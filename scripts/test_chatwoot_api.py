#!/usr/bin/env python3
"""
Chatwoot API Test Script
This script tests the Chatwoot API connection and basic operations.
"""

import requests
import json

# Configuration - Update these with your actual values
CHATWOOT_URL = "https://your-chatwoot-instance.com"
API_ACCESS_TOKEN = "your_api_access_token"
ACCOUNT_ID = "your_account_id"

def test_connection():
    """Test basic API connection"""
    url = f"{CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/conversations"
    headers = {
        "api_access_token": API_ACCESS_TOKEN,
        "Content-Type": "application/json"
    }

    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        conversations = response.json()
        print("✓ Chatwoot API connection successful")
        print(f"Found {len(conversations.get('data', []))} conversations")
        return True
    else:
        print(f"✗ Chatwoot API connection failed: {response.status_code}")
        print(response.text)
        return False

def get_inboxes():
    """Get available inboxes"""
    url = f"{CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/inboxes"
    headers = {
        "api_access_token": API_ACCESS_TOKEN,
        "Content-Type": "application/json"
    }

    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        inboxes = response.json()
        print(f"✓ Retrieved {len(inboxes.get('data', []))} inboxes")
        for inbox in inboxes.get('data', []):
            print(f"  - {inbox['name']} (ID: {inbox['id']})")
        return inboxes
    else:
        print(f"✗ Failed to get inboxes: {response.status_code}")
        return None

def send_test_message(conversation_id, message):
    """Send a test message to a conversation"""
    url = f"{CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/conversations/{conversation_id}/messages"
    headers = {
        "api_access_token": API_ACCESS_TOKEN,
        "Content-Type": "application/json"
    }

    data = {
        "content": message,
        "message_type": "outgoing"
    }

    response = requests.post(url, json=data, headers=headers)

    if response.status_code == 200:
        message_data = response.json()
        print(f"✓ Sent test message: {message}")
        return message_data
    else:
        print(f"✗ Failed to send message: {response.status_code}")
        print(response.text)
        return None

if __name__ == "__main__":
    print("Testing Chatwoot API connection...")
    print("=" * 50)

    if test_connection():
        print("\nTesting inbox retrieval...")
        get_inboxes()

        print("\nNote: Message sending requires a valid conversation ID.")
        # Uncomment and modify the lines below to test message sending
        # conversation_id = "your_conversation_id"
        # send_test_message(conversation_id, "Test message from API")

    print("\nChatwoot API testing complete.")</content>
<parameter name="filePath">F:/github/chatwoot n8n ai agent/scripts/test_chatwoot_api.py