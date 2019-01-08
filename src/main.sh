#!/bin/bash

# pkgs: jq parted lsblk

if [ $(id -u) -gt 0 ]; then
  echo "ERROR: Must be run as root" >&2
  exit 2
fi

STORAGE="/var/lib/wyper"
TMP="/tmp/wiper"

mkdir -p "$STORAGE"
mkdir -p "$TMP"

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

detect_root_location() {
  ROOT_MNT=$(awk -v needle="/" '$2==needle {print $1}' /proc/mounts)
  ROOT_DEV_NAME=$(lsblk -no pkname "$ROOT_MNT")
  ROOT_DEV="/dev/$ROOT_DEV_NAME"

  log "System is mounted at $ROOT_MNT which is part of $ROOT_DEV, ignoring that disk"
}

get_from_list() {
  head -n "$1" | tail -n 1
}

detect_disks() {
  DEVS_J=$(lsblk -Jo name,rm,size,ro,type,mountpoint,hotplug,label,uuid,model,serial,vendor | jq '.blockdevices[] | select(.type == "disk" and .name != "'"$ROOT_DEV_NAME"'")')
  DEVS=$(echo "$DEVS_J" | jq -r ".name")
  DEVS=($DEVS)
  DEV_NAME_LIST=$(echo "$DEVS_J" | jq -sr '.[] | .vendor + " " + .model + " " + .serial + " (" + .size + ")"')
}

contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

MAP="$TMP/.map"
mkdir -p "$MAP"
name_to_index() {
  :
}

name_to_index_sync() {
#  for dev in $DEVS; do
#    for dev_index in $(ls "$MAP"); do
  :
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

render() {
  banner

  MIN=$(tput cols)

  if [ $MIN -gt 50 ]; then
    MIN=$(( $MIN - 4 ))
  fi

  center "Disks:"

  echo

  render_diskstates

  echo

  center ""

  tail -n 10 "$LOG" | render_logs

  echo
}

render_logs() {
  while read line; do
    center "$line"
  done
}

render_diskstates() {
  MIN=$(( $MIN - 4 ))

  center "<index>: <Name> (<Size>)"
  MIN=$(( $MIN - 8 ))
  center "Wiped at -"
  center "Healthy"
  MIN=$(( $MIN + 8 ))
  echo

  MIN=$(( $MIN + 4 ))
}

render_loop() {
  while true; do
    RENDERED=$(render)
    clear
    echo "$RENDERED"

    sleep 1s
  done
}

echo > "$LOG"

log "Launching..."
detect_root_location

render_loop
