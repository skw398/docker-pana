#!/bin/sh
# Compares this image's pana score for a published package with the score that
# pub.dev currently reports.
#
# This is a manual aid, not part of CI. pub.dev may have scored a different
# version, or used a different pana/SDK at the time it last analyzed the
# package, so a mismatch is a signal to compare the per-section details rather
# than proof that this image is wrong.
#
# Usage: sh test/compare_with_pub_dev.sh <docker-image> <package>
set -eu

image="${1:?usage: compare_with_pub_dev.sh <docker-image> <package>}"
package="${2:?usage: compare_with_pub_dev.sh <docker-image> <package>}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

status=0
docker run --rm --platform linux/amd64 --memory 4g \
  --cap-drop=ALL --security-opt no-new-privileges --pids-limit 4096 \
  "$image" --hosted "$package" > "$tmp/out" 2> "$tmp/err" || status=$?
if [ "$status" -ne 0 ]; then
  printf 'pana exited with code %s\n' "$status" >&2
  tail -n 5 "$tmp/err" >&2 || true
  exit 1
fi

json="$(curl --fail --silent --show-error --retry 3 "https://pub.dev/api/packages/$package/score")" || {
  printf 'could not fetch the pub.dev score\n' >&2
  exit 2
}
json="$(printf '%s' "$json" | tr -d '[:space:]')"

local_total="$(sed -n 's/^Points: \([0-9]*\)\/\([0-9]*\)\.$/\1 \2/p' "$tmp/out" | head -1)"
local_granted="${local_total% *}"
local_max="${local_total#* }"
remote_granted="$(printf '%s' "$json" | grep -o '"grantedPoints":[0-9]*' | head -1 | cut -d: -f2)"
remote_max="$(printf '%s' "$json" | grep -o '"maxPoints":[0-9]*' | head -1 | cut -d: -f2)"

printf '%s\n' "$package"
printf '  docker-pana: %s/%s\n' "$local_granted" "$local_max"
printf '  pub.dev    : %s/%s\n' "$remote_granted" "$remote_max"
printf '  sections (docker-pana):\n'
grep '^## ' "$tmp/out" | sed 's/^## //' || true

if [ "$local_granted" = "$remote_granted" ] && [ "$local_max" = "$remote_max" ]; then
  printf 'MATCH\n'
else
  printf 'MISMATCH (see the note in the script header)\n'
  exit 1
fi
