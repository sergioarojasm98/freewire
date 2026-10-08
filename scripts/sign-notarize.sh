#!/bin/bash
# Runs ON THE MAC inside ~/.local/tmp/fl-import.sh (which imported the Developer ID G2 identity into the temporary
# keychain $CSC_KEYCHAIN and consumed the p12 password from stdin). Reads one more stdin line: the App Store Connect
# API key (.p8) in base64. Signs build/Release/Freewire.app with the hardened runtime, notarizes it, staples the
# ticket and writes dist/Freewire-<version>.zip. Secrets only ever live in a 0600 temp file that is always removed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Release/Freewire.app"
KEY_ID="7X6ZGRV2U7"
ISSUER="42e462d3-4c6d-4cf9-8a13-c57e828a9f40"
VERSION="${1:?usage: sign-notarize.sh <version>}"
: "${CSC_KEYCHAIN:?run me through fl-import.sh}"

IFS= read -r P8_B64
KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT
chmod 700 "$KEYDIR"
printf '%s' "$P8_B64" | base64 -D > "$KEYDIR/AuthKey_$KEY_ID.p8"
unset P8_B64
chmod 600 "$KEYDIR/AuthKey_$KEY_ID.p8"

# The temp keychain has only the G2 identity; take its SHA-1 so the old G1 (same name, login keychain) can't be picked.
IDENTITY="$(security find-identity -v -p codesigning "$CSC_KEYCHAIN" | awk '/Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || { echo "no Developer ID identity in $CSC_KEYCHAIN" >&2; exit 1; }
echo "signing with ${IDENTITY:0:8}… (G2)"

codesign --force --options runtime --timestamp --keychain "$CSC_KEYCHAIN" --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier|Runtime Version|Identifier)=" || true

mkdir -p dist
SUBMIT="dist/Freewire-$VERSION-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --key "$KEYDIR/AuthKey_$KEY_ID.p8" --key-id "$KEY_ID" --issuer "$ISSUER" \
  --wait --timeout 30m --output-format json | tee dist/notarization.json | /usr/bin/python3 -c \
  'import json,sys; d=json.load(sys.stdin); print("notarization:", d.get("status"), d.get("id")); sys.exit(0 if d.get("status")=="Accepted" else 1)'
rm -f "$SUBMIT"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ZIP="dist/Freewire-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
