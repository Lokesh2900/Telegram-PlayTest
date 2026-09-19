#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: package-unsigned-ipa.sh <path/to/TelegramPlay.app> [output.ipa]}"
OUTPUT="${2:-TelegramPlay-unsigned.ipa}"

APP_NAME="$(basename "$APP_PATH")"

rm -rf Payload
mkdir -p Payload
ditto "$APP_PATH" "Payload/$APP_NAME"
zip -qr "$OUTPUT" Payload
rm -rf Payload

echo "Created $OUTPUT from $APP_PATH"
