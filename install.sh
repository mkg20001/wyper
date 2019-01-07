#!/bin/bash

MAIN=$(dirname $(readlink -f $0))
STORAGE="$MAIN/.tmp"
DB="$STORAGE/.db"
IMGSTORED="$STORAGE/current.img"

mkdir -p "$STORAGE"

_db() { # GET via <key> SET via <key> <value>
  if [ ! -e "$DB" ]; then
    echo > "$DB"
  fi
  if [ -z "$2" ]; then
    cat "$DB" | grep "^$1=" | sed "s|^$1=||g"
  else
    NEWDB=$(cat "$DB" | grep -v "^$1=")
    echo "$NEWDB
$1=$2" > "$DB"
  fi
}

log() {
  echo "$(date +%s): $*"
}

fetch_meta() {
  DISTRO="bionic"
  BASEURL="https://cloud-images.ubuntu.com/$DISTRO/current"
  IMGFILE=$(curl -s "$BASEURL/" | grep "cloudimg-amd64.img" | sed -r "s|.+href=\"([a-z0-9.-]+)\".+|\1|g")
  IMGURL="$BASEURL/$IMGFILE"
  IMGHASH=$(curl -s "$BASEURL/SHA256SUMS" | grep "$IMGFILE\$")
}

fetch_image() {
  log "Fetching cloud-image metadata..."

  fetch_meta

  if [ "$(_db current)" != "$IMGHASH" ]; then
    log "Fetching latest image..."
    wget -O "$IMGSTORED" "$IMGURL"
  fi

  _db current "$IMGHASH"
}

dev_arg_check() {
  if [ $(id -u) -gt 0 ]; then
    echo "ERROR: Must be root"
    exit 2
  fi

  if [ -z "$DEV" ]; then
    echo "Device not specified"
  fi

  if ! echo "$DEV" | grep "^/dev" > /dev/null; then
    echo "ERROR: Not a device"
    exit 2
  fi
}

flash_image() {
  log "Flashing $DISTRO cloud-image on $DEV..."

  #dd "if=$IMGSTORED" "of=$DEV" &
  #progress -mp "$!"
  #pv -n "$IMGSTORED" | dd if=/dev/stdin "of=$DEV" bs=128M conv=notrunc,noerror
  # bs=128M conv=notrunc,noerror
  (pv -n "$IMGSTORED" | dd if=/dev/stdin "of=$DEV") 2>&1 | dialog --gauge "Flashing $DISTRO cloud-image on $DEV..." 10 70 0
}

main() {
#  check_pkg coreutils pv

  DEV="$2"
  case "$1" in
    install)
      dev_arg_check

      echo "This will wipe $DEV and install the latest version of wyper."
      read -p "Contrinue [y/N]: " prompt

      if [[ "$prompt" == "y"* ]]; then
        fetch_image
        flash_image
      fi
      ;;
    update)
      dev_arg_check
      ;;
    *)
      echo "Wyper - Drive wiping tool"
      echo
      echo "Commands:"
      echo " - install <device>: Install the software on the specified device. Will clone the current repo as-is and copy remote settings."
      echo " WARNING: ALL DATA ON THE SPECIFIED DEVICE WILL BE LOST!"
      echo " - update <device>: Update the software on the device with the current version."
      echo " NOTE: To upgrade between distributions or to fix other errors it's recommended to simply re-flash using the install command"
      exit 2
  esac
}

main "$@"
