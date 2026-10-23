#!/bin/sh
# Prints the docker image for the action to run.
#
# Uses PANA_IMAGE when set, otherwise derives it from PANA_ACTION_REPOSITORY
# (e.g. OWNER/docker-pana -> ghcr.io/owner/docker-pana:latest).
set -eu

if [ -n "${PANA_IMAGE:-}" ]; then
  printf '%s\n' "$PANA_IMAGE"
  exit 0
fi

if [ -z "${PANA_ACTION_REPOSITORY:-}" ]; then
  printf '%s\n' 'Set image when invoking docker-pana as a local action.' >&2
  exit 2
fi

printf 'ghcr.io/%s:latest\n' \
  "$(printf '%s' "$PANA_ACTION_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
