#!/usr/bin/env python3
"""
Export WooCommerce appointments into Google Sheets.

This script prefers the newer WooCommerce Appointments endpoint and falls back
to the legacy endpoint automatically:
  - /wp-json/wc/v3/appointments
  - /wp-json/wc-appointments/v1/appointments

Required environment variables:
  WOOCOMMERCE_BASE_URL
  WOOCOMMERCE_CONSUMER_KEY
  WOOCOMMERCE_CONSUMER_SECRET
  GOOGLE_SERVICE_ACCOUNT_FILE
  GOOGLE_APPOINTMENTS_SHEET_ID

Optional environment variables:
  GOOGLE_APPOINTMENTS_SHEET_NAME         default: Appointments
  WOOCOMMERCE_APPOINTMENTS_AFTER         example: 2026-04-01T00:00:00
  WOOCOMMERCE_APPOINTMENTS_STATUS        default: any
  WOOCOMMERCE_APPOINTMENTS_PER_PAGE      default: 100
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import gspread
import requests
from gspread.exceptions import WorksheetNotFound
from requests.auth import HTTPBasicAuth


APPOINTMENT_HEADERS = [
    "appointment_id",
    "user_id",
    "email",
    "order_id",
    "status",
    "customer_status",
    "start",
    "end",
    "date_created",
    "date_modified",
    "source_endpoint",
    "synced_at",
]

APPOINTMENT_ENDPOINTS = (
    "/wp-json/wc/v3/appointments",
    "/wp-json/wc-appointments/v1/appointments",
)


@dataclass(frozen=True)
class Settings:
    woo_base_url: str
    woo_consumer_key: str
    woo_consumer_secret: str
    google_service_account_file: str
    google_sheet_id: str
    google_sheet_name: str
    appointments_after: str
    appointments_status: str
    appointments_per_page: int


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        print(f"[ERROR] Missing environment variable: {name}")
        sys.exit(1)
    return value


def parse_positive_int(name: str, default: int) -> int:
    raw_value = os.getenv(name, str(default)).strip() or str(default)
    try:
        return max(int(raw_value), 1)
    except ValueError:
        print(f"[ERROR] Invalid integer value for {name}: {raw_value}")
        sys.exit(1)


def load_settings() -> Settings:
    return Settings(
        woo_base_url=require_env("WOOCOMMERCE_BASE_URL").rstrip("/"),
        woo_consumer_key=require_env("WOOCOMMERCE_CONSUMER_KEY"),
        woo_consumer_secret=require_env("WOOCOMMERCE_CONSUMER_SECRET"),
        google_service_account_file=require_env("GOOGLE_SERVICE_ACCOUNT_FILE"),
        google_sheet_id=require_env("GOOGLE_APPOINTMENTS_SHEET_ID"),
        google_sheet_name=os.getenv(
            "GOOGLE_APPOINTMENTS_SHEET_NAME", "Appointments"
        ).strip()
        or "Appointments",
        appointments_after=os.getenv("WOOCOMMERCE_APPOINTMENTS_AFTER", "").strip(),
        appointments_status=os.getenv(
            "WOOCOMMERCE_APPOINTMENTS_STATUS", "any"
        ).strip()
        or "any",
        appointments_per_page=parse_positive_int(
            "WOOCOMMERCE_APPOINTMENTS_PER_PAGE",
            100,
        ),
    )


def build_auth(settings: Settings) -> HTTPBasicAuth:
    return HTTPBasicAuth(
        settings.woo_consumer_key,
        settings.woo_consumer_secret,
    )


def woo_get(
    settings: Settings,
    path: str,
    *,
    params: dict[str, Any] | None = None,
) -> requests.Response:
    return requests.get(
        f"{settings.woo_base_url}{path}",
        params=params or {},
        auth=build_auth(settings),
        timeout=30,
    )


def fetch_appointments(settings: Settings) -> tuple[str, list[dict[str, Any]]]:
    params: dict[str, Any] = {
        "per_page": settings.appointments_per_page,
        "orderby": "id",
        "order": "asc",
    }
    if settings.appointments_after:
        params["after"] = settings.appointments_after
    if settings.appointments_status.lower() != "any":
        params["status"] = settings.appointments_status

    last_error = ""
    for endpoint in APPOINTMENT_ENDPOINTS:
        page = 1
        appointments: list[dict[str, Any]] = []

        while True:
            response = woo_get(settings, endpoint, params={**params, "page": page})

            if response.status_code == 404 and page == 1:
                last_error = (
                    f"{endpoint} returned 404, trying the next appointments endpoint."
                )
                break

            if response.status_code != 200:
                last_error = (
                    f"{endpoint} returned HTTP {response.status_code}: "
                    f"{response.text[:500]}"
                )
                break

            payload = response.json()
            if not isinstance(payload, list):
                last_error = f"{endpoint} did not return a JSON array."
                break

            appointments.extend(item for item in payload if isinstance(item, dict))

            total_pages = int(response.headers.get("X-WP-TotalPages", "1") or "1")
            if page >= total_pages or len(payload) < settings.appointments_per_page:
                print(
                    f"[OK] Loaded {len(appointments)} appointment(s) from {endpoint}"
                )
                return endpoint, appointments

            page += 1

    print(f"[ERROR] Could not fetch appointments. {last_error}")
    sys.exit(1)


def fetch_order(
    settings: Settings,
    order_id: int | str | None,
    cache: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if not order_id:
        return {}

    cache_key = str(order_id)
    if cache_key in cache:
        return cache[cache_key]

    response = woo_get(settings, f"/wp-json/wc/v3/orders/{cache_key}")
    if response.status_code != 200:
        print(
            f"[WARN] Could not load order #{cache_key}. "
            f"HTTP {response.status_code}: {response.text[:200]}"
        )
        cache[cache_key] = {}
        return cache[cache_key]

    payload = response.json()
    cache[cache_key] = payload if isinstance(payload, dict) else {}
    return cache[cache_key]


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def normalize_email(value: Any) -> str:
    return normalize_text(value).lower()


def build_row(
    appointment: dict[str, Any],
    order: dict[str, Any],
    source_endpoint: str,
) -> dict[str, str]:
    billing = order.get("billing", {}) if isinstance(order.get("billing"), dict) else {}
    appointment_customer = (
        appointment.get("customer", {})
        if isinstance(appointment.get("customer"), dict)
        else {}
    )
    user_id = (
        appointment.get("customer_id")
        or order.get("customer_id")
        or ""
    )
    email = (
        billing.get("email")
        or appointment_customer.get("email")
        or appointment.get("billing_email")
        or appointment.get("email")
        or ""
    )
    synced_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    return {
        "appointment_id": normalize_text(appointment.get("id")),
        "user_id": normalize_text(user_id),
        "email": normalize_email(email),
        "order_id": normalize_text(appointment.get("order_id")),
        "status": normalize_text(
            appointment.get("status") or appointment.get("appointment_status")
        ),
        "customer_status": normalize_text(appointment.get("customer_status")),
        "start": normalize_text(appointment.get("start")),
        "end": normalize_text(appointment.get("end")),
        "date_created": normalize_text(appointment.get("date_created")),
        "date_modified": normalize_text(appointment.get("date_modified")),
        "source_endpoint": source_endpoint,
        "synced_at": synced_at,
    }


def column_letter(index: int) -> str:
    result = ""
    current = index
    while current > 0:
        current, remainder = divmod(current - 1, 26)
        result = chr(65 + remainder) + result
    return result


def get_worksheet(settings: Settings) -> gspread.Worksheet:
    client = gspread.service_account(filename=settings.google_service_account_file)
    spreadsheet = client.open_by_key(settings.google_sheet_id)

    try:
        worksheet = spreadsheet.worksheet(settings.google_sheet_name)
    except WorksheetNotFound:
        worksheet = spreadsheet.add_worksheet(
            title=settings.google_sheet_name,
            rows=1000,
            cols=max(len(APPOINTMENT_HEADERS), 12),
        )

    return worksheet


def ensure_headers(worksheet: gspread.Worksheet) -> None:
    current_headers = worksheet.row_values(1)
    if current_headers == APPOINTMENT_HEADERS:
        return

    worksheet.update(
        range_name=f"A1:{column_letter(len(APPOINTMENT_HEADERS))}1",
        values=[APPOINTMENT_HEADERS],
        value_input_option="RAW",
    )


def get_existing_row_map(worksheet: gspread.Worksheet) -> dict[str, int]:
    values = worksheet.get_all_values()
    row_map: dict[str, int] = {}
    for index, row in enumerate(values[1:], start=2):
        if not row:
            continue
        appointment_id = normalize_text(row[0] if row else "")
        if appointment_id:
            row_map[appointment_id] = index
    return row_map


def row_to_values(row: dict[str, str]) -> list[str]:
    return [row.get(header, "") for header in APPOINTMENT_HEADERS]


def print_preview(rows: list[dict[str, str]], limit: int) -> None:
    preview = rows[:limit]
    if not preview:
        print("[INFO] No appointment rows to preview.")
        return

    print(f"[INFO] Previewing {len(preview)} row(s)")
    for row in preview:
        print(
            f"- appointment_id={row['appointment_id']} | "
            f"user_id={row['user_id'] or '0'} | "
            f"email={row['email'] or 'n/a'} | "
            f"order_id={row['order_id'] or 'n/a'} | "
            f"status={row['status'] or 'n/a'}"
        )


def sync_rows(worksheet: gspread.Worksheet, rows: list[dict[str, str]]) -> tuple[int, int]:
    ensure_headers(worksheet)
    existing_rows = get_existing_row_map(worksheet)
    last_column = column_letter(len(APPOINTMENT_HEADERS))

    updated = 0
    appended = 0
    append_buffer: list[list[str]] = []

    for row in rows:
        appointment_id = row.get("appointment_id", "")
        if not appointment_id:
            continue

        values = row_to_values(row)
        row_index = existing_rows.get(appointment_id)

        if row_index:
            worksheet.update(
                range_name=f"A{row_index}:{last_column}{row_index}",
                values=[values],
                value_input_option="USER_ENTERED",
            )
            updated += 1
        else:
            append_buffer.append(values)

    if append_buffer:
        worksheet.append_rows(
            append_buffer,
            value_input_option="USER_ENTERED",
        )
        appended = len(append_buffer)

    return updated, appended


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export WooCommerce appointments into Google Sheets."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch and print rows without writing to Google Sheets.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Only process the first N appointment rows.",
    )
    parser.add_argument(
        "--preview",
        type=int,
        default=10,
        help="Number of rows to print during --dry-run. Default: 10",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    settings = load_settings()
    source_endpoint, appointments = fetch_appointments(settings)

    order_cache: dict[str, dict[str, Any]] = {}
    rows: list[dict[str, str]] = []

    for appointment in appointments:
        order = fetch_order(settings, appointment.get("order_id"), order_cache)
        rows.append(build_row(appointment, order, source_endpoint))

    rows.sort(key=lambda row: int(row["appointment_id"] or "0"))

    if args.limit > 0:
        rows = rows[: args.limit]

    print(f"[INFO] Prepared {len(rows)} appointment row(s) for export")

    if args.dry_run:
        print_preview(rows, max(args.preview, 1))
        print("[INFO] Dry run finished. No Google Sheet changes were made.")
        return 0

    worksheet = get_worksheet(settings)
    updated, appended = sync_rows(worksheet, rows)
    print(
        "[OK] Google Sheet sync finished. "
        f"updated={updated}, appended={appended}, sheet={settings.google_sheet_name}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
