#!/bin/zsh
set -euo pipefail

MDI_PROJECT_ROOT=${0:A:h:h}
MDI_SOURCE_ROOT="$MDI_PROJECT_ROOT/Sources"

typeset -a MDI_FORBIDDEN_PATTERNS
MDI_FORBIDDEN_PATTERNS=(
  'Process[[:space:]]*\('
  'URLSession'
  'FileManager\.default\.(removeItem|moveItem|replaceItem|createFile)'
  'NSWorkspace\.shared\.open.*terminal'
  '/usr/bin/sudo'
  'rm[[:space:]]+-rf'
)

for MDI_PATTERN in "${MDI_FORBIDDEN_PATTERNS[@]}"; do
  if command -v rg >/dev/null 2>&1; then
    MDI_MATCH_COMMAND=(rg --line-number --glob '*.swift' --regexp "$MDI_PATTERN" "$MDI_SOURCE_ROOT")
  else
    MDI_MATCH_COMMAND=(grep -EnR --include '*.swift' "$MDI_PATTERN" "$MDI_SOURCE_ROOT")
  fi

  if "${MDI_MATCH_COMMAND[@]}"; then
    print -u2 "Forbidden production-source pattern found: $MDI_PATTERN"
    exit 1
  fi
done

print "Source safety invariant scan passed."
