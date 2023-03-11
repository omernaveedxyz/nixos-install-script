{ pkgs }:

rec {
  # print out script usage information to STDOUT
  # INPUT: $1 -> error description
  usage = pkgs.writeShellScriptBin "usage" ''
    printf "%s\n" \
        "installationScript: ERROR: $@" \
        "" \
        "Usage: installationScript [OPTIONS] <drive>" \
        "" \
        "Options:" \
        "  --fido2=<device>              Enable FIDO2 device for encryption. Optionally specify a FIDO2 device (will be auto-detected otherwise)" \
        "  --hibernation                 Enable hibernation and assign additional swap space" \
        "  --luks=<passphrase>           Enable drive encryption using LUKS. Optionally specify luks passphrase (will be prompted otherwise)" \
        "  --hostname=<label>            Set drive label (for both luks and decrypted) (e.g. omer-desktop)" \
        "  --help                        Display this help message"

    exit 0
  '';

  # check if specified fido2-device path is valid
  # INPUT: $1 -> specified fido2-device path
  validateFIDO2Device = pkgs.writeShellScriptBin "validateFIDO2Device" ''
    [ "$(${pkgs.systemd}/bin/systemd-cryptenroll --fido2-device=list | ${pkgs.coreutils}/bin/wc -l)" -lt 2 ] && \
      ${usage}/bin/usage "no FIDO2 devices detected" && \
      exit 1

    # TODO: currently unable to test as QEMU vm is limited to a single CanoKey. reference: https://www.qemu.org/docs/master/system/devices/canokey.html
    [ "$(${pkgs.systemd}/bin/systemd-cryptenroll --fido2-device=list | ${pkgs.coreutils}/bin/wc -l)" -gt 2 ] && \
      [ "$(echo "$1")" = "" ] && ${usage}/bin/usage "Multiple FIDO2 devices detected. Please specify one" && \
      exit 1 

    [ ! "$(${pkgs.systemd}/bin/systemd-cryptenroll --fido2-device=list | ${pkgs.gawk}/bin/awk 'NR>1 {print $1}' | ${pkgs.gnugrep}/bin/grep -w "$1")" ] && \
      ${usage}/bin/usage "invalid FIDO2 device path specified" && \
      exit 1

    exit 0
  '';

  # check if specified hostname matches all requirements for linux device hostnames
  # INPUT: $1 -> specified hostname
  validateHostname = pkgs.writeShellScriptBin "validateHostname" ''
    [ "$(echo "$1")" = "" ] && \
      ${usage}/bin/usage "hostname cannot be empty" && \
      exit 1

    [ "$(echo -n "$1" | ${pkgs.coreutils}/bin/tail -c 1)" = "-" ] && \
      ${usage}/bin/usage "hostname cannot end in hyphen" && \
      exit 1

    [ "$(echo "$1" | ${pkgs.gnused}/bin/sed 's/[^0-9a-zA-Z-]//g')" != "$(echo "$1")" ] && \
      ${usage}/bin/usage "invalid character in hostname. Only alnum+hyphen allowed" && \
      exit 1

    [ "''${#1}" -lt 1 ] || [ "''${#1}" -ge 64 ] && \
      ${usage}/bin/usage "length of hostname must be between 1 and 63 characters" && \
      exit 1

    exit 0
  '';

  # check if specified drive is recognized by the syste
  # INPUT: $1 -> specified drive path
  validateDrive = pkgs.writeShellScriptBin "validateDrive" ''
    [ ! "$(${pkgs.util-linux}/bin/lsblk -d -p --noheadings --raw | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.gnugrep}/bin/grep -w "$1")" ] && \
      ${usage}/bin/usage "invalid block device specified for drive path" && \
      exit 1

    exit 0
  '';

  # overwrite drive's previous contents with zeroes
  # INPUT: $1 -> specified drive path to be wiped
  wipe = pkgs.writeShellScriptBin "wipe" ''
    ${pkgs.coreutils}/bin/dd if="/dev/zero" of="$1" bs=4096 count="$(($(${pkgs.util-linux}/bin/fdisk -l "$1" | ${pkgs.gawk}/bin/awk 'NR==1 {print $7}')/8))" status=progress
    exit 0
  '';

  installationScript = pkgs.writeShellScriptBin "installationScript" ''
    enableFIDO2=false fido2Device=
    enableHibernation=false
    enableLuks=false passphrase=
    hostname=
    eval set --$(${pkgs.util-linux}/bin/getopt --options "" --longoptions "luks::,fido2::,hostname::,hibernation,help" -- "$@") || ${usage}/bin/usage ""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --luks) enableLuks=true && passphrase="$2" && shift 2 || exit 1;;
            --hibernation) enableHibernation=true && shift 1 || exit 1;;
            --fido2) ${validateFIDO2Device}/bin/validateFIDO2Device "$2" && enableFIDO2=true && fido2Device="$2" && shift 2 || exit 1;;
            --hostname) ${validateHostname}/bin/validateHostname "$2" && hostname="$2" && shift 2 || exit 1;;
            --help) ${usage}/bin/usage "Help flag provided" && shift 1 || exit 1;;
            --) shift; break;;
            *) ${usage}/bin/usage "Invalid argument provided" && exit 1;;
        esac
    done

    # make sure only a single drive is specified and that it is a valid drive
    drive=
    case $# in
        0) ${usage}/bin/usage "must provide drive for installation" && exit 1;;
        1) ${validateDrive}/bin/validateDrive "$1" && drive="$1" || exit 1;;
        *) ${usage}/bin/usage "too many arguments" && exit 1;;
    esac
       
    # set default hostname to root if not specified
    [ -z "$hostname" ] && hostname="root" && echo "no hostname specified... using root as default"

    # make sure enable-luks is declared if enable-fido2 is declared
    [ "$enableFIDO2" = true ] && [ "$enableLuks" = false ] && ${usage}/bin/usage "in order to use FIDO2, luks must be enabled." && exit 1

    # format specified drive.
    formatPrimary() {
        # partition drive based on if UEFI or Legacy boot detected
        if [ -d /sys/firmware/efi/efivars ]; then
            echo "UEFI detected"
            ${pkgs.gptfdisk}/bin/sgdisk -Z "$drive"
            ${pkgs.gptfdisk}/bin/sgdisk -n 0:0:+512M -t 0:ef00 "$drive"
            ${pkgs.gptfdisk}/bin/sgdisk -n 0:0:0 -t 0:8300 "$drive"
        else
            ${wipe}/bin/wipe "$drive"
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
            ) | ${pkgs.util-linux}/bin/fdisk "$drive"
        fi

        # encrypt & format drive partitions
        ${pkgs.dosfstools}/bin/mkfs.fat -F32 -n BOOT "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | ${pkgs.gawk}/bin/awk 'NR==2 {print $1}')"
        if [ "$enableLuks" = true ]; then
            echo -n "password" | \
              ${pkgs.cryptsetup}/bin/cryptsetup luksFormat "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
              ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')" --label "$hostname-luks" --key-slot 2 --key-file -
            PASSWORD="password" ${pkgs.systemd}/bin/systemd-cryptenroll --recovery-key "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
              ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')" > "$hostname-recovery.txt"
            if [ "$enableFIDO2" = true ]; then
                if [ ! -z "$fido2Device" ]; then
                    PASSWORD="$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)" ${pkgs.systemd}/bin/systemd-cryptenroll --fido2-device="$fido2Device" "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
                      ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')"
                else
                    PASSWORD="$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)" ${pkgs.systemd}/bin/systemd-cryptenroll --fido2-device=auto "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
                      ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')"
                fi
            elif [ ! -z "$passphrase" ]; then
                echo -en "$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)\n$passphrase\n$passphrase" | \
                  ${pkgs.cryptsetup}/bin/cryptsetup luksAddKey "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
                  ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')"
            else
                echo -n "Enter a password for root partition encryption: "
                read password
                echo -en "$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)\n$password\n$password" | \
                  ${pkgs.cryptsetup}/bin/cryptsetup luksAddKey "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
                  ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')"
            fi
            PASSWORD="$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)" ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot 2 "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
              ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')"
            echo -n "$(${pkgs.coreutils}/bin/cat $hostname-recovery.txt)" | \
              ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$(${pkgs.util-linux}/bin/lsblk -p --noheadings --raw "$drive" | \
              ${pkgs.gawk}/bin/awk 'NR==3 {print $1}')" "$hostname" --key-file -
            ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f -L "$hostname" /dev/mapper/"$hostname"
        else
            ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f -L "$hostname" "$(lsblk -p --noheadings --raw "$drive" | \
              awk 'NR==3 {print $1}')"
        fi
        mount --label "$hostname" /mnt

        # create btrfs subvolumes
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /mnt/@
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /mnt/@nix
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /mnt/@persistent
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /mnt/@swap
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /mnt/@snapshots
        ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /mnt/@ /mnt/@-blank
        umount /mnt

        # mount subvolumes
        mount -o subvol=@,compress=zstd,noatime --label "$hostname" /mnt
        ${pkgs.coreutils}/bin/mkdir -p /mnt/{boot,nix,persistent,swap,snapshots}
        mount -o subvol=@nix,compress=zstd,noatime --label "$hostname" /mnt/nix
        mount -o subvol=@persistent,compress=zstd,noatime --label "$hostname" /mnt/persistent
        mount -o subvol=@swap,compress=zstd,noatime --label "$hostname" /mnt/swap
        mount -o subvol=@snapshots,compress=zstd,noatime --label "$hostname" /mnt/snapshots
        mount --label "BOOT" /mnt/boot

        # create swapfile based on size of system memory
        SIZE="4g"
        if [ "$enableHibernation" = true ]; then
            MEMORY="$(${pkgs.gnugrep}/bin/grep MemTotal /proc/meminfo | awk '{print $2}')"
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
        ${pkgs.btrfs-progs}/bin/btrfs filesystem mkswapfile -s "$SIZE" /mnt/swap/swapfile
        ${pkgs.util-linux}/bin/swapon /mnt/swap/swapfile
    }

    # update auto-generated configuration.nix & hardware-configuration.nix files
    createConfig() {
        nixos-generate-config --root /mnt
        if [ "$enableFIDO2" = true ]; then
            ${pkgs.gnused}/bin/sed -i "/boot.initrd.luks.devices.\"$hostname\".device = */a boot.initrd.luks.devices.\"$hostname\".crypttabExtraOpts = \[ \"fido2-device=auto\" \];" /mnt/etc/nixos/hardware-configuration.nix
        fi
        ${pkgs.gnused}/bin/sed -i "s~swapDevices = \[ \];~swapDevices = \[ { device = \"/swap/swapfile\"; } \];~" /mnt/etc/nixos/hardware-configuration.nix
        if [ "$enableHibernation" = true ]; then
            ${pkgs.gnused}/bin/sed -i "/^}/i boot.resumeDevice = \"/dev/disk/by-label/$hostname\";" /mnt/etc/nixos/hardware-configuration.nix
            ${pkgs.gnused}/bin/sed -i "/^}/i boot.kernelParams = \[ \"mem_sleep_default=deep\" \"resume_offset=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)\" \];" /mnt/etc/nixos/hardware-configuration.nix
            ${pkgs.gnused}/bin/sed -i "/^}/i services.logind.lidSwitch = \"suspend-then-hibernate\";" /mnt/etc/nixos/hardware-configuration.nix
            ${pkgs.gnused}/bin/sed -i "/^}/i systemd.sleep.extraConfig = \"HibernateDelaySec=1h\";" /mnt/etc/nixos/hardware-configuration.nix # TODO: currently broken as a result of https://github.com/systemd/systemd/issues/25269
            ${pkgs.gnused}/bin/sed -i "s~options = \[ \"subvol=@\" \];~options = \[ \"subvol=@\" \"x-systemd.after=local-fs-pre.target\" \];~" /mnt/etc/nixos/hardware-configuration.nix # TODO: workaround for https://github.com/NixOS/nixpkgs/issues/213122
        fi
        if [ ! -d /sys/firmware/efi/efivars ]; then
            ${pkgs.gnused}/bin/sed -i "s~# boot.loader.grub.device = \"/dev/sda\";~boot.loader.grub.device = \"$drive\";~" /mnt/etc/nixos/configuration.nix
        fi
        ${pkgs.gnused}/bin/sed -i "s~# networking.hostName = \"nixos\";~networking.hostName = \"$hostname\";~" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "s~# networking.networkmanager.enable = true;~networking.networkmanager.enable = true;~" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i time.timeZone = \"America/Chicago\";" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i users.users.omer = { isNormalUser = true; initialPassword = \"password\"; extraGroups = \[ \"wheel\" \]; packages = with pkgs; \[ neovim git firefox lf \]; };" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i services.openssh.enable = true;" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i nix.settings.trusted-users = \[ \"@wheel\" \];" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i security.sudo.wheelNeedsPassword = false;" /mnt/etc/nixos/configuration.nix
        ${pkgs.gnused}/bin/sed -i "/^}/i boot.initrd.systemd.enable = true;" /mnt/etc/nixos/configuration.nix
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
    exit 0
  '';
}
