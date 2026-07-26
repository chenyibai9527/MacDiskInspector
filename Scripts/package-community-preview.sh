#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_APP_PATH="$MDI_PROJECT_ROOT/build/DerivedData/Build/Products/Release/Mac 磁盘扫描助手.app"
MDI_OUTPUT_DIR="$MDI_PROJECT_ROOT/build/community"
MDI_RELEASE_LABEL=${MDI_RELEASE_LABEL:-0.2.0-rc5}
MDI_ZIP_PATH="$MDI_OUTPUT_DIR/MacDiskInspector-$MDI_RELEASE_LABEL-universal-community.zip"

if [[ ! "$MDI_RELEASE_LABEL" =~ '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$' ]]; then
  print -u2 "Invalid MDI_RELEASE_LABEL. Use 1-64 letters, numbers, dots, underscores, or hyphens."
  exit 64
fi

"$MDI_PROJECT_ROOT/Scripts/build-app.sh"

codesign --verify --deep --strict --verbose=2 "$MDI_APP_PATH"

mkdir -p "$MDI_OUTPUT_DIR"
ditto -c -k --keepParent "$MDI_APP_PATH" "$MDI_ZIP_PATH"

print "Ad-hoc signed community build:"
print "$MDI_ZIP_PATH"
shasum -a 256 "$MDI_ZIP_PATH"
