#!/bin/sh
# Wires Google OAuth into the build without editing Dart code.
#
#   ./scripts/configure-google.sh <ios-client-id> [web-client-id] [api-key]
#
# Produces:
#   mobile/google.json   – used by --dart-define-from-file (gitignored)
#   ios/Runner/Info.plist – CFBundleURLSchemes gets the reversed client id
#
# The reversed id is what Google reads from the redirect URL. Format:
#   790541594186-abc.apps.googleusercontent.com
#   com.googleusercontent.apps.790541594186-abc

set -eu

IOS_ID="${1:?pass the iOS client id}"
WEB_ID="${2:-}"
API_KEY="${3:-${YOUTUBE_API_KEY:-}}"

case "$IOS_ID" in
  *.apps.googleusercontent.com) ;;
  *) echo "That does not look like a client id: $IOS_ID" >&2; exit 1 ;;
esac

PREFIX="${IOS_ID%.apps.googleusercontent.com}"
REVERSED="com.googleusercontent.apps.$PREFIX"

# Preserve keys that were not passed, so configuring iOS never drops Android.
ANDROID_ID="${ANDROID_ID:-}"
if [ -f google.json ] && [ -z "$ANDROID_ID" ]; then
  ANDROID_ID=$(sed -n 's/.*"GOOGLE_ANDROID_CLIENT_ID": *"\([^"]*\)".*/\1/p' google.json)
fi

cat > google.json <<EOF
{
  "GOOGLE_ANDROID_CLIENT_ID": "$ANDROID_ID",
  "GOOGLE_CLIENT_ID": "$IOS_ID",
  "GOOGLE_SERVER_CLIENT_ID": "$WEB_ID",
  "YOUTUBE_API_KEY": "$API_KEY"
}
EOF
echo "wrote google.json"
echo "  ios client:   $IOS_ID"
[ -n "$WEB_ID" ] && echo "  web client:   $WEB_ID" || echo "  web client:   (empty)"
[ -n "$API_KEY" ] && echo "  api key:      ${API_KEY%????}…" || echo "  api key:      (empty)"

PLIST=ios/Runner/Info.plist
if [ ! -f "$PLIST" ]; then
  echo "Run this from the mobile/ directory" >&2
  exit 1
fi

# Replace any previous CFBundleURLTypes with a single Google scheme.
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleURLTypes array" \
  -c "Add :CFBundleURLTypes:0 dict" \
  -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Editor" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $REVERSED" \
  "$PLIST"

echo "registered URL scheme: $REVERSED"
echo
echo "Build with:"
echo "  flutter build apk --release --dart-define-from-file=google.json"
