#!/usr/bin/env bash
# Builds, signs, notarizes and publishes Freewire from rpi5, using the Mac mini as the build machine.
# shellcheck disable=SC2029,SC1091  # remote commands expand REMOTE_DIR/VERSION locally; ~/.1password is runtime-only
#
#   scripts/release.sh v1.0.0
#
# Needs: ssh mac-mini-server (Xcode, xcodegen, ~/.local/tmp/fl-import.sh + the G2 p12), the 1Password service
# account in ~/.1password, and gh. Secrets go from 1Password straight into the ssh stdin; nothing is printed.
set -euo pipefail
TAG="${1:?usage: release.sh vX.Y.Z}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v1.2.3" >&2; exit 1; }
VERSION="${TAG#v}"
here="$(cd "$(dirname "$0")/.." && pwd)"
MAC=mac-mini-server
REMOTE_DIR='GitHub/freewire'
VAULT=i7pl4yuyooocpafj4q6enlve2i          # SR98 - Certificates & Keys
P12_PASSWORD_ITEM=ymzbpjhuaxakxtzu6rhmilsq2y  # APPLE - Developer ID G2 p12 password (Freeleapp)
P8_DOCUMENT=rih2i5t25qdg4l7i5lw5dkdcda       # APPLE - App Store Connect API Key (Freeleapp 7X6ZGRV2U7)

marketing="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$here/project.yml")"
[ "$VERSION" = "$marketing" ] || { echo "tag $TAG does not match MARKETING_VERSION $marketing" >&2; exit 1; }
[ -z "$(git -C "$here" status --porcelain)" ] || { echo "the working tree has uncommitted changes" >&2; exit 1; }
[ "$(git -C "$here" rev-parse HEAD)" = "$(git -C "$here" rev-parse '@{u}' 2>/dev/null)" ] || { echo "push HEAD first" >&2; exit 1; }

echo "== sync and build on the Mac mini"
rsync -a --delete --exclude .git --exclude .build --exclude build --exclude dist --exclude '*.xcodeproj' "$here/" "$MAC:$REMOTE_DIR/"
# shellcheck disable=SC2029  # REMOTE_DIR is meant to expand here
ssh "$MAC" "cd $REMOTE_DIR && xcodegen generate --quiet && \
  (cd FreewireCore && { swift test > /tmp/freewire-test.log 2>&1 || { tail -30 /tmp/freewire-test.log; exit 1; }; } \
   && tail -1 /tmp/freewire-test.log) && \
  rm -rf build/Release dist && xcodebuild -project Freewire.xcodeproj -scheme Freewire -configuration Release \
  -derivedDataPath build/dd CONFIGURATION_BUILD_DIR=\$PWD/build/Release CODE_SIGNING_ALLOWED=NO build -quiet && \
  echo 'build ok'" < /dev/null

echo "== sign + notarize"
# shellcheck disable=SC1091
set -a; . "$HOME/.1password"; set +a
{
  op read -n "op://$VAULT/$P12_PASSWORD_ITEM/password"; echo
  op document get "$P8_DOCUMENT" --vault "$VAULT" | base64 -w0; echo
} | ssh "$MAC" "cd $REMOTE_DIR && ~/.local/tmp/fl-import.sh bash scripts/sign-notarize.sh $VERSION"

echo "== publish"
out="$(mktemp -d)"
scp -q "$MAC:$REMOTE_DIR/dist/Freewire-$VERSION.zip" "$MAC:$REMOTE_DIR/dist/Freewire-$VERSION.zip.sha256" "$out/"
# Leftover builds share the bundle id, so Launch Services could open one of them instead of the installed app
ssh "$MAC" "rm -rf $REMOTE_DIR/build $REMOTE_DIR/dist"
gh release create "$TAG" "$out/Freewire-$VERSION.zip" "$out/Freewire-$VERSION.zip.sha256" \
  --repo sergioarojasm98/freewire --target "$(git -C "$here" rev-parse HEAD)" \
  --title "Freewire $VERSION" --notes-file "$here/RELEASE_NOTES.md"
