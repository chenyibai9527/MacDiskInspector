#!/bin/zsh
set -euo pipefail

: "${MDI_TEAM_ID:?Set MDI_TEAM_ID to your Apple Developer Team ID}"
: "${MDI_NOTARY_PROFILE:?Set MDI_NOTARY_PROFILE to a notarytool keychain profile}"

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_RELEASE_ROOT="$MDI_PROJECT_ROOT/build/release"
MDI_ARCHIVE_PATH="$MDI_RELEASE_ROOT/MacDiskInspector.xcarchive"
MDI_EXPORT_PATH="$MDI_RELEASE_ROOT/export"
MDI_ZIP_PATH="$MDI_RELEASE_ROOT/MacDiskInspector.zip"

mkdir -p "$MDI_RELEASE_ROOT"

xcodebuild \
  -project "$MDI_PROJECT_ROOT/MacDiskInspector.xcodeproj" \
  -scheme MacDiskInspector \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$MDI_ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$MDI_TEAM_ID" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$MDI_ARCHIVE_PATH" \
  -exportPath "$MDI_EXPORT_PATH" \
  -exportOptionsPlist "$MDI_PROJECT_ROOT/App/ExportOptions.plist"

ditto -c -k --keepParent \
  "$MDI_EXPORT_PATH/MacDiskInspector.app" \
  "$MDI_ZIP_PATH"

xcrun notarytool submit \
  "$MDI_ZIP_PATH" \
  --keychain-profile "$MDI_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$MDI_EXPORT_PATH/MacDiskInspector.app"
codesign --verify --deep --strict --verbose=2 "$MDI_EXPORT_PATH/MacDiskInspector.app"
spctl --assess --type execute --verbose=4 "$MDI_EXPORT_PATH/MacDiskInspector.app"

print "Notarized app:"
print "$MDI_EXPORT_PATH/MacDiskInspector.app"
