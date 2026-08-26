#!/usr/bin/env bash
set -Eeuo pipefail

LOCK_FILE="${1:-}"

if [ -z "$LOCK_FILE" ] || [ ! -f "$LOCK_FILE" ]; then
  echo "Error: feed lock file was not found: ${LOCK_FILE:-<empty>}" >&2
  exit 1
fi

if [ ! -x ./scripts/feeds ] || [ ! -d feeds ]; then
  echo "Error: run Pin-feeds.sh from the OpenWrt source root after feeds update" >&2
  exit 1
fi

locked_count=0
while IFS=$'\t' read -r name repo_url branch commit extra; do
  case "$name" in
    '' | \#*) continue ;;
  esac

  if [ -n "${extra:-}" ] || [ -z "$repo_url" ] || [ -z "$branch" ] || [ -z "$commit" ]; then
    echo "Error: malformed feed lock row for $name" >&2
    exit 1
  fi
  case "$name" in
    *[!A-Za-z0-9_-]*)
      echo "Error: invalid feed name: $name" >&2
      exit 1
      ;;
  esac
  if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: invalid commit for feed $name: $commit" >&2
    exit 1
  fi

  feed_dir="feeds/$name"
  if [ ! -d "$feed_dir/.git" ]; then
    echo "Error: feed directory was not cloned: $feed_dir" >&2
    exit 1
  fi

  actual_origin="$(git -C "$feed_dir" remote get-url origin)"
  if [ "${actual_origin%.git}" != "${repo_url%.git}" ]; then
    echo "Error: feed URL mismatch for $name: expected $repo_url, got $actual_origin" >&2
    exit 1
  fi

  git -C "$feed_dir" fetch --depth=1 origin "$commit"
  git -C "$feed_dir" checkout --detach "$commit"
  actual_commit="$(git -C "$feed_dir" rev-parse HEAD)"
  if [ "$actual_commit" != "$commit" ]; then
    echo "Error: feed commit mismatch for $name: expected $commit, got $actual_commit" >&2
    exit 1
  fi

  locked_count=$((locked_count + 1))
  printf 'Pinned feed %s (%s) at %s\n' "$name" "$branch" "$commit"
done < "$LOCK_FILE"

if [ "$locked_count" -eq 0 ]; then
  echo "Error: feed lock file contains no feed rows: $LOCK_FILE" >&2
  exit 1
fi
