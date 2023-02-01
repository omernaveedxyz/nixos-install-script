#!/bin/bash
set -euo pipefail

usage() {
    echo $(basename "$0"): ERROR: "$@"
    echo -e "\nUsage: $(basename "$0") [OPTIONS] <drive>
    \nOptions:
    \r  --enable-luks                 Enable drive encryption using LUKS
    \r  --fido2-device <path>         Path to FIDO2 device for encryption (e.g. /dev/hidraw0)
    \r  --hostname <label>            Set drive label (for both luks and decrypted) (e.g. omer-desktop)
    \r  --enable-hibernation          Assign additional swap space & enable hibernation
    \r  --help                        Display this help message
    "
    exit 1
}

# check if specified fido2-device path is recognized by systemd-cryptenroll
# INPUT: $1 -> specified fido2-device path
validateFIDO2Device() {
    [ "$(echo "$1")" = "--" ] && usage "fido2-device path cannot be empty"
    [ ! "$(systemd-cryptenroll --fido2-device=list | awk 'NR>1 {print $1}' | grep -w "$1")" ] && usage "invalid fido2-device path specified"
    [ "${#1}" -lt 1 ] && usage "fido2-device path cannot be empty"
    return 0
}

# check if specified hostname matches all requirements for linux device hostnames
# INPUT: $1 -> specified hostname
validateHostname() {
    [ "$(echo "$1")" = "--" ] && usage "hostname cannot be empty"
    [ "$(echo -n "$1" | tail -c 1)" = "-" ] && usage "hostname cannot end in hyphen"
    [ "$(echo "$1" | sed 's/[^0-9a-zA-Z-]//g')" != "$(echo "$1")" ] && usage "invalid character in hostname. Only alnum+hyphen allowed"
    [ "${#1}" -lt 1 ] || [ "${#1}" -ge 64 ] && usage "length of hostname must be between 1 and 63 characters"
    return 0
}

enableLuks=false fido2Device= hostname= enableHibernation=false
eval set --$(getopt --longoptions "enable-luks,fido2-device:,hostname:,enable-hibernation,help" -- "$@") || usage ""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-luks) enableLuks=true; shift 1;;
        --fido2-device) validateFIDO2Device "$2"; fido2Device="$2"; shift 2;;
        --hostname) validateHostname "$2"; hostname="$2"; shift 2;;
        --enable-hibernation) enableHibernation=true; shift 1;;
        --help) usage "Help flag provided"; shift 1;;
        --) shift; break;;
        *) usage "Invalid argument provided";;
    esac
done

# check if specified drive is recognized by the system
# INPUT: $1 -> specified drive path
validateDrive() {
    [ "$(echo "$1")" = "--" ] && usage "drive path cannot be empty"
    [ ! "$(lsblk -d -p --noheadings --raw | awk '{print $1}' | grep -w "$1")" ] && usage "invalid block device specified for drive path"
    [ "${#1}" -lt 1 ] && usage "drive path cannot be empty"
    return 0
}

drive=
case $# in
    0) usage "must provide drive for installation";;
    1) validateDrive "$1"; drive="$1";;
    *) usage "too many arguments";;
esac

# set default hostname to root if not specified
[ -z "$hostname" ] && hostname="root"

# overwrite drive's previous contents with zeroes. Helps with some issues
wipe() {
    dd if="/dev/zero" of="$1" bs=4096 count="$(($(fdisk -l "$1" | awk 'NR==1 {print $7}')/8))" status=progress
}

