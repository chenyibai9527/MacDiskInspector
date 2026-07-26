#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_DERIVED_DATA=${MDI_DERIVED_DATA:-"$MDI_PROJECT_ROOT/build/DerivedData.noindex"}
MDI_BUILD_NUMBER=${MDI_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}
MDI_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [[ ! "$MDI_BUILD_NUMBER" =~ '^[0-9]{1,18}$' ]]; then
  print -u2 "Invalid MDI_BUILD_NUMBER. Use 1-18 digits."
  exit 64
fi

xcodebuild \
  -project "$MDI_PROJECT_ROOT/MacDiskInspector.xcodeproj" \
  -scheme MacDiskInspector \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$MDI_DERIVED_DATA" \
  CURRENT_PROJECT_VERSION="$MDI_BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build

MDI_APP_PATH="$MDI_DERIVED_DATA/Build/Products/Release/Mac 磁盘扫描助手.app"

codesign \
  --force \
  --deep \
  --sign - \
  --options runtime \
  --entitlements "$MDI_PROJECT_ROOT/App/MacDiskInspector.entitlements" \
  "$MDI_APP_PATH"

codesign --verify --deep --strict --verbose=2 "$MDI_APP_PATH"

if [[ -x "$MDI_LSREGISTER" ]]; then
  if ! "$MDI_LSREGISTER" -u "$MDI_APP_PATH"; then
    print -u2 "Warning: could not unregister the local build from LaunchServices."
  else
    print "LaunchServices: local build unregistered."
  fi
fi

print "Ad-hoc signed verification app with read-only sandbox:"
print "$MDI_APP_PATH"
print "Build number: $MDI_BUILD_NUMBER"
