#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_APP_NAME="Mac 磁盘扫描助手.app"
MDI_BINARY_NAME="MacDiskInspector"
MDI_DERIVED_DATA=${MDI_DERIVED_DATA:-"$MDI_PROJECT_ROOT/build/DerivedData.noindex"}
MDI_APP_PATH="$MDI_DERIVED_DATA/Build/Products/Release/$MDI_APP_NAME"
MDI_OUTPUT_DIR="$MDI_PROJECT_ROOT/build/distribution"
MDI_DOCS_DIR="$MDI_PROJECT_ROOT/output/pdf"
MDI_DMG_ASSETS_DIR="$MDI_PROJECT_ROOT/Distribution/DMG"
MDI_DOCS_PYTHON=${MDI_DOCS_PYTHON:-/Users/wisdomfish/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}
MDI_DMGBUILD_VERSION="1.6.7"
MDI_DMGBUILD_DIR="$MDI_PROJECT_ROOT/build/tools/dmgbuild-$MDI_DMGBUILD_VERSION"
MDI_TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mdi-dmg.XXXXXX")
MDI_STAGE_DIR="$MDI_TEMP_ROOT/stage"
MDI_MOUNT_PATH=""

cleanup() {
  if [[ -n "$MDI_MOUNT_PATH" && -d "$MDI_MOUNT_PATH" ]]; then
    hdiutil detach "$MDI_MOUNT_PATH" -quiet || true
  fi
  if [[ -n "$MDI_TEMP_ROOT" && -d "$MDI_TEMP_ROOT" ]]; then
    rm -rf -- "$MDI_TEMP_ROOT"
  fi
}
trap cleanup EXIT

if [[ "${MDI_SKIP_APP_BUILD:-0}" == "1" ]]; then
  [[ -d "$MDI_APP_PATH" ]] || {
    print -u2 "MDI_SKIP_APP_BUILD=1, but the Release app is missing: $MDI_APP_PATH"
    exit 1
  }
else
  "$MDI_PROJECT_ROOT/Scripts/build-app.sh"
fi

if [[ ! -x "$MDI_DOCS_PYTHON" ]]; then
  MDI_DOCS_PYTHON=$(command -v python3)
fi
"$MDI_DOCS_PYTHON" "$MDI_PROJECT_ROOT/Scripts/generate-distribution-docs.py"
"$MDI_DOCS_PYTHON" "$MDI_PROJECT_ROOT/Scripts/generate-dmg-icon.py"

MDI_VERSION=$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "$MDI_APP_PATH/Contents/Info.plist"
)
MDI_RELEASE_LABEL=${MDI_RELEASE_LABEL:-$MDI_VERSION}

if [[ ! "$MDI_RELEASE_LABEL" =~ '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$' ]]; then
  print -u2 "Invalid MDI_RELEASE_LABEL. Use 1-64 letters, numbers, dots, underscores, or hyphens."
  exit 64
fi

MDI_DMG_PATH="$MDI_OUTPUT_DIR/Mac磁盘扫描助手-$MDI_RELEASE_LABEL-universal.dmg"
MDI_VOLUME_NAME="Mac 磁盘扫描助手 $MDI_RELEASE_LABEL"

mkdir -p "$MDI_STAGE_DIR" "$MDI_OUTPUT_DIR"
ditto "$MDI_APP_PATH" "$MDI_STAGE_DIR/$MDI_APP_NAME"
ln -s /Applications "$MDI_STAGE_DIR/Applications"
ditto "$MDI_DOCS_DIR/使用说明.pdf" "$MDI_STAGE_DIR/使用说明.pdf"
ditto "$MDI_DOCS_DIR/打不开？双击这里.pdf" "$MDI_STAGE_DIR/打不开？双击这里.pdf"
ditto "$MDI_DMG_ASSETS_DIR/打不开请看这里.txt" "$MDI_STAGE_DIR/打不开请看这里.txt"
mkdir -p "$MDI_STAGE_DIR/.background"
ditto "$MDI_DMG_ASSETS_DIR/background.png" "$MDI_STAGE_DIR/.background/background.png"
ditto "$MDI_DMG_ASSETS_DIR/background@2x.png" "$MDI_STAGE_DIR/.background/background@2x.png"

