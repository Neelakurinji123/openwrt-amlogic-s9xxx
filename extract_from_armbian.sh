#!/bin/bash

file=$(basename -- "$1")
extension="${file##*.}"
tmpdir=$(mktemp -d -p .)

case "$extension" in
    "xz")
        xz -d -c "$file" > $tmpdir/armbian.img
        ;;
    "gz")
        gunzip -c "$file" > $tmpdir/armbian.img
        ;;
    "bz2")
        bzip2 -d -c "$file" > $tmpdir/armbian.img
        ;;
    "img")
        cp "$file" > $tmpdir/armbian.img
        ;;
    *)
        echo "Unidentified file: $file"
        exit 1
        ;;
esac

cd $tmpdir

efi_start=$(fdisk -l armbian.img | awk '/armbian.img1/{print $2}')
efi_end=$(fdisk -l armbian.img | awk '/armbian.img1/{print $3}')
efi_sector=$(fdisk -l armbian.img | awk '/armbian.img1/{print $4}')
rootfs_start=$(fdisk -l armbian.img | awk '/armbian.img2/{print $2}')
rootfs_end=$(fdisk -l armbian.img | awk '/armbian.img2/{print $3}')
rootfs_sector=$(fdisk -l armbian.img | awk '/armbian.img2/{print $4}')

mkdir -p mnt_efi
mkdir -p mnt_rootfs

mount -o loop,offset=$(( $efi_start * 512 )),sizelimit=$(( $efi_sector * 512 )) armbian.img mnt_efi
mount -o loop,offset=$(( $rootfs_start * 512 )),sizelimit=$(( $rootfs_sector * 512 ))  armbian.img mnt_rootfs

kver=$(echo mnt_efi/System.map* | sed 's#^.*/System.map-##')

## boot files
mkdir -p boot-$kver
cp mnt_efi/System.map-$kver mnt_efi/config-$kver mnt_efi/initrd.img-$kver mnt_efi/uInitrd-$kver mnt_efi/vmlinuz-$kver boot-$kver
(cd boot-$kver; tar czf ../../boot-${kver}.tar.gz *)

## dtb files
mkdir -p dtb-amlogic-$kver
find mnt_efi/dtb-$kver | grep meson | xargs -i cp -a {} dtb-amlogic-$kver
tar czf ../dtb-amlogic-${kver}.tar.gz dtb-amlogic-$kver
( cd dtb-amlogic-$kver; tar czf ../../dtb-amlogic-${kver}.tar.gz *)

## kernel modules
cp -a mnt_rootfs/lib/modules/$kver .
ln -sf /usr/src/linux-$kver mnt_rootfs/lib/modules/$kver/build
ln -sf /usr/src/linux-$kver mnt_rootfs/lib/modules/$kver/source
tar czf ../modules-${kver}.tar.gz $kver

umount mnt_efi
umount mnt_rootfs
cd ..
rm -rf $tmpfile

## end
