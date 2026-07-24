#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_BENCHMARK="$MDI_PROJECT_ROOT/.build/release/DiskInspectorBenchmark"

cd "$MDI_PROJECT_ROOT"
swift build -c release --product DiskInspectorBenchmark

for MDI_FILE_COUNT in 10000 50000 100000; do
  if (( MDI_FILE_COUNT <= 10000 )); then
    MDI_DIRECTORY_COUNT=100
  elif (( MDI_FILE_COUNT <= 50000 )); then
    MDI_DIRECTORY_COUNT=200
  else
    MDI_DIRECTORY_COUNT=400
  fi

  "$MDI_BENCHMARK" \
    --files "$MDI_FILE_COUNT" \
    --directories "$MDI_DIRECTORY_COUNT" \
    --payload-bytes 1 \
    --aggregation-depth 3
done
