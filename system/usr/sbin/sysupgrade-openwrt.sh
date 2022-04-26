#!/bin/sh
#
# sysupgrade-openwrt.sh - Upgrade tool for aml OpenWrt
# 
# author: krishna@hottunalabs.net
# 

make_path="${PWD}"
openwrt_path="${make_path}/openwrt"
main_target="armvirt"
sub_target="64"
openwrt_target="${main_target}-${sub_target}"
openwrt_file="${openwrt_target}-default-rootfs-ext4.img.gz"
openwrt_url="https://downloads.openwrt.org/releases"
openwrt_branch="21.02"
current_release=$(awk -F= '/^VERSION=/{print $2}' /etc/os-release | sed 's/\"//g')
major_ver=${current_release%.*}
minor_ver=${current_release##*.}
command="$0"
command_name=$(basename "$command")
tmp_path=$(mktemp -t -d)
OLDIFS=$IFS

error_msg() {
    echo -e " [\033[1;91m ${1} \033[0m]"
    exit 1
}

process_msg() {
    echo -e " [\033[1;92m ${1} \033[0m]"
}

init_var() {
    cd ${make_path}

    # If it is followed by [ : ], it means that the option requires a parameter value
    get_all_ver=$(getopt "fs" "${@}")

    opt=""
    second_stage="false"
    while [ -n "${1}" ]; do
        case "${1}" in
        -f | --force)
            opt="force"
            shift
            ;;
        -s | --specific)
            opt="specific"
            shift
            ;;
        --second_stage)
            second_stage="true"
            ;;
        *)
            echo -n "Invalid option [ ${1} ]!"
            ;;
        esac
        shift
    done
}

require_pkgs() {
    $(opkg list_installed | grep -q ^wget-ssl) || opkg install wget-ssl
    $(opkg list_installed | grep -q ^curl) || opkg install curl
    $(opkg list_installed | grep -q ^getopt) || opkg install getopt
}

availability_check() {
    echo -e "- Searching latest Openwrt... \n"
#   if [ "$opt" = "specific" ]; then
#        release_list=$(curl -s ${openwrt_url}/ | grep "href=\"[0-9][0-9]" | sed 's|^.*<a .*\">\(.*\)</a>.*$|\1|' | sed '1!G;h;$!d')
#    else
        release_list=$(curl -s ${openwrt_url}/ | grep "href=\"${openwrt_branch}" | sed 's|^.*<a .*\">\(.*\)</a>.*$|\1|' | sed '1!G;h;$!d')
#    fi

    release=$(echo $release_list | head -n 1 | cut -f 1 -d ' ')

    if [ "$opt" = "specific" ]; then
        for n in $release_list; do
            echo $n
        done | awk '{print "[" ++i "]\t" $0}'

        echo -n " Select number: "
        read key

        case "$key" in
        [0-9]|[0-9][0-9])
            if [ $key -le $(echo $release_list | wc -w) ]; then
                release=$(echo $release_list | cut -f $key -d ' ')
                upgradable=true
            else
                echo -n " Invalid number " && error_msg "error" && exit 1
            fi
            ;;
         *)
            echo -n " Invalid number " && error_msg "error"
            exit 1 ;;
        esac

    elif [ "$current_release" = "$release" ]; then
        echo -e " OpenWrt is up to date: v${release} \n"
        if [ "$opt" = "force" ]; then
            upgradable=true
        else
            exit 0
        fi
    elif $( echo $release | grep -q '\-rc') && [ $minor_ver = 0 ]; then
        echo -e "\n Upgradable OpenWrt is available: v${release} \n"
        upgradable=true
    elif $( echo $release | grep -q '\-rc') && [ "${minor_ver##*-}" -lt "${release##*-}" ]; then
        echo -e "\n Upgradable OpenWrt is available: v${release} \n"
        upgradable=true
    elif [ ${openwrt_branch%%.*} -lt ${release%%.*} ] && $( echo $release | grep -q '\.[0-9]$'); then
        echo -e "\n Major upgrade is available: v${release} \n\n"
        echo -e " WARNING: There is no guarantee if new configuration format changes. \n\n"  
        upgradable=true
    elif [ $minor_ver -lt ${release##*.} ]; then
        echo -e "\n Upgradable OpenWrt is available: v${release} \n"
        upgradable=true
    else
        error_msg " Unknown error"
        exit 1
    fi

    if [ $upgradable = true ]; then
        echo -n " Proceed?: [y/N] "
        read key
        case "$key" in
        "y" | "Y")
            clear
            ;;
         *)
            exit 0
        esac
    fi
}

