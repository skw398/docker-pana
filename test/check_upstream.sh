#!/bin/sh
# Detects when a pinned tool is out of date for its reference:
# - Dart, Flutter, pana and dartdoc are compared with pub.dev's worker, because
#   they must match pub.dev for scoring.
# - WebP is compared with pub.dev's pin too, but only flags when pub.dev moves
#   past this image: WebP here is deliberately one security fix newer than
#   pub.dev's vulnerable 1.3.0.
# - pana's transitive dependencies are compared with pub.dev's workspace
#   lockfile, which resolves them together with the other workspace members.
#
# It also checks that the Dockerfile labels match the versions actually pinned
# in the download URLs, paths, and the README version table.
#
# Requires network access.
# Exit codes: 0 = no drift, 1 = drift, 2 = error or an inconsistent Dockerfile.
# Usage: sh test/check_upstream.sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

dockerfile="$repo_root/Dockerfile"

label() {
  grep "dev\.docker-pana\.$1=" "$dockerfile" | head -1 | sed 's/.*="\([^"]*\)".*/\1/'
}

ours_dart="$(label dart)"
ours_flutter="$(label flutter)"
ours_pana="$(label pana)"
ours_dartdoc="$(label dartdoc)"
ours_webp="$(label webp)"

# Internal consistency: the labels must match the pinned URLs and paths.
pinned_dart="$(sed -n 's#.*dart-archive/channels/stable/release/\([0-9.]*\)/sdk/.*#\1#p' "$dockerfile" | head -1)"
pinned_flutter="$(sed -n 's#.*flutter_linux_\([0-9.]*\)-stable\.tar\.xz.*#\1#p' "$dockerfile" | head -1)"
pinned_webp="$(sed -n 's#.*libwebp-\([0-9.]*\)-linux-x86-64\.tar\.gz.*#\1#p' "$dockerfile" | head -1)"
pinned_pana_path="$(sed -n 's#.*pana-\([0-9.]*\)/bin/pana\.dart.*#\1#p' "$dockerfile" | head -1)"
pinned_pana_pubspec="$(sed -n "s/^  pana: *'\([^']*\)'.*/\1/p" "$repo_root/runtime/pubspec.yaml" | head -1)"
pinned_dartdoc="$(sed -n 's#.*dart pub unpack dartdoc:\([0-9.]*\) .*#\1#p' "$dockerfile" | head -1)"

inconsistent=0

# Compare each label with the version found in its source.
match() {
  field="$1"
  label_value="$2"
  pinned_value="$3"
  where="$4"
  if [ -z "$pinned_value" ]; then
    printf '%s: could not read the version from %s\n' "$field" "$where" >&2
    inconsistent=1
  elif [ "$label_value" != "$pinned_value" ]; then
    printf '%s: label=%s but %s=%s\n' "$field" "$label_value" "$where" "$pinned_value" >&2
    inconsistent=1
  fi
}

match Dart "$ours_dart" "$pinned_dart" "the Dart download URL"
match Flutter "$ours_flutter" "$pinned_flutter" "the Flutter download URL"
match WebP "$ours_webp" "$pinned_webp" "the WebP download URL"
match pana "$ours_pana" "$pinned_pana_path" "the pana compile path"
match pana "$ours_pana" "$pinned_pana_pubspec" "runtime/pubspec.yaml"
match dartdoc "$ours_dartdoc" "$pinned_dartdoc" "the dartdoc unpack version"

readme_version() {
  awk -F'|' -v name="$1" '
    { gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3)
      if ($2 == name) { print $3; exit } }
  ' "$repo_root/README.md"
}

match Dart "$ours_dart" "$(readme_version Dart)" "the README table"
match Flutter "$ours_flutter" "$(readme_version Flutter)" "the README table"
match WebP "$ours_webp" "$(readme_version WebP)" "the README table"
match pana "$ours_pana" "$(readme_version pana)" "the README table"
match dartdoc "$ours_dartdoc" "$(readme_version dartdoc)" "the README table"

if [ "$inconsistent" -eq 1 ]; then
  printf '\nThe Dockerfile labels do not match the pinned URLs, paths, or the README table.\n' >&2
  exit 2
fi

