#!/bin/bash

file=$(basename -- "$1")
tmpdir=$(mktemp -d -p . )
extension="${file##*.}"

case "$extension" in
    "deb")
        kver=$(echo $file | sed 's/^linux-headers-\(.*\)_.*_arm64.deb$/\1/')
        dpkg -x $file $tmpdir
        ;;
    *)
        echo "Unidentified file: $file"
        exit 1
        ;;
esac

cd $tmpdir
cp -a usr/src/linux-headers-*/include .
cp -a usr/src/linux-headers*/arch/arm64/include/asm include/

tar czf ../header-${kver}.tar.gz include

cd ..
rm -rf $tmpdir
## end