download_official_openwrt() {
    echo -n "- Downloading OpenWrt image "
    source /etc/os-release
    /usr/bin/wget --show-progress ${openwrt_url}/${release}/targets/${OPENWRT_BOARD}/sha256sums -O ${tmp_path}/sha256sums
    #/usr/bin/wget --show-progress ${openwrt_url}/${release}/packages/${OPENWRT_ARCH}/base/Packages -O ${tmp_path}/base_packages
    echo -n "- Downloading openwrt-rootfs: "
    openwrt_sha256sum=$(cat ${tmp_path}/sha256sums | awk /rootfs-ext4.img.gz/'{print $0}' | sed 's/ \*/  /')
    openwrt_rootfs=$(cat ${tmp_path}/sha256sums | awk /rootfs-ext4.img.gz/'{print $2}' | sed 's/^\*//')
    [ -f "${tmp_path}/${openwrt_rootfs}" ] || wget --show-progress ${openwrt_url}/${release}/targets/${main_target}/${sub_target}/${openwrt_rootfs} \
                                                            -O ${tmp_path}/${openwrt_rootfs}
    cd $tmp_path
    t=$(echo "$openwrt_sha256sum" | sha256sum -c | awk '{print $2}')
    echo -n "- sha256sum check "
    if [ "$t" = "OK" ]; then
        process_msg "Passed"
    else
        error_msg "Failed"
        exit 1
    fi
}

unmount_ing() {
  umount $tmp_path/rootfs/target
  umount $tmp_path/rootfs/dev/pts
  umount $tmp_path/rootfs/proc
  umount $tmp_path/rootfs/sys
  umount $tmp_path/rootfs/dev
  umount $tmp_path/rootfs
}

mount_img() {
    echo "- Preparing OpenWrt installation "
    cd $tmp_path
    gunzip $openwrt_rootfs &&
    fs_image=${openwrt_rootfs%%.gz} &&
    mkdir -p rootfs &&
    mount -o loop $fs_image rootfs &&
    mkdir -p rootfs/target rootfs/pkgs &&
    mount -o bind /dev rootfs/dev &&
    mount -o bind /sys rootfs/sys &&
    mount -o bind /proc rootfs/proc &&
    mount -o bind /tmp rootfs/tmp &&
    mount -o bind /dev/pts rootfs/dev/pts &&
    cp sha256sums rootfs/ &&
    cp $(which $command_name) rootfs/ &&
    echo -e "libc\nbase-files\nlibgcc1\nlibrt" > rootfs/core_pkglist &&
    echo -e "libpthread\nbusybox\nblockdev\nca-bundle\ngetrandom\nlibblkid1" > rootfs/core_base_pkglist &&
    chroot rootfs opkg list_installed > rootfs/base_pkglist &&
    sed -i '/kernel/d;/^base-files/d;/^libc/d;/^libgcc1/d;/^librt/d;/^kmod-/d' rootfs/base_pkglist &&
    chroot rootfs opkg update &&
    chroot rootfs opkg install getopt curl wget-ssl &&
    root_device=$(mount | grep 'on / type' | cut -d ' ' -f 1) &&
    mount $root_device rootfs/target &&
    mount -o bind /tmp rootfs/target/tmp &&
    echo "dest target /target" >> rootfs/etc/opkg.conf &&
    chroot rootfs opkg list_installed > rootfs/others_pkglist &&
    sed -i '/^luci/d;/^kmod-/d;/^kernel/d;/^base-files/d;/^libc/d;/^libgcc1/d;/^librt/d' rootfs/others_pkglist &&
    gunzip -c /tmp/opkg-lists/openwrt_base > rootfs/uncompressed_list &&
    gunzip -c /tmp/opkg-lists/openwrt_core >> rootfs/uncompressed_list &&
    gunzip -c /tmp/opkg-lists/openwrt_luci >> rootfs/uncompressed_list &&
    gunzip -c /tmp/opkg-lists/openwrt_packages >> rootfs/uncompressed_list &&
    gunzip -c /tmp/opkg-lists/openwrt_routing >> rootfs/uncompressed_list &&
    gunzip -c /tmp/opkg-lists/openwrt_telephony >> rootfs/uncompressed_list

    if [ $? -eq 0 ]; then
        echo -n "- Mounting OpenWrt image "
         process_msg "Passed"
    else
        echo -n "- Mounting OpenWrt image "
        unmount_ing
        error_msg "Failed"
    fi

    if [ ${release%.*} = "21.02" ]; then
        echo -e "uclient-fetch\nlibubox20210516\nlibblobmsg-json20210516\nlibubus20210630\nubusd\nubus\nopkg\nlibjson-c5\njshn\njsonfilter" >> rootfs/core_base_pkglist
    fi
}

