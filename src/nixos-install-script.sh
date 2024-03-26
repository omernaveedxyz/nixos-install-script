#!/bin/bash

######################
# PARSE COMMAND LINE #
######################

# When called, the process ends.
# Args:
# 	$1: The exit message (print to stderr)
# 	$2: The exit code (default is 1)
# if env var _PRINT_HELP is set to 'yes', the usage is print to stderr (prior to $1)
# Example:
# 	test -f "$_arg_infile" || _PRINT_HELP=yes die "Can't continue, have to supply file as an argument, got '$_arg_infile'" 4
die()
{
    local _ret="${2:-1}"
    test "${_PRINT_HELP:-no}" = yes && print_help >&2
    echo "$1" >&2
    exit "${_ret}"
}

# THE DEFAULTS INITIALIZATION - POSITIONALS
# The positional args array has to be reset before the parsing, because it may already be defined
# - for example if this script is sourced by an argbash-powered script.
_positionals=()
# THE DEFAULTS INITIALIZATION - OPTIONALS
_arg_fido="off"
_arg_hibernation="off"
_arg_luks="off"
_arg_hostname="nixos"
_arg_testing="off"

# Function that prints general usage of the script.
# This is useful if users asks for it, or if there is an argument parsing error (unexpected / spurious arguments)
# and it makes sense to remind the user how the script is supposed to be called.
print_help()
{
    printf 'Usage: %s [--fido] [--hibernation] [--luks] [--hostname <arg>] [--help] <disk>\n' "$0"
    printf '\t%s\n' "<disk>: disk to install NixOS to"
    printf '\t%s\n' "--fido: add FIDO2 key to LUKS encryption (off by default)"
    printf '\t%s\n' "--hibernation: assign additional space to swapfile for hibernation (off by default)"
    printf '\t%s\n' "--luks: enable LUKS disk encryption (off by default)"
    printf '\t%s\n' "--hostname: hostname of device (default: 'nixos')"
    printf '\t%s\n' "--help: Prints help"
}

# The parsing of the command-line
parse_commandline()
{
    _positionals_count=0
    while test $# -gt 0
    do
        _key="$1"
        case "$_key" in
            --fido)
                _arg_fido="on"
                ;;
            --hibernation)
                _arg_hibernation="on"
                ;;
            --luks)
                _arg_luks="on"
                ;;
            --testing)
                _arg_testing="on"
                ;;
            --hostname)
                test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
                _arg_hostname="$2"
                shift
                ;;
            --hostname=*)
                _arg_hostname="${_key##--hostname=}"
                ;;
            -*)
                print_help
                exit 0
                ;;
            *)
                _last_positional="$1"
                _positionals+=("$_last_positional")
                _positionals_count=$((_positionals_count + 1))
                ;;
        esac
        shift
    done
}

# Check that we receive expected amount positional arguments.
# Return 0 if everything is OK, 1 if we have too little arguments
# and 2 if we have too much arguments
handle_passed_args_count()
{
    local _required_args_string="'disk'"
    test "${_positionals_count}" -ge 1 || _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 1 (namely: $_required_args_string), but got only ${_positionals_count}." 1
    test "${_positionals_count}" -le 1 || _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 1 (namely: $_required_args_string), but got ${_positionals_count} (the last one was: '${_last_positional}')." 1
}

# Take arguments that we have received, and save them in variables of given names.
# The 'eval' command is needed as the name of target variable is saved into another variable.
assign_positional_args()
{
    local _positional_name _shift_for=$1
    # We have an array of variables to which we want to save positional args values.
    # This array is able to hold array elements as targets.
    # As variables don't contain spaces, they may be held in space-separated string.
    _positional_names="_arg_disk "
    
    shift "$_shift_for"
    for _positional_name in ${_positional_names}
    do
        test $# -gt 0 || break
        eval "$_positional_name=\${1}" || die "Error during argument parsing, possibly an Argbash bug." 1
        shift
    done
}

# Now call all the functions defined above that are needed to get the job done
parse_commandline "$@"
handle_passed_args_count
assign_positional_args 1 "${_positionals[@]}"

##############
# VALIDATION #
##############

validate_disk()
{
    if ! grep --word-regexp --quiet "^$_arg_disk" <<< "$(lsblk --paths --noheadings --nodeps --output=NAME)"; then
        die "FATAL ERROR: disk specified is not valid (specified: '$_arg_disk')." 1
    fi
}

