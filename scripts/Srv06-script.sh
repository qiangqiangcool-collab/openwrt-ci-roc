#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEVICE_CONFIG_FILE="${1:-}"
GENERAL_CONFIG_FILE="${2:-}"
FEED_LOCK_FILE="${FEED_LOCK_FILE:-}"
SOURCES_FILE="${THIRD_PARTY_SOURCES_FILE:-$PWD/third-party-sources.txt}"

for config_file in "$DEVICE_CONFIG_FILE" "$GENERAL_CONFIG_FILE"; do
  if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
    echo "Error: configuration file was not found: ${config_file:-<empty>}" >&2
    exit 1
  fi
done

if [ -z "$FEED_LOCK_FILE" ]; then
  echo "Error: FEED_LOCK_FILE is required for the srv06 build" >&2
  exit 1
fi
case "$FEED_LOCK_FILE" in
  /*) lock_path="$FEED_LOCK_FILE" ;;
  *) lock_path="$WORKSPACE/$FEED_LOCK_FILE" ;;
esac
if [ ! -f "$lock_path" ]; then
  echo "Error: feed lock file was not found: $lock_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCES_FILE")"
{
  printf 'Repository\tBranch\tCommit\n'
  printf '%s\t%s\t%s\n' \
    'https://github.com/laipeng668/immortalwrt.git' \
    'openwrt-25.12' \
    "$(git rev-parse HEAD)"
} > "$SOURCES_FILE"

while IFS=$'\t' read -r name repo_url branch commit extra; do
  case "$name" in
    '' | \#*) continue ;;
  esac
  if [ -n "${extra:-}" ] || [ -z "$repo_url" ] || [ -z "$branch" ] || [ -z "$commit" ]; then
    echo "Error: malformed feed lock row for $name" >&2
    exit 1
  fi
  actual_commit="$(git -C "feeds/$name" rev-parse HEAD)"
  if [ "$actual_commit" != "$commit" ]; then
    echo "Error: feed $name is not pinned: expected $commit, got $actual_commit" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\n' "$repo_url" "$branch" "$commit" >> "$SOURCES_FILE"
done < "$lock_path"

# Install only packages exposed by the already-pinned feeds. This dedicated build
# intentionally avoids Roc-script.sh because that script follows third-party HEADs.
./scripts/feeds update -i -a
./scripts/feeds install -a

# Docker must never fall back to the firmware overlay. It stays disabled until the
# dedicated ext4 data partition has been mounted and verified after flashing.
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-srv06-docker-storage <<'EOF'
#!/bin/sh

if uci -q get dockerd.globals >/dev/null 2>&1; then
	uci set dockerd.globals.data_root='/mnt/docker'
	uci set dockerd.globals.iptables='0'
	uci commit dockerd
fi

/etc/init.d/dockerd disable >/dev/null 2>&1 || true
exit 0
EOF
chmod 0755 files/etc/uci-defaults/99-srv06-docker-storage

# The qualcommax target adds its wireless userspace and drivers as defaults.
# Point6 is wired-only, so fail before the expensive compile if a future target
# or config change selects any of them again.
cat "$DEVICE_CONFIG_FILE" "$GENERAL_CONFIG_FILE" > .config
make defconfig >/dev/null
for forbidden_config in \
  CONFIG_PACKAGE_wpad-openssl \
  CONFIG_PACKAGE_hostapd-common \
  CONFIG_PACKAGE_kmod-ath11k \
  CONFIG_PACKAGE_kmod-ath11k-ahb \
  CONFIG_PACKAGE_kmod-ath11k-pci \
  CONFIG_PACKAGE_ath11k-firmware-ipq6018 \
  CONFIG_PACKAGE_ath11k-firmware-qcn9074 \
  CONFIG_PACKAGE_ipq-wifi-jdcloud_re-cs-02; do
  if grep -Fqx "${forbidden_config}=y" .config; then
    echo "Error: wired-only srv06 config unexpectedly enables $forbidden_config" >&2
    exit 1
  fi
done
