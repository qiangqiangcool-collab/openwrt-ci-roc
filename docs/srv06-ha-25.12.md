# Srv06 Home Assistant firmware baseline

This branch builds one wired-only image for JDCloud RE-CS-02. It is not a
generic QWRT image and it must not be flashed with `sysupgrade -F`.

## Frozen inputs

- CI baseline: `laipeng668/openwrt-ci-roc` commit
  `ef1b10c979fa8ad8f1caa123dd0241e3a39f1032`
- Firmware source: `laipeng668/immortalwrt` branch `openwrt-25.12`, commit
  `758d572f2c33ca850ca9f4de21904c212e0acdf1`
- Kernel: `6.12.103`
- Feed commits: `locks/srv06-ha-25.12.feeds.tsv`
- Target: `qualcommax/ipq60xx/jdcloud_re-cs-02`

The dedicated workflow uses `scripts/Srv06-script.sh`. It does not invoke the
upstream `Roc-script.sh`, because that script deliberately follows several
third-party repositories at their current branch heads.

## Runtime boundaries

- Wireless drivers and firmware are excluded.
- LACP requires both `kmod-bonding` and `proto-bonding`.
- Docker data root is `/mnt/docker`; Docker starts disabled.
- Docker iptables management is disabled. Home Assistant will use host
  networking, avoiding an extra Docker NAT/firewall path on the router.
- Docker may be enabled only after the dedicated ext4 data partition is mounted
  at `/mnt/docker` and a write/read test succeeds there.
- Home Assistant configuration belongs below
  `/mnt/docker/apps/homeassistant/config`, never in the firmware overlay.

## Flash gates

1. GitHub Actions build succeeds and the release contains the sysupgrade image,
   manifest, full `.config`, source-revision report, and checksums.
2. The manifest proves Docker, Compose, Dockerman, OpenClash, AdGuard Home,
   HAProxy, bonding, and ext4 support are present and no ath11k packages remain.
3. A fresh read-only inventory of point6 confirms the exact board, current image,
   partition table, boot slots, mounted data partition, LACP state, and package
   compatibility.
4. A fresh backup and a minimal selective-restore archive are created and
   checksum-verified. Never restore the old overlay wholesale.
5. `sysupgrade -T <image>` passes on point6. A failure stops the procedure; do
   not override it with `-F`.
6. Flash only in a wired maintenance window with a documented physical recovery
   route. Restore network/LACP first, then DNS/OpenClash, then Wol-Guard/HAProxy.
7. Mount `/mnt/docker`, verify it is the independent data filesystem, then enable
   Docker and deploy a pinned Home Assistant Container image.

The OpenClash selector state must be preserved. No build, restore, or acceptance
step is allowed to switch the user's current nodes.
