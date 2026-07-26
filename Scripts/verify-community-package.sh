#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 <community-package.zip>"
  exit 64
fi

MDI_ZIP_PATH=$1
if [[ ! -f "$MDI_ZIP_PATH" ]]; then
  print -u2 "Package not found: $MDI_ZIP_PATH"
  exit 66
fi

MDI_VERIFY_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/mdi-package-verify.XXXXXX")
trap 'rm -rf "$MDI_VERIFY_TEMP"' EXIT

ditto -x -k "$MDI_ZIP_PATH" "$MDI_VERIFY_TEMP"
MDI_APP_PATH="$MDI_VERIFY_TEMP/Mac 磁盘扫描助手.app"
MDI_BINARY_PATH="$MDI_APP_PATH/Contents/MacOS/MacDiskInspector"
MDI_PRIVACY_PATH="$MDI_APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
MDI_ENTITLEMENTS_PATH="$MDI_VERIFY_TEMP/entitlements.plist"

[[ -d "$MDI_APP_PATH" ]] || {
  print -u2 "Mac 磁盘扫描助手.app is missing from package root."
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$MDI_APP_PATH"
lipo "$MDI_BINARY_PATH" -verify_arch arm64 x86_64

codesign -d --entitlements :- "$MDI_APP_PATH" > "$MDI_ENTITLEMENTS_PATH" 2>/dev/null
plutil -lint "$MDI_ENTITLEMENTS_PATH"

[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$MDI_ENTITLEMENTS_PATH")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.files.user-selected.read-only" "$MDI_ENTITLEMENTS_PATH")" == "true" ]]

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" "$MDI_ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  print -u2 "Unexpected network client entitlement."
  exit 1
fi

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.server" "$MDI_ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  print -u2 "Unexpected network server entitlement."
  exit 1
fi

[[ -f "$MDI_PRIVACY_PATH" ]] || {
  print -u2 "PrivacyInfo.xcprivacy is missing."
  exit 1
}
plutil -lint "$MDI_PRIVACY_PATH"

MDI_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MDI_APP_PATH/Contents/Info.plist")
MDI_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MDI_APP_PATH/Contents/Info.plist")

print "Community package verification passed."
print "Version: $MDI_VERSION ($MDI_BUILD)"
print "Architectures: $(lipo -archs "$MDI_BINARY_PATH")"
print "SHA-256:"
shasum -a 256 "$MDI_ZIP_PATH"
