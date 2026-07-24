#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_DERIVED_DATA="$MDI_PROJECT_ROOT/build/DerivedData"

xcodebuild \
  -project "$MDI_PROJECT_ROOT/MacDiskInspector.xcodeproj" \
  -scheme MacDiskInspector \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$MDI_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

print "Unsigned verification app:"
print "$MDI_DERIVED_DATA/Build/Products/Release/MacDiskInspector.app"
