#!/bin/sh
# Detects drift between runtime/pubspec.lock and the lockfile pub.dev resolves.
#
# pub.dev uses a pub workspace: pkg/pub_worker is a member, so its dependencies
# are resolved together with the other members. For example, pkg/api_builder
# requires analyzer ^13.0.0, which keeps the workspace on analyzer 13.x even
# though pana allows <15.0.0. The workspace lockfile is committed at the
# repository root, so it is the reference for pana's transitive dependencies.
#
# Requires network access.
# Exit codes: 0 = no drift, 1 = drift, 2 = error.
# Usage: sh test/check_pana_deps.sh
set -eu
export LC_ALL=C

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://raw.githubusercontent.com/dart-lang/pub-dev/main/pubspec.lock"
curl --fail --silent --show-error --retry 3 "$url" -o "$tmp/upstream" || {
  printf 'could not fetch the pub.dev workspace lockfile\n' >&2
  exit 2
}

versions() {
  awk '
    /^  [a-zA-Z0-9_]+:/ { name = $1; sub(":", "", name) }
    /^    version: / { version = $2; gsub(/"/, "", version); print name " " version }
  ' "$1" | sort
}

versions "$repo_root/runtime/pubspec.lock" > "$tmp/pinned"
versions "$tmp/upstream" > "$tmp/resolved"

awk '
  NR == FNR { pinned[$1] = $2; next }
  { resolved[$1] = $2 }
  END {
    for (name in pinned) {
      if (!(name in resolved)) {
        printf "- %s: missing from the pub.dev workspace lock (`%s`)\n", name, pinned[name]
      } else if (pinned[name] != resolved[name]) {
        printf "- %s: this image `%s`, pub.dev workspace `%s`\n", name, pinned[name], resolved[name]
      }
    }
  }
' "$tmp/pinned" "$tmp/resolved" | sort > "$tmp/drift"

if [ -s "$tmp/drift" ]; then
  cat "$tmp/drift"
  exit 1
fi

printf 'pana dependencies match the pub.dev workspace lock.\n'
exit 0
