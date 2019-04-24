#!/bin/bash

# from https://willhaley.com/blog/custom-debian-live-environment/
# and https://wiki.debian.org/Debootstrap

SRC=$(dirname $(readlink -f $0))
set -e

log() {
  echo
  echo "*** $*"
  echo
}

log "Installing tools..."

sudo apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    dosfstools

TMP=$(mktemp -d)
log "Creating image in $TMP..."
sudo mount -t tmpfs -o size=4096m /dev/null $TMP
mount | grep "$TMP"
function finish {
  if [ ! -z "$disk" ]; then
    sudo umount "$TMP/mnt/"*
    sudo losetup -d "$disk"
  fi
  sudo umount "$TMP"
  rm -rf "$TMP"
}
trap finish EXIT
trap finish SIGINT
trap finish SIGTERM

log "Bootstraping ubuntu base system..."
sudo debootstrap \
    --arch=amd64 \
    --variant=minbase \
    disco \
    "${TMP}/chroot" \
    http://archive.ubuntu.com/ubuntu/

log "Copying source code..."
sudo mkdir -p "${TMP}/chroot/srv/wyper" "${TMP}/etc/network" "${TMP}/root/etc/network"
sudo cp -r "$SRC/.git" "${TMP}/chroot/srv/wyper/"
sudo git -C "${TMP}/chroot/srv/wyper/" reset --hard HEAD

log "Setting up system..."
sudo chroot "${TMP}/chroot" bash -ex - << EOF
export DEBIAN_FRONTEND=noninteractive
echo "wyper" > /etc/hostname
echo "deb http://archive.ubuntu.com/ubuntu/ DISTRO main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ DISTRO-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ DISTRO-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu DISTRO-security main restricted universe multiverse" | \
  sed "s|DISTRO|\$(cat /etc/lsb-release | grep DISTRIB_CODENAME | sed "s|^DISTRIB_CODENAME=||g")|g" > /etc/apt/sources.list
apt-get update && \
apt-get install -y --no-install-recommends \
    linux-image-generic \
    live-boot \
    systemd-sysv \
    git \
    console-data console-common v86d locales

locale-gen en_US.UTF-8
update-locale en_US.UTF-8

if [ ! -z "$DEBUG" ]; then
  apt-get install -y sudo network-manager net-tools wireless-tools
  yes | adduser user || /bin/true
  echo 'user:somepw' | chpasswd
  addgroup user sudo
fi

apt-get clean
cd /srv/wyper && bash prepare_machine.sh
EOF

log "Packing system..."
mkdir -p ${TMP}/{scratch,image/live}
sudo mksquashfs \
    "${TMP}/chroot" \
    "${TMP}/image/live/filesystem.squashfs" \
    -e boot

log "Preparing image..."
sudo cp ${TMP}/chroot/boot/vmlinuz-* \
    ${TMP}/image/vmlinuz && \
sudo cp ${TMP}/chroot/boot/initrd.img-* \
    ${TMP}/image/initrd.img

cat <<'EOF' >${TMP}/scratch/grub.cfg

search --set=root --file /WYPER

insmod all_video

set default="0"
set timeout=30

menuentry "Wyper" {
    linux /vmlinuz boot=live splash nomodeset
    initrd /initrd.img
}
EOF

touch ${TMP}/image/WYPER

