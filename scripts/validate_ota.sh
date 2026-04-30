#!/bin/bash

echo ">>> Checking OTA URL..."

# 1. Check for the dummy plug
if [[ "${OTA_URL}" == "*enter url"* ]]; then
  echo "[-] Error: Dummy URL detected. You forgot to paste the link!"
  exit 1
fi

# 2. Enforce official Google AOSP domain whitelist
if [[ "${OTA_URL}" != "https://dl.google.com/dl/android/aosp/"* ]]; then
  echo "[-] Error: Invalid domain! URL must start with https://dl.google.com/dl/android/aosp/"
  exit 1
fi

# 3. Ping the URL headers to ensure it returns a 200 OK status
if ! curl --output /dev/null --silent --head --fail "${OTA_URL}"; then
  echo "[-] Error: OTA URL is dead or returned a 404. Aborting build."
  exit 1
fi

echo "[+] OTA URL is valid, official, and live!"
