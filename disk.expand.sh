#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PV="/dev/sda3"
MOUNTPOINT="/"
ASSUME_YES="false"
DRY_RUN="false"

usage() {
  cat <<EOF
Ubuntu LVM auto-grow script

Default behavior:
  Automatically uses /dev/sda3

Usage:
  sudo $0 [options]

Options:
  -y, --yes       Do not prompt for confirmation
  --dry-run       Show what would be done, do not change anything
  -h, --help      Show help

Examples:
  sudo $0 --dry-run
  sudo $0 -y
EOF
}

log() {
  echo "[+] $*"
}

warn() {
  echo "[!] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

trim() {
  awk '{$1=$1; print}'
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || die "Run as root with sudo."

need_cmd findmnt
need_cmd lsblk
need_cmd lvs
need_cmd pvs
need_cmd vgs
need_cmd pvresize
need_cmd lvextend
need_cmd growpart
need_cmd partprobe
need_cmd udevadm

log "Checking root filesystem"

SRC="$(findmnt -n -o SOURCE --target "$MOUNTPOINT" | head -n1 | trim)"
FSTYPE="$(findmnt -n -o FSTYPE --target "$MOUNTPOINT" | head -n1 | trim)"

[[ -n "$SRC" ]] || die "Could not detect root filesystem source."

LV_PATH="$(lvs --noheadings -o lv_path "$SRC" 2>/dev/null | trim || true)"

if [[ -z "$LV_PATH" ]]; then
  SRC_REAL="$(readlink -f "$SRC" || true)"
  LV_PATH="$(lvs --noheadings -o lv_path "$SRC_REAL" 2>/dev/null | trim || true)"
fi

[[ -n "$LV_PATH" ]] || die "Root filesystem does not appear to be on LVM. Source was: $SRC"

VG_NAME="$(lvs --noheadings -o vg_name "$LV_PATH" | trim)"
LV_NAME="$(lvs --noheadings -o lv_name "$LV_PATH" | trim)"

[[ -n "$VG_NAME" ]] || die "Could not detect VG name."
[[ -n "$LV_NAME" ]] || die "Could not detect LV name."

log "Checking for default PV: $DEFAULT_PV"

[[ -b "$DEFAULT_PV" ]] || die "$DEFAULT_PV does not exist. This script is set to use /dev/sda3 automatically."

PV_VG="$(pvs --noheadings -o vg_name "$DEFAULT_PV" 2>/dev/null | trim || true)"

[[ -n "$PV_VG" ]] || die "$DEFAULT_PV exists, but it is not an LVM physical volume."
[[ "$PV_VG" == "$VG_NAME" ]] || die "$DEFAULT_PV belongs to VG '$PV_VG', but root is using VG '$VG_NAME'."

PV_DEV="$DEFAULT_PV"
DISK="/dev/sda"
PART_NUM="3"

cat <<EOF

Detected layout:

  Root mountpoint:  $MOUNTPOINT
  Filesystem:       $FSTYPE
  Root source:      $SRC
  LV path:          $LV_PATH
  VG name:          $VG_NAME
  LV name:          $LV_NAME
  PV device:        $PV_DEV
  Disk:             $DISK
  Partition:        $PART_NUM

Current disk layout:

EOF

lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS "$DISK"

case "$FSTYPE" in
  ext2|ext3|ext4|xfs)
    ;;
  *)
    warn "Filesystem '$FSTYPE' may not be supported by automatic resize."
    ;;
esac

if [[ "$ASSUME_YES" != "true" && "$DRY_RUN" != "true" ]]; then
  echo
  read -r -p "Type EXPAND to grow /dev/sda3 and extend $LV_PATH: " CONFIRM
  [[ "$CONFIRM" == "EXPAND" ]] || die "Cancelled."
fi

log "Rescanning disk $DISK"

if [[ -w /sys/class/block/sda/device/rescan ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] echo 1 > /sys/class/block/sda/device/rescan"
  else
    echo 1 > /sys/class/block/sda/device/rescan
  fi
else
  warn "Could not rescan /dev/sda from sysfs. Continuing anyway."
fi

run partprobe "$DISK" || true
run udevadm settle || true

log "Growing partition /dev/sda3"
run growpart "$DISK" "$PART_NUM"

log "Refreshing partition table"
run partprobe "$DISK" || true
run udevadm settle || true

log "Growing LVM physical volume $PV_DEV"
run pvresize "$PV_DEV"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] lvextend -r -l +100%FREE $LV_PATH"
else
  VG_FREE_EXTENTS="$(vgs --noheadings -o vg_free_count "$VG_NAME" | trim)"

  if [[ "$VG_FREE_EXTENTS" == "0" ]]; then
    warn "No free space found in VG $VG_NAME after pvresize."
    exit 0
  fi

  log "Extending logical volume and filesystem"
  lvextend -r -l +100%FREE "$LV_PATH"
fi

cat <<EOF

Done.

Updated disk layout:

EOF

lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS "$DISK"

echo
log "LVM summary:"
vgs "$VG_NAME"
lvs "$VG_NAME"
