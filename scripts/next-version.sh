#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: next-version.sh <Info.plist version> [latest tag]" >&2
  exit 2
fi

configured_version=$1
last_tag=${2-}

# Older source plists used major.minor. Keep that form valid for later edits.
if [[ "$configured_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
  configured_version="${configured_version}.0"
fi

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "$configured_version" =~ $version_pattern ]]; then
  echo "::error::Info.plist version '$configured_version' is not a valid X.Y.Z version" >&2
  exit 1
fi

if [[ -z "$last_tag" ]]; then
  printf '%s\n' "$configured_version"
  exit 0
fi

tag_version=${last_tag#v}
if [[ "$last_tag" != v* ]] || ! [[ "$tag_version" =~ $version_pattern ]]; then
  echo "::error::Latest tag '$last_tag' is not a valid vX.Y.Z version" >&2
  exit 1
fi

IFS=. read -r configured_major configured_minor configured_patch <<< "$configured_version"
IFS=. read -r tag_major tag_minor tag_patch <<< "$tag_version"

# A deliberate version bump in Info.plist wins. Otherwise keep the existing
# automatic patch-release behavior for ordinary pushes to main.
if (( configured_major > tag_major ||
      (configured_major == tag_major && configured_minor > tag_minor) ||
      (configured_major == tag_major && configured_minor == tag_minor && configured_patch > tag_patch) )); then
  printf '%s\n' "$configured_version"
else
  printf '%s.%s.%s\n' "$tag_major" "$tag_minor" "$((tag_patch + 1))"
fi