base="https://raw.githubusercontent.com/dart-lang/pub-dev/main"
curl --fail --silent --show-error --retry 3 "$base/Dockerfile.worker" -o "$tmp/worker" 2>/dev/null || {
  printf 'could not fetch Dockerfile.worker\n' >&2
  exit 2
}
curl --fail --silent --show-error --retry 3 "$base/pkg/pub_worker/pubspec.yaml" -o "$tmp/pubspec" 2>/dev/null || {
  printf 'could not fetch pubspec.yaml\n' >&2
  exit 2
}
curl --fail --silent --show-error --retry 3 "$base/tool/setup-webp.sh" -o "$tmp/webp" 2>/dev/null || {
  printf 'could not fetch setup-webp.sh\n' >&2
  exit 2
}

up_dart="$(awk '/setup-dart\.sh/ {print $NF; exit}' "$tmp/worker")"
up_flutter="$(awk '/setup-flutter\.sh/ {print $NF; exit}' "$tmp/worker")"
up_dartdoc="$(awk '/setup-dartdoc\.sh/ {print $NF; exit}' "$tmp/worker")"
up_pana="$(grep '^  pana:' "$tmp/pubspec" | head -1 | awk '{print $2}' | tr -d '^')"
up_webp="$(sed -n 's/^LIBWEBP_VERSION="\([^"]*\)".*/\1/p' "$tmp/webp" | head -1)"

drift=0
check() {
  name="$1"
  ours="$2"
  reference="$3"
  upstream="$4"
  if [ -n "$ours" ] && [ -n "$upstream" ] && [ "$ours" = "$upstream" ]; then
    printf '%-8s docker-pana=%s  %s=%s  ok\n' "$name" "$ours" "$reference" "$upstream"
  else
    printf '%-8s docker-pana=%s  %s=%s  CHANGED\n' "$name" "$ours" "$reference" "$upstream"
    # shellcheck disable=SC2016  # the backticks are literal Markdown
    printf -- '- %s: this image `%s`, %s `%s`\n' \
      "$name" "$ours" "$reference" "$upstream" >> "$tmp/drift"
    drift=1
  fi
}

check Dart "$ours_dart" pub.dev "$up_dart"
check Flutter "$ours_flutter" pub.dev "$up_flutter"
check pana "$ours_pana" pub.dev "$up_pana"
check dartdoc "$ours_dartdoc" pub.dev "$up_dartdoc"

# WebP is intentionally newer than pub.dev's pin, so it is flagged when pub.dev
# moves past this image, or when its pin could not be read.
if [ -z "$up_webp" ]; then
  printf '%-8s docker-pana=%s  pub.dev=%s  CHANGED\n' WebP "$ours_webp" unknown
  printf -- "- WebP: could not read pub.dev's WebP pin.\n" >> "$tmp/drift"
  drift=1
elif [ "$up_webp" != "$ours_webp" ] \
  && [ "$(printf '%s\n' "$ours_webp" "$up_webp" | sort -V | tail -1)" = "$up_webp" ]; then
  printf '%-8s docker-pana=%s  pub.dev=%s  CHANGED\n' WebP "$ours_webp" "$up_webp"
  # shellcheck disable=SC2016  # the backticks are literal Markdown
  printf -- '- WebP: pub.dev now pins `%s`, newer than this image (`%s`).\n' \
    "$up_webp" "$ours_webp" >> "$tmp/drift"
  drift=1
else
  printf '%-8s docker-pana=%s  pub.dev=%s  ok\n' WebP "$ours_webp" "$up_webp"
fi

# pana's transitive dependencies drift independently of the pana version.
deps_status=0
deps_output="$(sh "$repo_root/test/check_pana_deps.sh" 2>&1)" || deps_status=$?
case "$deps_status" in
  0)
    printf '%-8s matches the pub.dev workspace lock  ok\n' Deps
    ;;
  1)
    printf '%-8s differs from the pub.dev workspace lock  CHANGED\n' Deps
    printf '%s\n' "$deps_output" >> "$tmp/drift"
    drift=1
    ;;
  *)
    printf '%s\n' "$deps_output" >&2
    exit 2
    ;;
esac

if [ "$drift" -eq 1 ]; then
  printf '\nThe following versions differ from their reference:\n\n'
  cat "$tmp/drift"
  printf '\nUpdate the pinned versions (Dockerfile, runtime/pubspec.yaml, or runtime/pubspec.lock) and rebuild.\n'
  exit 1
fi
printf '\nNo drift.\n'