formatPrimary() {
    # partition drive based on if UEFI or Legacy boot detected
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "UEFI detected"
        sgdisk -Z "$drive"
        sgdisk -n 0:0:+512M -t 0:ef00 "$drive"
        sgdisk -n 0:0:0 -t 0:8300 "$drive"
    else
        wipe "$drive"
        echo "Legacy detected"
        (
        echo o
        echo n
        echo 
        echo 
        echo 
        echo +512M
        echo n
        echo 
        echo 
        echo 
        echo
        echo t
        echo 1
        echo ef
        echo w
        ) | fdisk "$drive"
    fi

    # encrypt & format drive partitions
    mkfs.fat -F32 -n BOOT "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==2 {print $1}')"
    if [ "$enableLuks" = true ]; then
        echo -n "password" | cryptsetup luksFormat "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')" --label "$hostname-luks" --key-slot 2 --key-file -
        PASSWORD="password" systemd-cryptenroll --recovery-key "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')" > "$hostname-recovery.txt"
        if [ ! -z "$fido2Device" ]; then
            PASSWORD="$(cat $hostname-recovery.txt)" systemd-cryptenroll --fido2-device="$fido2Device" "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')"
        else
            echo -n "Enter a password for root partition encryption: "
            read password
            echo -n "$password" | cryptsetup luksFormat "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')" --label "$hostname-luks" --key-file -
        fi
        PASSWORD="$(cat $hostname-recovery.txt)" systemd-cryptenroll --wipe-slot 2 "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')"
        echo -n "$(cat $hostname-recovery.txt)" | cryptsetup luksOpen "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')" "$hostname" --key-file -
        mkfs.btrfs -f -L "$hostname" /dev/mapper/"$hostname"
    else
        mkfs.btrfs -f -L "$hostname" "$(lsblk -p --noheadings --raw "$drive" | awk 'NR==3 {print $1}')"
    fi
    mount --label "$hostname" /mnt

    # create btrfs subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@nix
    btrfs subvolume create /mnt/@persistent
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume snapshot -r /mnt/@ /mnt/@-blank
    umount /mnt

    # mount subvolumes
    mount -o subvol=@,compress=zstd,noatime --label "$hostname" /mnt
    mkdir -p /mnt/{boot,nix,persistent,swap,snapshots}
    mount -o subvol=@nix,compress=zstd,noatime --label "$hostname" /mnt/nix
    mount -o subvol=@persistent,compress=zstd,noatime --label "$hostname" /mnt/persistent
    mount -o subvol=@swap,compress=zstd,noatime --label "$hostname" /mnt/swap
    mount -o subvol=@snapshots,compress=zstd,noatime --label "$hostname" /mnt/snapshots
    mount --label "BOOT" /mnt/boot

    # create swapfile based on size of system memory
    SIZE="4g"
    if [ "$enableHibernation" = true ]; then
        MEMORY="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
        if [ "$MEMORY" -ge "33554432" ]; then
            SIZE="64g"
        elif [ "$MEMORY" -ge "16777216" ]; then
            SIZE="32g"
        elif [ "$MEMORY" -ge "8388608" ]; then
            SIZE="16g"
        elif [ "$MEMORY" -ge "4194304" ]; then
            SIZE="8g"
        fi
    fi
    btrfs filesystem mkswapfile -s "$SIZE" /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile # TODO: workaround for https://github.com/NixOS/nixpkgs/pull/212692
    swapon /mnt/swap/swapfile
}

createConfig() {
    nixos-generate-config --root /mnt
    if [ ! -z "$fido2Device" ]; then
        sed -i "/boot.initrd.luks.devices.\"$hostname\".device = */a boot.initrd.luks.devices.\"$hostname\".crypttabExtraOpts = \[ \"fido2-device=auto\" \];" /mnt/etc/nixos/hardware-configuration.nix
    fi
    sed -i "s~swapDevices = \[ \];~swapDevices = \[ { device = \"/swap/swapfile\"; } \];~" /mnt/etc/nixos/hardware-configuration.nix
    if [ "$enableHibernation" = true ]; then
        sed -i "/^}/i boot.resumeDevice = \"/dev/disk/by-label/$hostname\";" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i boot.kernelParams = \[ \"mem_sleep_default=deep\" \"resume_offset=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)\" \];" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i services.logind.lidSwitch = \"suspend-then-hibernate\";" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i systemd.sleep.extraConfig = \"HibernateDelaySec=1h\";" /mnt/etc/nixos/hardware-configuration.nix # TODO: currently broken as a result of https://github.com/systemd/systemd/issues/25269
        sed -i "s~options = \[ \"subvol=@\" \];~options = \[ \"subvol=@\" \"x-systemd.after=local-fs-pre.target\" \];~" /mnt/etc/nixos/hardware-configuration.nix # TODO: workaround for https://github.com/NixOS/nixpkgs/issues/213122
    fi
    if [ ! -d /sys/firmware/efi/efivars ]; then
        sed -i "s~# boot.loader.grub.device = \"/dev/sda\";~boot.loader.grub.device = \"$device\";~" /mnt/etc/nixos/configuration.nix
    fi
    sed -i "s~# networking.hostName = \"nixos\";~networking.hostName = \"$hostname\";~" /mnt/etc/nixos/configuration.nix
    sed -i "s~# networking.networkmanager.enable = true;~networking.networkmanager.enable = true;~" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i time.timeZone = \"America/Chicago\";" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i users.users.omer = { isNormalUser = true; initialPassword = \"password\"; extraGroups = \[ \"wheel\" \]; packages = with pkgs; \[ neovim git firefox lf \]; };" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i services.openssh.enable = true;" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i nix.settings.trusted-users = \[ \"@wheel\" \];" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i security.sudo.wheelNeedsPassword = false;" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i boot.initrd.systemd.enable = true;" /mnt/etc/nixos/configuration.nix
}

echo -n "Install? [y/N] "
read confirmation
if [ "$confirmation" = "y" ]; then
    formatPrimary
    createConfig
    nixos-install --no-root-passwd
    echo "Success!!!"
    if [ "$enableLuks" = true ]; then
	    echo "Please backup $hostname-recovery.txt. It is your LUKS recovery key."
    fi
fi
