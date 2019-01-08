#!/bin/bash

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
  ROOT_DEV=$(lsblk -no pkname "$ROOT_MNT")
  ROOT_DEV="/dev/$ROOT_DEV"

  log "System is mounted at $ROOT_MNT which is part of $ROOT_DEV"
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
