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

STATE="$TMP/.state"
mkdir -p "$STATE"
detect_disks() {
  # log "Detecting disks..."

  DEVS_J=$(lsblk -Jo name,rm,size,ro,type,mountpoint,hotplug,label,uuid,model,serial,rev,vendor,hctl | jq '.blockdevices[] | select(.type == "disk" and .name != "'"$ROOT_DEV_NAME"'")')
  DEVS=$(echo "$DEVS_J" | jq -r ".name")
  # log "Found disk(s): $(echo $DEVS)"
  DEVS_ARRAY=($DEVS)

  for dev in $DEVS; do
    DEV_STATE="$STATE/$dev"
    DEV_J=$(echo "$DEVS_J" | jq -sr '.[] | select(.name == "'"$dev"'")')
    if [ -e "$DEV_STATE" ] && [ "$(gen_dev_uuid)" != "$(cat $DEV_STATE/uuid)" ]; then
      rm_routine
    fi
    if [ ! -e "$DEV_STATE" ]; then
      add_routine
    fi
  done

  for DEV_STATE in "$STATE"/*; do
    dev=$(basename "$DEV_STATE")
    if ! contains "$dev" "${DEVS_ARRAY[@]}"; then
      rm_routine
    fi
  done
  # DEV_NAME_LIST=$(echo "$DEVS_J" | jq -sr '.[] | .vendor + " " + .model + " " + .serial + " (" + .size + ")"')
}

gen_dev_uuid() {
  echo "$DEV_J" | jq -c '[.vendor, .model, .serial, .rev, .size, .hctl]' | sha256sum | fold -w 64 | head -n 1
}

add_routine() {
  log "Generating metadata for new device $dev..."

  mkdir -p "$DEV_STATE"
  echo "$DEV_J" | jq -r '.vendor + " " + .model + " " + .serial + " rev " + .rev + " (" + .size + ")"' | sed -r "s|  +| |g" | sed -r "s|^ *||g" > "$DEV_STATE/display"
  gen_dev_uuid > "$DEV_STATE/uuid"
  get_free_id > "$DEV_STATE/id"

  log "Added as $(cat $DEV_STATE/id)!"
}

rm_routine() {
  log "Removing metadata for obsolete device $dev..."
  kill -s SIGKILL "$(cat $DEV_STATE/task 2> /dev/null || /bin/true)" 2> /dev/null || /bin/true # kill obsolete task
  rm -rf "$DEV_STATE"
  log "Removed"
}

get_free_id() {
  ids=$(cat "$STATE"/*/id)
  for freeid in "${ID_ARRAY[@]}"; do
    if ! contains "$freeid" $ids; then
      echo "$freeid"
      return 0
    fi
  done

  log "ERROR: We're out of ids! You really managed to get ${#ID_LIST} drives plugged into this thing?! Report that as an issue!"
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

render() {
  banner

  MIN=$(tput cols)

  if [ $MIN -gt 50 ]; then
    MIN=$(( $MIN - 4 ))
  fi

  render_diskstates

  tail -n 10 "$LOG" | render_logs

  echo
}

render_logs() {
  while read line; do
    center "$line"
  done
}

render_diskstates() {
  if [ "$(ls -A $STATE)" ]; then
    center "Disks:"
    echo

    MIN=$(( $MIN - 4 ))

    for DEV_STATE in "$STATE"/*; do
      dev=$(basename "$DEV_STATE")
      center "$(cat $DEV_STATE/id): $(cat $DEV_STATE/display)"
      MIN=$(( $MIN - 16 ))
      center "Wiped at -"
      center "Healthy"
      MIN=$(( $MIN + 16 ))
      echo
    done

    MIN=$(( $MIN + 4 ))
  else
    _MIN="$MIN"
    MIN=
    center "<No disks detected. Please attach some>"
    MIN="$_MIN"
  fi
}

render_loop() {
  while true; do
    RENDERED=$(render)
    clear
    echo "$RENDERED"

    sleep .1s
  done
}

bg_loop() {
  while true; do
    detect_disks
    sleep 10s
  done
}

control_loop() {
  while read -sn1 char; do
    log "Char $char"
  done
}

echo > "$LOG"

log "Launching..."
detect_root_location

control_loop < /dev/stdin | bg_loop >> "$LOG" 2>&1 | render_loop # this gets piped so everything gets killed on Ctrl+C
