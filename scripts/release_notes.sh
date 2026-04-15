#!/usr/bin/env bash
set -euo pipefail

CURRENT_TAG="${1:?usage: release_notes.sh <current-tag>}"

previous_tag() {
  git tag --list 'v*' --sort=-v:refname \
    | while IFS= read -r tag; do
        if [[ "$tag" != "$CURRENT_TAG" ]]; then
          echo "$tag"
          break
        fi
      done
}

filter_subjects() {
  awk '
    BEGIN { IGNORECASE = 1 }
    /^bump version/ { next }
    /^bump build/ { next }
    /^version bump/ { next }
    /^build bump/ { next }
    { print }
  '
}

PREVIOUS_TAG="$(previous_tag || true)"

if [[ -n "$PREVIOUS_TAG" ]]; then
  echo "## Changes since $PREVIOUS_TAG"
  echo
  NOTES="$(git log --format=%s "$PREVIOUS_TAG"..HEAD | filter_subjects)"
else
  echo "## Initial release"
  echo
  NOTES="$(git log --format=%s | filter_subjects)"
fi

if [[ -n "$NOTES" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "- $line"
  done <<< "$NOTES"
else
  echo "- Release generated from the checked-in versioned source state."
fi
