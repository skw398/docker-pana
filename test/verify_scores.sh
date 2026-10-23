#!/bin/sh
# Verifies pana's per-section scoring for the fixtures.
#
# The goal of this image is to produce the same score as pub.dev, but a
# successful build only proves that analysis runs. This check pins the expected
# points for every report section, including a fixture that intentionally misses
# points, so that environment changes that alter scoring are caught.
#
# It parses pana's human-readable report, whose format is fixed because pana is
# pinned. Only sh, docker and the usual core utilities are required.
#
# Usage: sh test/verify_scores.sh <docker-image> [fixture ...]
set -eu

image="${1:?usage: verify_scores.sh <docker-image> [fixture ...]}"
shift || true
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

all_fixtures="sample_package flutter_package partial_score_package"
fixtures="${*:-$all_fixtures}"

for fixture in $fixtures; do
  case " $all_fixtures " in
    *" $fixture "*) ;;
    *) printf 'unknown fixture: %s; available: %s\n' "$fixture" "$all_fixtures" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Expected "<granted> <max> <section title>" per fixture.
expectations() {
  case "$1" in
    partial_score_package) cat <<'EOF'
15 30 Follow Dart file conventions
0 20 Provide documentation
20 20 Platform support
30 50 Pass static analysis
40 40 Support up-to-date dependencies
EOF
      ;;
    *) cat <<'EOF'
30 30 Follow Dart file conventions
20 20 Provide documentation
20 20 Platform support
50 50 Pass static analysis
40 40 Support up-to-date dependencies
EOF
      ;;
  esac
}

expected_total() {
  case "$1" in
    partial_score_package) printf '105 160' ;;
    *) printf '160 160' ;;
  esac
}

fail=0
for fixture in $fixtures; do
  out="$tmp/$fixture.out"
  err="$tmp/$fixture.err"
  mount="type=bind,src=$repo_root/test/fixtures/$fixture,dst=/package,readonly"

  status=0
  docker run --rm --platform linux/amd64 --memory 4g \
    --cap-drop=ALL --security-opt no-new-privileges --pids-limit 4096 \
    --mount "$mount" "$image" /package > "$out" 2> "$err" || status=$?
  if [ "$status" -ne 0 ]; then
    printf '%s: pana exited with code %s\n' "$fixture" "$status" >&2
    tail -n 5 "$err" >&2 || true
    fail=1
    continue
  fi

  fixture_ok=1
  expectations "$fixture" > "$tmp/expected"
  while read -r granted max title; do
    got="$(grep -F "$title (" "$out" | head -1 | sed 's/.*(\([0-9]*\) \/ \([0-9]*\)).*/\1 \2/')"
    if [ "$got" != "$granted $max" ]; then
      fixture_ok=0
      fail=1
      printf '%s: %s expected %s/%s, got %s\n' \
        "$fixture" "$title" "$granted" "$max" "${got:-none}" >&2
    fi
  done < "$tmp/expected"

  total="$(expected_total "$fixture")"
  expected_granted="${total% *}"
  expected_max="${total#* }"
  got="$(sed -n 's/^Points: \([0-9]*\)\/\([0-9]*\)\.$/\1 \2/p' "$out" | head -1)"
  if [ "$got" != "$total" ]; then
    fixture_ok=0
    fail=1
    printf '%s: total expected %s/%s, got %s\n' \
      "$fixture" "$expected_granted" "$expected_max" "${got:-none}" >&2
  fi

  # The advertised contract: with --exit-code-threshold 0, pana exits non-zero
  # unless the package scores the maximum.
  missing=$((expected_max - expected_granted))
  if [ "$missing" -gt 0 ]; then
    threshold_status=0
    docker run --rm --platform linux/amd64 --memory 4g \
      --cap-drop=ALL --security-opt no-new-privileges --pids-limit 4096 \
      --mount "$mount" "$image" --exit-code-threshold 0 /package \
      > /dev/null 2>&1 || threshold_status=$?
    if [ "$threshold_status" -eq 0 ]; then
      fixture_ok=0
      fail=1
      printf '%s: expected a non-zero exit with --exit-code-threshold 0\n' "$fixture" >&2
    fi
  fi

  if [ "$fixture_ok" -eq 1 ]; then
    printf '%s: ok (total %s/%s)\n' "$fixture" "${got% *}" "${got#* }"
  fi
done

if [ "$fail" -ne 0 ]; then
  printf 'Score verification failed.\n' >&2
  exit 1
fi
printf 'All score expectations matched.\n'
