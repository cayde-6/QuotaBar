#!/usr/bin/env bash
set -euo pipefail

expect_version() {
  local actual
  actual=$(bash scripts/next-version.sh "$1" "$2")
  if [[ "$actual" != "$3" ]]; then
    echo "Expected $3 for configured=$1, tag=$2; got $actual" >&2
    exit 1
  fi
}

expect_version 1.1.0 v1.0.15 1.1.0
expect_version 1.1.0 v1.1.0 1.1.1
expect_version 1.0.0 v1.1.4 1.1.5
expect_version 1.2.0 v1.1.4 1.2.0
expect_version 1.0 v1.0.15 1.0.16
expect_version 1.1.0 '' 1.1.0

if bash scripts/next-version.sh 1.1.0 v1.0.bad >/dev/null 2>&1; then
  echo 'Invalid release tags must fail' >&2
  exit 1
fi
