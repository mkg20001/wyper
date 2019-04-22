#!/bin/bash

# from https://willhaley.com/blog/custom-debian-live-environment/
# and https://wiki.debian.org/Debootstrap

SRC=$(dirname $(readlink -f $0))
set -ex

sudo apt-get install \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools

TMP=$(mktemp -d)
echo "$TMP"

sudo debootstrap \
    --arch=amd64 \
    --variant=minbase \
    bionic \
    "${TMP}/chroot" \
    http://archive.ubuntu.com/ubuntu/

sudo mkdir -p "${TMP}/chroot/srv/wyper"
sudo cp -r "$SRC/.git" "${TMP}/chroot/srv/wyper/"
sudo git -C "${TMP}/chroot/srv/wyper/" reset --hard HEAD

sudo chroot "${TMP}/chroot" bash -ex - << EOF
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
    git
apt-get clean
cd /srv/wyper && bash prepare_machine.sh
EOF
mkdir -p ${TMP}/{scratch,image/live}

sudo mksquashfs \
    "${TMP}/chroot" \
    "${TMP}/image/live/filesystem.squashfs" \
    -e boot

sudo cp ${TMP}/chroot/boot/vmlinuz-* \
    ${TMP}/image/vmlinuz && \
sudo cp ${TMP}/chroot/boot/initrd.img-* \
    ${TMP}/image/initrd

cat <<'EOF' >${TMP}/scratch/grub.cfg

search --set=root --file /WYPER

insmod all_video

set default="0"
set timeout=30

menuentry "Wyper" {
    linux /vmlinuz boot=live quiet nomodeset
    initrd /initrd
}
EOF

touch ${TMP}/image/WYPER

## MAKE BOOT

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