if ! PYTHONPATH="$MDI_DMGBUILD_DIR" "$MDI_DOCS_PYTHON" -c \
  "import importlib.metadata; assert importlib.metadata.version('dmgbuild') == '$MDI_DMGBUILD_VERSION'" \
  2>/dev/null; then
  mkdir -p "$MDI_DMGBUILD_DIR"
  "$MDI_DOCS_PYTHON" -m pip install \
    --disable-pip-version-check \
    --no-deps \
    --require-hashes \
    --target "$MDI_DMGBUILD_DIR" \
    -r "$MDI_PROJECT_ROOT/Scripts/requirements-dmg.txt"
fi

PYTHONPATH="$MDI_DMGBUILD_DIR" "$MDI_DOCS_PYTHON" -m dmgbuild \
  --settings "$MDI_DMG_ASSETS_DIR/layout-settings.py" \
  -Dsource="$MDI_STAGE_DIR" \
  -Dassets="$MDI_DMG_ASSETS_DIR" \
  "$MDI_VOLUME_NAME" \
  "$MDI_DMG_PATH"

hdiutil verify "$MDI_DMG_PATH"

MDI_ATTACH_OUTPUT=$(hdiutil attach -readonly -nobrowse "$MDI_DMG_PATH")
MDI_MOUNT_PATH=$(
  print -r -- "$MDI_ATTACH_OUTPUT" |
    awk -F '\t' 'END { print $NF }'
)
MDI_MOUNTED_APP="$MDI_MOUNT_PATH/$MDI_APP_NAME"
MDI_MOUNTED_BINARY="$MDI_MOUNTED_APP/Contents/MacOS/$MDI_BINARY_NAME"

[[ -d "$MDI_MOUNTED_APP" ]] || {
  print -u2 "$MDI_APP_NAME is missing from the mounted DMG."
  exit 1
}
[[ -L "$MDI_MOUNT_PATH/Applications" ]] || {
  print -u2 "Applications shortcut is missing from the mounted DMG."
  exit 1
}
[[ "$(readlink "$MDI_MOUNT_PATH/Applications")" == "/Applications" ]] || {
  print -u2 "Applications shortcut does not point to /Applications."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/使用说明.pdf" ]] || {
  print -u2 "使用说明.pdf is missing from the mounted DMG."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/打不开？双击这里.pdf" ]] || {
  print -u2 "打不开？双击这里.pdf is missing from the mounted DMG."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/打不开请看这里.txt" ]] || {
  print -u2 "打不开请看这里.txt is missing from the mounted DMG."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/.VolumeIcon.icns" ]] || {
  print -u2 "The mounted volume icon is missing."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/.background.tiff" || -f "$MDI_MOUNT_PATH/.background.png" ]] || {
  print -u2 "The DMG background is missing."
  exit 1
}
[[ -f "$MDI_MOUNT_PATH/.DS_Store" ]] || {
  print -u2 "The DMG Finder layout is missing."
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$MDI_MOUNTED_APP"
lipo "$MDI_MOUNTED_BINARY" -verify_arch arm64 x86_64

MDI_DISPLAY_NAME=$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleDisplayName" \
    "$MDI_MOUNTED_APP/Contents/Info.plist"
)
[[ "$MDI_DISPLAY_NAME" == "Mac 磁盘扫描助手" ]] || {
  print -u2 "Unexpected app display name: $MDI_DISPLAY_NAME"
  exit 1
}

print "DMG package verification passed."
print "App: $MDI_APP_NAME"
print "Architectures: $(lipo -archs "$MDI_MOUNTED_BINARY")"
print "DMG: $MDI_DMG_PATH"
print "SHA-256:"
shasum -a 256 "$MDI_DMG_PATH"
