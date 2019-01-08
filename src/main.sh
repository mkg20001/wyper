#!/bin/bash

# pkgs: jq parted lsblk

set -e
shopt -s nullglob

if [ $(id -u) -gt 0 ]; then
  echo "ERROR: Must be run as root" >&2
  exit 2
fi

ID_LIST="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
ID_SPACE_ARRAY=$(echo "$ID_LIST" | sed -r "s|(.)|\1 |g")
ID_ARRAY=($ID_SPACE_ARRAY)

STORAGE="/var/lib/wyper"
TMP="/tmp/wyper"

mkdir -p "$STORAGE"
mkdir -p "$TMP"
echo "Loading..." > "$TMP/menu"

STATE="$TMP/.state"
mkdir -p "$STATE"

LOG="$TMP/out.log"

center() { # <string> [<min-size>]
  if [ ! -z "$2" ]; then
    MIN="$2"
  fi

  if [ -z "$MIN" ]; then
    MIN="0"
  fi

  STR="$1"
  SIZE="${#STR}"

  if [ $SIZE -gt $MIN ]; then
    MIN="$SIZE"
  fi

  BORDER=$(( ($(tput cols) - $MIN) / 2 ))

  SPACE=""
  if [ $MIN -gt 0 ]; then
    SPACE=$(printf ' %.0s' $(seq 1 $BORDER))
  fi

  echo "$SPACE$STR$SPACE"
}

banner() {
  MIN=""

  echo
  echo

  center "========================================"
  center "      Wyper - Drive wiping utility      "
  center "========================================"

  echo
  echo
}

banner
echo
echo "Loading..."

log() {
  echo "[$(date +%H:%M:%S)]: $*" >> "$LOG"
}

contains () {
  needle="$1"
  shift
  while [ ! -z "$1" ]; do
    if [ "$1" == "$needle" ]; then
      return 0
    fi
    shift
  done

  return 1
}

do_disk_wipe() {
  DEV="$1"
  DEV_NAME="$2"

  log "Wiping $DEV with 000000 (1/3)..."
  dd if=/dev/null "of=$DEV"
  log "Wiping $DEV with 111111 (2/3)..."
  dd if=/dev/null "of=$DEV" # TODO: use 0xffff
  log "Wiping $DEV with random (3/3)..."
  dd if=/dev/null "of=$DEV" # TODO: use random (but make it fast)

  log "Creating msdos partition table on $DEV..."
  yes | parted "$DEV" mktable msdos

  log "Wiping completed for $DEV!"
}

. render.sh
. bg.sh
. control.sh

echo > "$LOG"

log "Launching..."
detect_root_location

control_loop < /dev/stdin | bg_loop >> "$LOG" 2>&1 | render_loop # this gets piped so everything gets killed on Ctrl+C
