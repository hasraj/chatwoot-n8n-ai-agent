#!/usr/bin/env python3
"""
WooCommerce API Test Script
This script tests the WooCommerce REST API connection and basic operations.
"""

import requests
import json
from requests.auth import HTTPBasicAuth

# Configuration - Update these with your actual values
WOO_URL = "https://your-woocommerce-site.com"
CONSUMER_KEY = "your_consumer_key"
CONSUMER_SECRET = "your_consumer_secret"

def test_connection():
    """Test basic API connection"""
    url = f"{WOO_URL}/wp-json/wc/v3/"
    response = requests.get(url, auth=HTTPBasicAuth(CONSUMER_KEY, CONSUMER_SECRET))

    if response.status_code == 200:
        print("✓ API connection successful")
        return True
    else:
        print(f"✗ API connection failed: {response.status_code}")
        print(response.text)
        return False

def get_products():
    """Retrieve products"""
    url = f"{WOO_URL}/wp-json/wc/v3/products"
    response = requests.get(url, auth=HTTPBasicAuth(CONSUMER_KEY, CONSUMER_SECRET))

    if response.status_code == 200:
        products = response.json()
        print(f"✓ Retrieved {len(products)} products")
        if products:
            print(f"Sample product: {products[0]['name']} - ${products[0]['price']}")
        return products
    else:
        print(f"✗ Failed to get products: {response.status_code}")
        return None

def get_orders():
    """Retrieve orders"""
    url = f"{WOO_URL}/wp-json/wc/v3/orders"
    response = requests.get(url, auth=HTTPBasicAuth(CONSUMER_KEY, CONSUMER_SECRET))

    if response.status_code == 200:
        orders = response.json()
        print(f"✓ Retrieved {len(orders)} orders")
        if orders:
            print(f"Sample order: #{orders[0]['id']} - {orders[0]['status']}")
        return orders
    else:
        print(f"✗ Failed to get orders: {response.status_code}")
        return None

def create_test_order():
    """Create a test order (be careful with this!)"""
    url = f"{WOO_URL}/wp-json/wc/v3/orders"
    data = {
        "payment_method": "bacs",
        "payment_method_title": "Direct Bank Transfer",
        "set_paid": False,
        "billing": {
            "first_name": "Test",
            "last_name": "Customer",
            "address_1": "123 Test St",
            "city": "Test City",
            "postcode": "12345",
            "country": "US",
            "email": "test@example.com"
        },
        "line_items": [
            {
                "product_id": 1,  # Replace with actual product ID
                "quantity": 1
            }
        ]
    }

    response = requests.post(url, json=data, auth=HTTPBasicAuth(CONSUMER_KEY, CONSUMER_SECRET))

    if response.status_code == 201:
        order = response.json()
        print(f"✓ Created test order #{order['id']}")
        return order
    else:
        print(f"✗ Failed to create order: {response.status_code}")
        print(response.text)
        return None

if __name__ == "__main__":
    print("Testing WooCommerce API connection...")
    print("=" * 50)

    if test_connection():
        print("\nTesting product retrieval...")
        get_products()

        print("\nTesting order retrieval...")
        get_orders()

        print("\nNote: Order creation test commented out for safety.")
        # Uncomment the line below to test order creation (use with caution!)
        # create_test_order()

    print("\nAPI testing complete.")</content>
<parameter name="filePath">F:/github/chatwoot n8n ai agent/scripts/test_woocommerce_api.py