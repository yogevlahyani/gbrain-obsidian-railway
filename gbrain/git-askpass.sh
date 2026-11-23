#!/bin/sh
# Reads GITHUB_TOKEN from the environment. Never logs or echoes the token.
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN}" ;;
  *) printf '%s\n' "${GITHUB_TOKEN}" ;;
esac
