#!/bin/sh
# Checks the image-resolution logic used by action.yml (scripts/resolve_image.sh).
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/scripts/resolve_image.sh"
fail=0

# check <name> <expected output> <expected exit> [VAR=VALUE ...]
check() {
  name="$1"
  want_output="$2"
  want_status="$3"
  shift 3
  status=0
  got="$(env -i PATH="$PATH" "$@" sh "$script" 2>/dev/null)" || status=$?
  if [ "$status" -ne "$want_status" ] || [ "$got" != "$want_output" ]; then
    printf '%s: want (status=%s, output=%s), got (status=%s, output=%s)\n' \
      "$name" "$want_status" "$want_output" "$status" "$got" >&2
    fail=1
  fi
}

check "explicit image" "example/image:tag" 0 PANA_IMAGE=example/image:tag
check "derived image" "ghcr.io/owner/docker-pana:latest" 0 \
  PANA_ACTION_REPOSITORY=Owner/docker-pana
check "explicit wins" "local/img:tag" 0 \
  PANA_IMAGE=local/img:tag PANA_ACTION_REPOSITORY=Owner/docker-pana
check "missing repository" "" 2

if [ "$fail" -ne 0 ]; then
  printf 'image resolution check failed\n' >&2
  exit 1
fi
printf 'image resolution: ok\n'
