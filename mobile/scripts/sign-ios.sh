#!/bin/sh
# Builds a properly signed IPA.
#
# Two ways to authenticate, both of which require a credential that only the
# account holder can create:
#
#   1. Xcode is signed in (Xcode > Settings > Accounts).
#        ./scripts/sign-ios.sh
#
#   2. An App Store Connect API key (safer: revocable, no password).
#      Create one at App Store Connect > Users and Access > Integrations,
#      download the .p8 once, then:
#        AUTH_KEY=~/Downloads/AuthKey_ABC123.p8 \
#        KEY_ID=ABC123 \
#        ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#        ./scripts/sign-ios.sh
#
# Output: build/ipa/*.ipa

set -eu

TEAM="${TEAM:-G6XG9572FX}"
SCHEME=Runner
WORKSPACE=ios/Runner.xcworkspace
ARCHIVE=build/aurora_signed.xcarchive
EXPORT_DIR=build/ipa

if [ ! -d "$WORKSPACE" ]; then
  echo "Run this from the mobile/ directory" >&2
  exit 1
fi

AUTH_ARGS=""
if [ -n "${AUTH_KEY:-}" ]; then
  AUTH_ARGS="-authenticationKeyPath $AUTH_KEY -authenticationKeyID ${KEY_ID:?set KEY_ID} -authenticationKeyIssuerID ${ISSUER_ID:?set ISSUER_ID}"
  echo "Using App Store Connect API key ${KEY_ID}"
else
  echo "Using the Apple ID signed into Xcode"
fi

echo "Archiving…"
# shellcheck disable=SC2086
xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -configuration Release -sdk iphoneos \
  -archivePath "$ARCHIVE" archive \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates $AUTH_ARGS

echo "Exporting IPA…"
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates $AUTH_ARGS

echo
ls -lh "$EXPORT_DIR"
echo "Signed IPA ready. Install it with Xcode's Devices window, Apple Configurator, or AirDrop."
