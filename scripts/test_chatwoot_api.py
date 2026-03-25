#!/usr/bin/env python3
"""
Chatwoot API smoke tests.

Configuration is read from environment variables:
  CHATWOOT_BASE_URL
  CHATWOOT_API_TOKEN
  CHATWOOT_ACCOUNT_ID
  CHATWOOT_TEST_CONVERSATION_ID (optional)
"""

from __future__ import annotations

import os
import sys
from typing import Any

import requests


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        print(f"[ERROR] Missing environment variable: {name}")
        sys.exit(1)
    return value


CHATWOOT_BASE_URL = require_env("CHATWOOT_BASE_URL").rstrip("/")
CHATWOOT_API_TOKEN = require_env("CHATWOOT_API_TOKEN")
CHATWOOT_ACCOUNT_ID = require_env("CHATWOOT_ACCOUNT_ID")
CHATWOOT_TEST_CONVERSATION_ID = os.getenv("CHATWOOT_TEST_CONVERSATION_ID", "").strip()


def chatwoot_request(method: str, path: str, **kwargs: Any) -> requests.Response:
    response = requests.request(
        method=method,
        url=f"{CHATWOOT_BASE_URL}{path}",
        headers={
            "api_access_token": CHATWOOT_API_TOKEN,
            "Content-Type": "application/json",
        },
        timeout=30,
        **kwargs,
    )
    return response


def print_result(label: str, response: requests.Response) -> None:
    status = response.status_code
    icon = "[OK]" if 200 <= status < 300 else "[FAIL]"
    print(f"{icon} {label}: HTTP {status}")
    if status >= 400:
        print(response.text[:1000])


def test_conversations() -> bool:
    response = chatwoot_request(
        "GET",
        f"/api/v1/accounts/{CHATWOOT_ACCOUNT_ID}/conversations",
        params={"page": 1},
    )
    print_result("List conversations", response)
    if response.status_code != 200:
        return False

    payload = response.json()
    conversations = payload.get("data", {}).get("payload", []) or payload.get("payload", [])
    print(f"Found {len(conversations)} conversation(s) on the first page")
    return True


def test_inboxes() -> bool:
    response = chatwoot_request("GET", f"/api/v1/accounts/{CHATWOOT_ACCOUNT_ID}/inboxes")
    print_result("List inboxes", response)
    if response.status_code != 200:
        return False

    payload = response.json()
    inboxes = payload.get("payload", []) or payload.get("data", {}).get("payload", [])
    for inbox in inboxes[:10]:
        print(f"- Inbox #{inbox.get('id')}: {inbox.get('name')}")
    return True


def test_webhooks() -> bool:
    response = chatwoot_request("GET", f"/api/v1/accounts/{CHATWOOT_ACCOUNT_ID}/webhooks")
    print_result("List webhooks", response)
    if response.status_code != 200:
        return False

    webhooks = response.json().get("payload", [])
    for webhook in webhooks[:10]:
        print(f"- Webhook #{webhook.get('id')}: {webhook.get('url')}")
    return True


def test_messages() -> bool:
    if not CHATWOOT_TEST_CONVERSATION_ID:
        print("[SKIP] CHATWOOT_TEST_CONVERSATION_ID not set, skipping conversation message test")
        return True

    response = chatwoot_request(
        "GET",
        f"/api/v1/accounts/{CHATWOOT_ACCOUNT_ID}/conversations/{CHATWOOT_TEST_CONVERSATION_ID}/messages",
    )
    print_result("Get conversation messages", response)
    if response.status_code != 200:
        return False

    payload = response.json()
    contact = (payload.get("meta", {}).get("contact", {}).get("payload") or [{}])[0]
    phone_number = contact.get("phone_number")
    print(f"Conversation contact phone: {phone_number or 'n/a'}")
    print(f"Message count returned: {len(payload.get('payload', []))}")
    return True


def main() -> int:
    print("Running Chatwoot API smoke tests")
    print("=" * 40)

    checks = [
        test_conversations(),
        test_inboxes(),
        test_webhooks(),
        test_messages(),
    ]

    if all(checks):
        print("\nAll Chatwoot smoke tests passed.")
        return 0

    print("\nOne or more Chatwoot smoke tests failed.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
