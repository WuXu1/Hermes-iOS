#!/bin/sh
# Builds an unsigned Release IPA for sideloading (the sideloading tool re-signs it).
#
#   scripts/build_unsigned_ipa.sh [output.ipa]
#
# Output defaults to HermesMobile-unsigned.ipa in the repo root.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/HermesMobile-unsigned.ipa"}
DERIVED="$ROOT/build/DerivedData-release"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

xcodebuild \
    -project "$ROOT/HermesMobile.xcodeproj" \
    -scheme HermesMobile \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

APP="$DERIVED/Build/Products/Release-iphoneos/HermesMobile.app"
mkdir -p "$STAGING/Payload"
cp -R "$APP" "$STAGING/Payload/"
rm -f "$OUTPUT"
(cd "$STAGING" && zip -qry "$OUTPUT" Payload)

echo "Built $OUTPUT"
file "$APP/HermesMobile"