isofile() {
  grub-mkstandalone \
      --format=x86_64-efi \
      --output=${TMP}/scratch/bootx64.efi \
      --locales="" \
      --fonts="" \
      "boot/grub/grub.cfg=${TMP}/scratch/grub.cfg"

  (cd ${TMP}/scratch && \
      dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
      mkfs.vfat efiboot.img && \
      mmd -i efiboot.img efi efi/boot && \
      mcopy -i efiboot.img ./bootx64.efi ::efi/boot/
  )

  grub-mkstandalone \
      --format=i386-pc \
      --output=${TMP}/scratch/core.img \
      --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
      --modules="linux normal iso9660 biosdisk search" \
      --locales="" \
      --fonts="" \
      "boot/grub/grub.cfg=${TMP}/scratch/grub.cfg"

  cat \
      /usr/lib/grub/i386-pc/cdboot.img \
      ${TMP}/scratch/core.img \
  > ${TMP}/scratch/bios.img

  log "Making iso..."
  sudo xorriso \
      -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "WYPER" \
      -eltorito-boot \
          boot/grub/bios.img \
          -no-emul-boot \
          -boot-load-size 4 \
          -boot-info-table \
          --eltorito-catalog boot/grub/boot.cat \
      --grub2-boot-info \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
      -eltorito-alt-boot \
          -e EFI/efiboot.img \
          -no-emul-boot \
      -append_partition 2 0xef ${TMP}/scratch/efiboot.img \
      -output "$SRC/wyper.iso" \
      -graft-points \
          "${TMP}/image" \
          /boot/grub/bios.img=${TMP}/scratch/bios.img \
          /EFI/efiboot.img=${TMP}/scratch/efiboot.img

  log "Successfully created $SRC/wyper.iso!"

  # Test it using qemu-system-x86_64 -m 1024 wyper.iso
}

imgfile() {
  log "Creating imagefile..."
  IMGFILE="$TMP/wyper.img"
  sudo mkdir -p $TMP/mnt/{usb,efi}
  dd if=/dev/zero of="$IMGFILE" bs=1MB count=1024
  sudo losetup -Pf "$IMGFILE"
  disk=$(losetup | grep "$IMGFILE" | awk '{print $1}')

  log "Setting up partitions..."
  sudo parted --script $disk \
    mklabel gpt \
    mkpart primary fat32 2048s 4095s \
        name 1 BIOS \
        set 1 bios_grub on \
    mkpart ESP fat32 4096s 413695s \
        name 2 EFI \
        set 2 esp on \
    mkpart primary fat32 413696s 100% \
        name 3 LINUX \
        set 3 msftdata on
  sudo gdisk $disk << EOF
r     # recovery and transformation options
h     # make hybrid MBR
1 2 3 # partition numbers for hybrid MBR
N     # do not place EFI GPT (0xEE) partition first in MBR
EF    # MBR hex code
N     # do not set bootable flag
EF    # MBR hex code
N     # do not set bootable flag
83    # MBR hex code
Y     # set the bootable flag
x     # extra functionality menu
h     # recompute CHS values in protective/hybrid MBR
w     # write table to disk and exit
Y     # confirm changes
EOF
  sudo mkfs.vfat -F32 ${disk}p2 && \
  sudo mkfs.vfat -F32 ${disk}p3

  log "Setting up boot partitions..."
  sudo mount ${disk}p2 $TMP/mnt/efi && \
  sudo mount ${disk}p3 $TMP/mnt/usb

  sudo grub-install \
    --target=x86_64-efi \
    --efi-directory=$TMP/mnt/efi \
    --boot-directory=$TMP/mnt/usb/boot \
    --removable \
    --recheck

  sudo grub-install \
    --target=i386-pc \
    --boot-directory=$TMP/mnt/usb/boot \
    --recheck \
    $disk

  log "Copying data..."
  sudo mkdir -p $TMP/mnt/usb/{boot/grub,live}
  sudo cp -r $TMP/image/* $TMP/mnt/usb/
  sudo cp \
    $TMP/scratch/grub.cfg \
    $TMP/mnt/usb/boot/grub/grub.cfg

  log "Successfully created $SRC/wyper.img!"
  sudo umount "$TMP/mnt/"*
  sudo losetup -d "$disk"
  cp "$IMGFILE" "$SRC/wyper.img"
  disk=""

  # Test it using qemu-system-x86_64 -m 1024 wyper.img
}

case "$1" in
  iso)
    isofile
    ;;
  img)
    imgfile
    ;;
  "")
    imgfile
    isofile
    ;;
esac
