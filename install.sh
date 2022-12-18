#!/bin/bash
set -euo pipefail

usage() {
    echo $(basename "$0"): ERROR: "$@"
    echo -e "\nUsage: $(basename "$0") [OPTIONS] <device>
    \nOptions:
    \r  -l, --enable-luks                 Enable drive encryption using LUKS
    \r  -f, --fido2-device <path>         Path to FIDO2 device for encryption
    \r  -n, --hostname <label>            Set drive label (both luks and decrypted)
    \r  -h, --help                        Display this help message
    "
    exit 1
}

validateHostname() {
    [ "$(echo "$1")" = "--" ] && usage "hostname cannot be empty"
    [ "$(echo -n "$1" | tail -c 1)" = "-" ] && usage "hostname cannot end in hyphen"
    [ "$(echo "$1" | sed 's/[^0-9a-zA-Z-]//g')" != "$(echo "$1")" ] && usage "invalid character in hostname. Only alnum+hyphen allowed"
    [ "${#1}" -lt 1 ] || [ "${#1}" -ge 64 ] && usage "length of hostname must be between 1 and 63 characters"
    return 0
}

enableLuks=false fido2Device= hostname=
eval set --$(getopt --options "l,f:,n:,h" --longoptions "enable-luks,fido2-device:,hostname:,help" -- "$@") || usage ""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l | --enable-luks) enableLuks=true; shift 1;;
        -f | --fido2-device) fido2Device="$2"; shift 2;;
        -n | --hostname) validateHostname "$2"; hostname="$2"; shift 2;;
        -h | --help) usage "Help flag provided"; shift 1;;
        --) shift; break;;
        *) usage "Invalid argument provided";;
    esac
done

device=
case $# in
    0) usage "must provide device";;
    1) device="$1";;
    *) usage "too many arguments";;
esac

if [ "$enableLuks" = true ]; then
    if [ -z "$fido2Device" ] || [ -z "$hostname" ]; then
        usage "Invalid flags. If --enableLuks, --fido2-device and --hostname must also be provided."
    fi
elif [ -z "$hostname" ]; then
    usage "--hostname must be specified."
fi

wipe() {
    dd if="/dev/zero" of="$1" bs=4096 count="$(($(fdisk -l "$1" | awk 'NR==1 {print $7}')/8))" status=progress
}

formatPrimary() {
    # Partition
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "UEFI detected"
        sgdisk -Z "$device"
        sgdisk -n 0:0:+512M -t 0:ef00 "$device"
        sgdisk -n 0:0:0 -t 0:8300 "$device"
    else
	wipe "$device"
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
        ) | fdisk "$device"
    fi
    mkfs.fat -F32 -n BOOT "$(lsblk -p --noheadings --raw "$device" | awk 'NR==2 {print $1}')"

    # Encrypt & Format
    if [ "$enableLuks" = true ]; then
        echo -n "password" | cryptsetup luksFormat "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')" --label "$hostname-luks" --key-slot 2 --key-file -
        PASSWORD="password" systemd-cryptenroll --recovery-key "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')" > "$hostname-recovery.txt"
        PASSWORD="$(cat $hostname-recovery.txt)" systemd-cryptenroll --fido2-device="$fido2Device" "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')"
        PASSWORD="$(cat $hostname-recovery.txt)" systemd-cryptenroll --wipe-slot 2 "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')"
        echo -n "$(cat $hostname-recovery.txt)" | cryptsetup luksOpen "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')" "$hostname" --key-file -
        mkfs.btrfs -f -L "$hostname" /dev/mapper/"$hostname"
        mount /dev/mapper/"$hostname" /mnt
    else
        mkfs.btrfs -f -L "$hostname" "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')"
        mount "$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')" /mnt
    fi

    # Create Btrfs subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@nix
    btrfs subvolume create /mnt/@persistent
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume snapshot -r /mnt/@ /mnt/@-blank
    umount /mnt

    # Mount subvolumes
    if [ "$enableLuks" = true ]; then
        partition=/dev/mapper/"$hostname"
    else
        partition="$(lsblk -p --noheadings --raw "$device" | awk 'NR==3 {print $1}')"
    fi
    mount -o subvol=@,compress=zstd,noatime "$partition" /mnt
    mkdir -p /mnt/{boot,nix,persistent,swap,snapshots}
    mount -o subvol=@nix,compress=zstd,noatime "$partition" /mnt/nix
    mount -o subvol=@persistent,compress=zstd,noatime "$partition" /mnt/persistent
    mount -o subvol=@swap,compress=zstd,noatime "$partition" /mnt/swap
    mount -o subvol=@snapshots,compress=zstd,noatime "$partition" /mnt/snapshots
    mount "$(lsblk -p --noheadings --raw "$device" | awk 'NR==2 {print $1}')" /mnt/boot

    # Create swapfile
    truncate -s 0 /mnt/swap/swapfile
    chattr +C /mnt/swap/swapfile
    dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count=4096
    chmod 0600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
}

createConfig() {
    nixos-generate-config --root /mnt
    sed -i "/boot.initrd.luks.devices.\"$hostname\".device = */a boot.initrd.luks.devices.\"$hostname\".crypttabExtraOpts = \[ \"fido2-device=auto\" \];" /mnt/etc/nixos/hardware-configuration.nix
    sed -i "s~swapDevices = \[ \];~swapDevices = \[ { device = \"/swap/swapfile\"; } \];~" /mnt/etc/nixos/hardware-configuration.nix
    sed -i "s~# boot.loader.grub.device = \"/dev/sda\";~boot.loader.grub.device = \"$device\";~" /mnt/etc/nixos/configuration.nix
    sed -i "s~# networking.hostName = \"nixos\";~networking.hostName = \"$hostname\";~" /mnt/etc/nixos/configuration.nix
    sed -i "s~# networking.networkmanager.enable = true;~networking.networkmanager.enable = true;~" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i time.timeZone = \"America/Chicago\";" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i users.users.omer = { isNormalUser = true; initialPassword = \"password\"; extraGroups = \[ \"wheel\" \]; packages = with pkgs; \[ neovim git firefox lf \]; };" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i services.openssh.enable = true;" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i nix.settings.trusted-users = \[ \"@wheel\" \];" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i security.sudo.wheelNeedsPassword = false;" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i programs.gnupg.agent = { enable = true; enableSSHSupport = true; }; services.pcscd.enable = true;" /mnt/etc/nixos/configuration.nix
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
    echo -e "\nForeward Instructions:
    \r  $ reboot
    \r  $ gpg --import public.key
    \r  $ git clone git@git.omernaveed.dev:/srv/git/nixos-config
    \r  $ colmena apply-local --sudo
    "
fi
