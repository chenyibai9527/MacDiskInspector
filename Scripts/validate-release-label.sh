#!/bin/bash
set -euo pipefail

MDI_PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
MDI_PROJECT_FILE="$MDI_PROJECT_ROOT/MacDiskInspector.xcodeproj/project.pbxproj"
MDI_CHANGELOG="$MDI_PROJECT_ROOT/CHANGELOG.md"
MDI_RELEASE_LABEL=${1:-}

if [[ ! "$MDI_RELEASE_LABEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "Invalid release label: $MDI_RELEASE_LABEL" >&2
  echo "Use a version such as 0.2.3-preview.2 or 0.2.4." >&2
  exit 64
fi

MDI_APP_VERSION=${MDI_RELEASE_LABEL%%-*}
MDI_PROJECT_VERSIONS=$(
  sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
    "$MDI_PROJECT_FILE" |
    sort -u
)
MDI_PROJECT_VERSION_COUNT=$(
  printf '%s\n' "$MDI_PROJECT_VERSIONS" |
    sed '/^$/d' |
    wc -l |
    tr -d ' '
)

if [[ "$MDI_PROJECT_VERSION_COUNT" != "1" ]]; then
  echo "Expected one MARKETING_VERSION across Xcode configurations, found:" >&2
  printf '%s\n' "$MDI_PROJECT_VERSIONS" >&2
  exit 1
fi

if [[ "$MDI_PROJECT_VERSIONS" != "$MDI_APP_VERSION" ]]; then
  echo "Release label $MDI_RELEASE_LABEL targets app version $MDI_APP_VERSION," >&2
  echo "but the Xcode project MARKETING_VERSION is $MDI_PROJECT_VERSIONS." >&2
  exit 1
fi

if ! grep -Fq "## [$MDI_RELEASE_LABEL] -" "$MDI_CHANGELOG"; then
  echo "CHANGELOG.md has no release section for $MDI_RELEASE_LABEL." >&2
  echo "Move the intended entries out of 未发布 before publishing." >&2
  exit 1
fi

printf 'release_label=%s\n' "$MDI_RELEASE_LABEL"
printf 'release_tag=v%s\n' "$MDI_RELEASE_LABEL"
printf 'app_version=%s\n' "$MDI_APP_VERSION"
