#!/usr/bin/env python3
"""
WooCommerce API smoke tests.

Configuration is read from environment variables:
  WOOCOMMERCE_BASE_URL
  WOOCOMMERCE_CONSUMER_KEY
  WOOCOMMERCE_CONSUMER_SECRET
  WOOCOMMERCE_TEST_ORDER_ID (optional)
  WOOCOMMERCE_TEST_PRODUCT_SEARCH (optional)
"""

from __future__ import annotations

import os
import sys
from typing import Any

import requests
from requests.auth import HTTPBasicAuth


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        print(f"[ERROR] Missing environment variable: {name}")
        sys.exit(1)
    return value


WOOCOMMERCE_BASE_URL = require_env("WOOCOMMERCE_BASE_URL").rstrip("/")
WOOCOMMERCE_CONSUMER_KEY = require_env("WOOCOMMERCE_CONSUMER_KEY")
WOOCOMMERCE_CONSUMER_SECRET = require_env("WOOCOMMERCE_CONSUMER_SECRET")
WOOCOMMERCE_TEST_ORDER_ID = os.getenv("WOOCOMMERCE_TEST_ORDER_ID", "").strip()
WOOCOMMERCE_TEST_PRODUCT_SEARCH = os.getenv("WOOCOMMERCE_TEST_PRODUCT_SEARCH", "").strip()


def woo_request(path: str, **kwargs: Any) -> requests.Response:
    return requests.get(
        f"{WOOCOMMERCE_BASE_URL}{path}",
        auth=HTTPBasicAuth(WOOCOMMERCE_CONSUMER_KEY, WOOCOMMERCE_CONSUMER_SECRET),
        timeout=30,
        **kwargs,
    )


def print_result(label: str, response: requests.Response) -> None:
    status = response.status_code
    icon = "[OK]" if 200 <= status < 300 else "[FAIL]"
    print(f"{icon} {label}: HTTP {status}")
    if status >= 400:
        print(response.text[:1000])


def test_root() -> bool:
    response = woo_request("/wp-json/wc/v3/")
    print_result("Woo root endpoint", response)
    return response.status_code == 200


def test_products() -> bool:
    params = {"per_page": 3}
    if WOOCOMMERCE_TEST_PRODUCT_SEARCH:
        params["search"] = WOOCOMMERCE_TEST_PRODUCT_SEARCH

    response = woo_request("/wp-json/wc/v3/products", params=params)
    print_result("List/search products", response)
    if response.status_code != 200:
        return False

    products = response.json()
    for product in products[:3]:
        print(
            f"- Product #{product.get('id')}: {product.get('name')} | "
            f"price={product.get('price')} | stock={product.get('stock_status')}"
        )
    return True


def test_orders() -> bool:
    response = woo_request("/wp-json/wc/v3/orders", params={"per_page": 3})
    print_result("List orders", response)
    if response.status_code != 200:
        return False

    orders = response.json()
    for order in orders[:3]:
        print(
            f"- Order #{order.get('id')}: status={order.get('status')} | "
            f"total={order.get('total')} {order.get('currency')}"
        )
    return True


def test_specific_order() -> bool:
    if not WOOCOMMERCE_TEST_ORDER_ID:
        print("[SKIP] WOOCOMMERCE_TEST_ORDER_ID not set, skipping single-order lookup")
        return True

    response = woo_request(f"/wp-json/wc/v3/orders/{WOOCOMMERCE_TEST_ORDER_ID}")
    print_result("Get specific order", response)
    if response.status_code != 200:
        return False

    order = response.json()
    customer_name = " ".join(
        part
        for part in [
            order.get("billing", {}).get("first_name", ""),
            order.get("billing", {}).get("last_name", ""),
        ]
        if part
    )
    print(
        f"Order #{order.get('id')} -> status={order.get('status')} | "
        f"customer={customer_name or 'n/a'}"
    )
    return True


def main() -> int:
    print("Running WooCommerce API smoke tests")
    print("=" * 40)

    checks = [
        test_root(),
        test_products(),
        test_orders(),
        test_specific_order(),
    ]

    if all(checks):
        print("\nAll WooCommerce smoke tests passed.")
        return 0

    print("\nOne or more WooCommerce smoke tests failed.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
