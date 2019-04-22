#!/bin/bash

# from https://willhaley.com/blog/custom-debian-live-environment/

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
    --arch=i386 \
    --variant=minbase \
    stretch \
    ${TMP}/chroot \
    http://ftp.us.debian.org/debian/


sudo chroot ${TMP}/chroot

## CHROOT

echo "debian-live" > /etc/hostname
apt-cache search linux-image

apt-get update && \
apt-get install --no-install-recommends \
    linux-image-686 \
    live-boot \
    systemd-sysv

apt-get install --no-install-recommends \
    network-manager net-tools wireless-tools wpagui \
    curl openssh-client \
    blackbox xserver-xorg-core xserver-xorg xinit xterm \
    nano && \
apt-get clean
passwd root

## EXCHROOT

mkdir -p ${TMP}/{scratch,image/live}

sudo mksquashfs \
    ${TMP}/chroot \
    ${TMP}/image/live/filesystem.squashfs \
    -e boot

cp ${TMP}/chroot/boot/vmlinuz-* \
    ${TMP}/image/vmlinuz && \
cp ${TMP}/chroot/boot/initrd.img-* \
    ${TMP}/image/initrd

cat <<'EOF' >${TMP}/scratch/grub.cfg

search --set=root --file /WYPER

insmod all_video

set default="0"
set timeout=30

menuentry "Debian Live" {
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

xorriso \
    -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
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
    -output "${TMP}/debian-custom.iso" \
    -graft-points \
        "${TMP}/image" \
        /boot/grub/bios.img=${TMP}/scratch/bios.img \
        /EFI/efiboot.img=${TMP}/scratch/efiboot.img