validate_hostname()
{
    if (( ${#_arg_hostname} >= 64 )); then
        die "FATAL ERROR: hostname must be less than 64 characters (specified: '$_arg_hostname')." 1
    elif (( ${#_arg_hostname} < 1 )); then
        die "FATAL ERROR: hostname must be at least 1 character in length." 1
    elif [[ $_arg_hostname == *- ]]; then
        die "FATAL ERROR: hostname cannot end in hypen (specified: '$_arg_hostname')." 1
    elif [[ $_arg_hostname =~ [^a-zA-Z0-9-] ]]; then
        die "FATAL ERROR: hostname can only contain alphanumeric characters and/or hyphens (specified '$_arg_hostname')." 1
    fi
}

validate_fido()
{
    if test "${_arg_fido:-off}" = on; then
        if grep --word-regexp --quiet "No FIDO2 devices found." <<< "$(systemd-cryptenroll --fido2-device=list 2>&1)"; then
            die "FATAL ERROR: unable to find FIDO2 device to enroll." 1
        elif test "${_arg_luks:-off}" = off; then
            die "FATAL ERROR: LUKS flag must be enabled in order to enroll FIDO2 device." 1
        fi
    fi
}

validate_root()
{
    if [ "$EUID" -ne 0 ]; then
        die "FATAL ERROR: please run this script as root user." 1
    fi
}

ask_confirmation()
{
    read -r -p "Perform installation (yes/no): " confirmation
    case $confirmation in
        [yY]|[yY][eE][sS]) :;;
        *) exit 0;;
    esac
}

validate_disk
validate_hostname
validate_fido
validate_root
ask_confirmation

################
# INSTALLATION #
################

format_disk()
{
    dd if=/dev/zero of="$_arg_disk" bs=4096 count=$(($(fdisk --list "$_arg_disk" | awk 'NR==1 {print $7}')/8)) status=progress
    if test -d /sys/firmware/efi; then
        sgdisk -Z "$_arg_disk"
        sgdisk -n 0:0:+512M -t 0:ef00 "$_arg_disk"
        sgdisk -n 0:0:0 -t 0:8300 "$_arg_disk"
    else
        echo -e "o\nn\n\n\n\n+512M\nn\n\n\n\n\nt\n1\nef\nw\n" | fdisk "$_arg_disk"
    fi
}

format_partitions()
{
    mkfs.fat -F32 -n BOOT "$(lsblk --paths --noheadings --raw --output=NAME "$_arg_disk" | awk 'NR==2')"
    if test "${_arg_luks:-off}" = on; then
        echo -n password | cryptsetup luksFormat "$(lsblk --paths --noheadings --raw --output=NAME "$_arg_disk" | awk 'NR==3')" --label "$_arg_hostname-luks" --key-slot 2 --key-file -
        PASSWORD=password systemd-cryptenroll --recovery-key "$(lsblk --paths --noheadings --raw --output=NAME "$_arg_disk" | awk 'NR==3')" > luks-recovery.txt
        if test "${_arg_fido:-off}" = on; then
            PASSWORD=$(cat luks-recovery.txt) systemd-cryptenroll --fido2-device=auto "/dev/disk/by-label/$_arg_hostname-luks"
        else
            unset -v password
            set +o allexport
            IFS= read -rsp 'Please enter a password for LUKS encryption: ' password
            echo -en "$(cat luks-recovery.txt)\n$password\n$password" | cryptsetup luksAddKey "/dev/disk/by-label/$_arg_hostname-luks"
        fi
        PASSWORD=$(cat luks-recovery.txt) systemd-cryptenroll --wipe-slot 2 "/dev/disk/by-label/$_arg_hostname-luks"
        echo -n "$(cat luks-recovery.txt)" | cryptsetup luksOpen "/dev/disk/by-label/$_arg_hostname-luks" "$_arg_hostname" --key-file -
        mkfs.btrfs --force --label "$_arg_hostname" "/dev/mapper/$_arg_hostname"
    else
        mkfs.btrfs --force --label "$_arg_hostname" "$(lsblk --paths --noheadings --raw --output=NAME "$_arg_disk" | awk 'NR==3')"
    fi
}

create_btrfs_subvolumes()
{
    mount --label "$_arg_hostname" /mnt
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/nix
    btrfs subvolume create /mnt/persistent
    test "${_arg_hibernation:-off}" = on && btrfs subvolume create /mnt/swap
    btrfs subvolume create /mnt/snapshots
    btrfs subvolume create /mnt/log
    umount /mnt

    mount --options subvol=root,compress=zstd,noatime -t btrfs --label "$_arg_hostname" /mnt
    mount --options X-mount.mkdir,subvol=nix,compress=zstd,noatime -t btrfs  --label "$_arg_hostname" /mnt/nix
    mount --options X-mount.mkdir,subvol=persistent,compress=zstd,noatime -t btrfs  --label "$_arg_hostname" /mnt/persistent
    test "${_arg_hibernation:-off}" = on && mount --options X-mount.mkdir,subvol=swap,compress=zstd,noatime -t btrfs  --label "$_arg_hostname" /mnt/swap
    mount --options X-mount.mkdir,subvol=snapshots,compress=zstd,noatime -t btrfs  --label "$_arg_hostname" /mnt/snapshots
    mount --options X-mount.mkdir,subvol=log,compress=zstd,noatime -t btrfs  --label "$_arg_hostname" /mnt/var/log
    mount --options X-mount.mkdir -t vfat  --label BOOT /mnt/boot
}

create_swapfile()
{
    if test "${_arg_hibernation:-off}" = on; then
        _swap_size="4g"
        _swap_memory="$(grep MemTotal /proc/meminfo | awk '{print $2}')"

        if (( _swap_memory >= 33554432 )); then
            _swap_size="64g"
        elif (( _swap_memory >= 16777216 )); then
            _swap_size="32g"
        elif (( _swap_memory >= 8388608 )); then
            _swap_size="16g"
        elif (( _swap_memory >= 4194304 )); then
            _swap_size="8g"
        fi

        btrfs filesystem mkswapfile -s $_swap_size /mnt/swap/swapfile
        swapon /mnt/swap/swapfile
    fi
}

generate_config_file()
{
    nixos-generate-config --root /mnt

    if test "${_arg_fido:-off}" = on; then
        sed -i "/boot.initrd.luks.devices.\"$_arg_hostname\".device = */a boot.initrd.luks.devices.\"$_arg_hostname\".crypttabExtraOpts = \[ \"fido2-device=auto\" \];" /mnt/etc/nixos/hardware-configuration.nix
    fi

    if test "${_arg_hibernation:-off}" = on; then
        sed -i "s~swapDevices = \[ \];~swapDevices = \[ { device = \"/swap/swapfile\"; } \];~" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i boot.resumeDevice = \"/dev/disk/by-label/$_arg_hostname\";" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i boot.kernelParams = \[ \"mem_sleep_default=deep\" \"resume_offset=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)\" \];" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i services.logind.lidSwitch = \"suspend-then-hibernate\";" /mnt/etc/nixos/hardware-configuration.nix
        sed -i "/^}/i systemd.sleep.extraConfig = \"HibernateDelaySec=1h\";" /mnt/etc/nixos/hardware-configuration.nix
    fi

    if ! test -d /sys/firmware/efi; then
        sed -i "s~# boot.loader.grub.device = \"/dev/sda\";~boot.loader.grub.device = \"$_arg_disk\";~" /mnt/etc/nixos/configuration.nix
    fi

    sed -i "s~# networking.hostName = \"nixos\";~networking.hostName = \"$_arg_hostname\";~" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i users.users.omer = { isNormalUser = true; initialPassword = \"password\"; extraGroups = [ \"wheel\" ]; };" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i services.openssh.enable = true;" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i nix.settings.trusted-users = [ \"@wheel\" ];" /mnt/etc/nixos/configuration.nix
    sed -i "/^}/i boot.initrd.systemd.enable = true;" /mnt/etc/nixos/configuration.nix

    if test "${_arg_testing:-off}" = on; then
        sed -i "/^}/i documentation.enable = false;" /mnt/etc/nixos/configuration.nix
        sed -i "/.\\/hardware-configuration.nix/a <nixpkgs/nixos/modules/testing/test-instrumentation.nix>" /mnt/etc/nixos/configuration.nix
        if test "${_arg_hibernation:-off}" = on; then
            sed -i "/^}/i systemd.services.backdoor.conflicts = [\"sleep.target\"];" /mnt/etc/nixos/configuration.nix
            sed -i "/^}/i powerManagement.resumeCommands = \"systemctl --no-block restart backdoor.service\";" /mnt/etc/nixos/configuration.nix
        fi
    else
        sed -i "s~# networking.networkmanager.enable = true;~networking.networkmanager.enable = true;~" /mnt/etc/nixos/configuration.nix
    fi
}

perform_installation()
{
    nixos-install --no-root-passwd --root /mnt
}

main()
{
    format_disk
    format_partitions
    create_btrfs_subvolumes
    create_swapfile
    generate_config_file
    perform_installation
}

main
