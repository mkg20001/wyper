#!/bin/bash

# pkgs: jq parted lsblk progress

set -e
shopt -s nullglob

if [ $(id -u) -gt 0 ]; then
  echo "ERROR: Must be run as root" >&2
  exit 2
fi

ROOT_MNT=$(awk -v needle="/" '$2==needle {print $1}' /proc/mounts)
if [ "$ROOT_MNT" == "overlay" ]; then
  ROOT_MNT=$(awk -v needle="/run/live/medium" '$2==needle {print $1}' /proc/mounts)
fi
ROOT_DEV_NAME=$(lsblk -no pkname "$ROOT_MNT")
ROOT_DEV="/dev/$ROOT_DEV_NAME"


ID_LIST="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
ID_SPACE_ARRAY=$(echo "$ID_LIST" | sed -r "s|(.)|\1 |g")
ID_ARRAY=($ID_SPACE_ARRAY)


if [ -e /run/live/medium/wyper_storage ]; then
  mount "$ROOT_MNT" /run/live/medium -o remount,rw
  STORAGE="/run/live/medium/wyper_storage"
  LOG="/run/live/medium/wyper_storage/wyper.log"
  ALOG="/run/live/medium/wyper_storage/wyper_audit.log"
else
  STORAGE="/var/lib/wyper"
  LOG="/var/log/wyper"
  ALOG="/var/log/wyper_audit"
fi

PSTATE="$STORAGE/state"
TMP="/tmp/wyper"
touch "$ALOG"
ln -s "$ALOG" "$TMP/alog" # so tty can access it

mkdir -p "$PSTATE"

STATE="$TMP/.state"

DB="$STORAGE/.db"
if [ ! -e "$DB" ]; then
  touch "$DB"
fi

_db() { # GET <key> SET <key> <value>
  if [ -z "$2" ]; then
    cat "$DB" | grep "^$1=" | sed "s|$1=||g" || /bin/true
  else
    newdb=$(cat "$DB" | grep -v "^$1=" || /bin/true)
    newdb="$newdb
$1=$2"
    echo "$newdb" > "$DB"
  fi
}

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

if [ ! -e "$TMP" ]; then
  mkdir "$TMP"
  mount /dev/null -t tmpfs -o defaults,noatime,nosuid,nodev,noexec,mode=1777,size=16M "$TMP"
fi

mkdir -p "$STATE"
echo "Loading..." > "$TMP/menu"

log() {
  echo "[$(date +%H:%M:%S)]: $*" >> "$LOG"
}

slog() {
  CUR_LOG="$*"
  log "$@"
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

. state.sh
. render.sh
. bg.sh
. control.sh
. do.sh

echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"
echo >> "$LOG"

log "Launching..."
detect_root_location
_db auto_wipe F

control_loop < /dev/stdin >> "$LOG" 2>&1 | bg_loop >> "$LOG" 2>&1 | render_loop # this gets piped so everything gets killed on Ctrl+C