input_key() {
    echo -n "  Proceed?: [y/N] "
    read key
    case "$key" in
    "y" | "Y")
        key="y"
        ;;
     *)
        key="n"
    esac
}

get_new_pkg_info() {
    cd $tmp_path
    list="$1"
    IFS=$'\n'
    for n2 in $(awk "/^Package: ${2}$/{x=NR+10}(NR<=x){print}" $list); do
        case "$n2" in
            Package*)
                Package=$(echo $n2 | cut -f2 -d " ")
                ;;
            Version*)
                Version=$(echo $n2 | cut -f2 -d " ")
                ;;
            Depends*)
                Depends=$(echo $n2 | cut -f2- -d " ")
                ;;
            License*)
                License=$(echo $n2 | cut -f2 -d " ")
                ;;
            Section*)
                Section=$(echo $n2 | cut -f2 -d " ")
                ;;
            Architecture*)
                Architecture=$(echo $n2 | cut -f2 -d " ")
                ;;
            Installed-Size*)
                Installed_Size=$(echo $n2 | cut -f2 -d " ")
                ;;
            Filename*)
                Filename=$(echo $n2 | cut -f2 -d " ")
                ;;
            Size*)
                Size=$(echo $n2 | cut -f2 -d " ")
                ;;
            SHA256sum*)
                SHA256sum=$(echo $n2 | cut -f2 -d " ")
                ;;
            Description*)
                Description=$(echo $n2 | cut -f2 -d " ")
                ;;
        esac
    done
}

upgrade_core() {
    # Upgrade core packages
    cd $tmp_path

    input_key
    if [ "$key" = "y" ]; then
        source rootfs/etc/os-release
        for f in $(cat rootfs/core_pkglist); do
            pkg_name=$(cat rootfs/sha256sums | awk "/ \*packages\/$f/{print $2}" | cut -d/ -f2)
            chroot rootfs wget --show-progress ${openwrt_url}/${VERSION}/targets/${OPENWRT_BOARD}/packages/$pkg_name -O /$pkg_name
            chroot rootfs opkg install --force-removal-of-essential-packages --force-reinstall /$pkg_name -o /target
        done
        for f in $(cat rootfs/core_base_pkglist); do
            get_new_pkg_info "rootfs/uncompressed_list" $f
            chroot rootfs wget --show-progress ${openwrt_url}/${VERSION}/packages/${OPENWRT_ARCH}/base/$Filename -O /$Filename
            chroot rootfs opkg install --force-removal-of-essential-packages --force-reinstall /$Filename -o /target
        done
        echo -n "- upgrading core packages "
    fi
}

upgrade_the_rest_of_pkgs() {
#    opkg upgrade $(opkg list-upgradable 2>/dev/null | cut -d' ' -f 1 | tr '\n' ' ')
    opkg upgrade $(opkg list-upgradable 2>/dev/null | cut -d' ' -f 1)
    echo -n "- upgrading all packages "
}


opkg update
require_pkgs
init_var $@
availability_check
download_official_openwrt
mount_img 
echo "- sysupgrade: second stage starts"
upgrade_core && process_msg "Done" || error_msg "Failed"
upgrade_the_rest_of_pkgs && process_msg "Done" || error_msg "Failed"

echo "  Upgrade has been completed successfully."

### End ###

