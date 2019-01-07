#!/bin/bash

set -e

MAIN=$(dirname $(readlink -f $0))
STORAGE="$MAIN/.tmp"
DB="$STORAGE/.db"
IMGSTORED="$STORAGE/current.img"

mkdir -p "$STORAGE"

CACHE="$STORAGE/cache"
TMP="$STORAGE/tmp"
rm -rf "$TMP"
mkdir -p "$TMP"
mkdir -p "$CACHE"

OUT="$STORAGE"

seed=$(cat "$MAIN/cloud-config.yaml")

# what it does:
# 1. dl img for dist
# 2. convert to raw
# 3. losetup, mount, chroot
# 4. enable ssh with pw and root login, remove UEFI from fstab
# 5. create cloud-localds and overwrite UEFI with it
# 6. umount, cleanup, rename

clear_dev() {
  for d in $(get_dev_all "$1"); do
    for str in $(mount | grep "^$d"); do
      if [ -d "$str" ]; then
        umount -f "$str"
      fi
    done

    losetup -d "$d"
  done
}

setup_dev() {
  clear_dev "$1"

  losetup -Pf "$1"
}

get_dev() {
  losetup -j "$1" -O name -J | jq ".loopdevices[0].name" | sed "s|\"||g"
}

get_dev_all() {
  losetup | grep "$1" | sed "s| .*||g"
}

build_img() {
  dist="bionic"
  tmp_dist="$TMP/dist.qcow2"
  tmp_raw="$TMP/dist.raw"
  tmp_root="$TMP/dist.root"
  if [ "$dist" == "xenial" ]; then
    FNAME="$dist-server-cloudimg-amd64-disk1.img"
  else
    FNAME="$dist-server-cloudimg-amd64.img"
  fi
  URL="https://cloud-images.ubuntu.com/$dist/current/$FNAME"
  SHA=$(dirname "$URL")
  SHA="$SHA/SHA256SUMS"
  FILE=$(basename "$URL")
  SHAC="$CACHE/$FILE.SHA"

  if [ -e "$SHAC" ]; then
    CURSHA=$(cat "$SHAC")
  fi

  NEWSHA=$(curl --silent "$SHA" | grep "$FILE")

  if [ "$CURSHA" != "$NEWSHA" ]; then
    log "Update $FILE..."
    wget "$URL" -O "$CACHE/$FILE"
    echo "$NEWSHA" > "$SHAC"
  fi

  rm -f "$tmp_dist"
  ln "$CACHE/$FILE" "$tmp_dist"

  qemu-img convert -f qcow2 -O raw "$tmp_dist" "$tmp_raw"
  setup_dev "$tmp_raw"
  dist_dev=$(get_dev "$tmp_raw")

  log "Mounted as $dist_dev"
  fs_dev="${dist_dev}p1"
  if [ -e "$tmp_root" ]; then
    rmdir "$tmp_root"
  fi
  mkdir "$tmp_root"
  mount "$fs_dev" "$tmp_root"
  ch=(chroot "$tmp_root")

  log "Chroot $tmp_root"
  # ssh allowpw
  for e in "s|#PermitRootLogin prohibit-password|PermitRootLogin yes|g" "s|#PubkeyAuthentication yes|PubkeyAuthentication yes|g" "s|PasswordAuthentication no|PasswordAuthentication yes|g"; do
    "${ch[@]}" sed "$e" -i /etc/ssh/sshd_config
  done
  # uefi disable
  "${ch[@]}" sed "s|LABEL=UEFI.*||g" -i /etc/fstab
  # grub fix for 18+
  [ -e "$tmp_root/boot/grub/grub.cfg" ] && "${ch[@]}" sed "s|search --no-floppy --fs-uuid --set=root|true|g" -i /boot/grub/grub.cfg
  # debug-door
  "${ch[@]}" adduser --quiet --disabled-password --shell /bin/bash --home /home/newuser --gecos "User" newuser
  "${ch[@]}" sh -c 'echo "newuser:newpassword" | chpasswd'
  "${ch[@]}" addgroup newuser sudo
  "${ch[@]}" cat /etc/fstab

  log "Localds..."
  ds_dev="${dist_dev}p15"
  echo "$seed" | cloud-localds "$TMP/ds.iso" -
  dd if="$TMP/ds.iso" of="$ds_dev"
  out_name="ubuntu-$(ubuntu-distro-info --series=$dist -r | sed 's| |-|g')-x86_64.img"
  out="$OUT/$out_name"

  log "Umount..."
  clear_dev "$tmp_raw"

  log "Move to $out..."
  mv -v "$tmp_raw" "$out"
  date +%s > "$out.ts"
}

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

  if [[ "$DEV" == "/dev/sda"* ]] && [ -z "$I_DONT_CARE" ]; then
    echo "ERROR: $DEV seems to be part of the system! Set I_DONT_CARE=1 if you still want to continue!"
    exit 2
  fi
}

flash_image() {
  log "Flashing $out cloud-image on $DEV..."

  (pv -n "$out" | dd if=/dev/stdin "of=$DEV") 2>&1 | dialog --gauge "Flashing $DISTRO cloud-image on $DEV..." 10 70 0
  clear
}

main() {
#  check_pkg coreutils pv dialog qemu-kvm cloud-image-utils

  DEV="$2"
  case "$1" in
    install)
      dev_arg_check

      echo "This will wipe $DEV and install the latest version of wyper."
      read -p "Contrinue [y/N]: " prompt

      if [[ "$prompt" == "y"* ]]; then
        build_img
        flash_image
      fi
      ;;
    update)
      dev_arg_check
      ;;
    *)
      echo "Wyper - Drive wiping liveCD"
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
