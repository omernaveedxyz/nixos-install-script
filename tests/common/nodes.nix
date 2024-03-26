{
  lib,
  pkgs,
  hibernation ? false,
  fido ? false,
  ...
}: let
  inherit (lib) mkForce;
  lock = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.nixpkgs.locked;
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
    sha256 = lock.narHash;
  };
in {
  machine = {
    # Necessary modules for test virtual machine configuration
    imports = [
      "${nixpkgs}/nixos/modules/profiles/installation-device.nix"
      "${nixpkgs}/nixos/modules/profiles/base.nix"
      "${nixpkgs}/nixos/tests/common/auto-format-root-device.nix"
    ];

    # Specify the number of cores the guest is permitted to use
    virtualisation.cores = 2;

    # The memory size in megabytes of the virtual machine
    virtualisation.memorySize =
      if hibernation
      then (1024 * 8)
      else (1024 * 4);

    # The disk size in megabytes of the virtual machine
    virtualisation.diskSize =
      if hibernation
      then (1024 * 16)
      else (1024 * 8);

    # Additional disk images to provide to the VM
    virtualisation.emptyDiskImages = [512];

    # The disk to be used for the root filesystem
    virtualisation.rootDevice = "/dev/vdb";

    # The path (inside the vm) to the device to boot from when legacy booting
    virtualisation.bootLoaderDevice = "/dev/vda";

    # The interface used for the virtual hard disks
    virtualisation.qemu.diskInterface = "virtio";

    # Automatically format the root device
    virtualisation.fileSystems."/".autoFormat = true;

    # The set of packages that appear in /run/current-system/sw
    environment.systemPackages = with pkgs; [nixos-install-script];

    # We don't want to have any networking in the guest whatsoever.
    # Also, if any vlans are enabled, the guest will reboot
    # (with a different configuration for legacy reasons),
    # and spend 5 minutes waiting for the vlan interface to show up
    # (which will never happen).
    virtualisation.vlans = [];

    # List of binary cache urls used to obtain pre-built binaries of nix packages
    nix.settings.substituters = mkForce [];

    # A list of web servers used by builtins.fetchurl to obtain files by hash
    nix.settings.hashed-mirrors = null;

    # The timeout (in seconds) for establishing connections in the binary cache substituter
    nix.settings.connect-timeout = 1;

    # The test cannot access the network, so any packages we need must be included in the VM.
    system.extraDependencies = with pkgs; [
      bintools
      brotli
      brotli.dev
      brotli.lib
      desktop-file-utils
      docbook5
      docbook_xsl_ns
      kbd.dev
      kmod.dev
      libarchive.dev
      libxml2.bin
      libxslt.bin
      nixos-artwork.wallpapers.simple-dark-gray-bottom
      ntp
      perlPackages.ListCompare
      perlPackages.XMLLibXML
      (python3.withPackages (p: [p.mistune]))
      shared-mime-info
      sudo
      texinfo
      unionfs-fuse
      xorg.lndir

      # Add curl so that rather than seeing the test attempt to download curl's tarball, we see what it's trying to download
      curl

      grub2
      grub2_efi
    ];

    # QEMU package to use
    virtualisation.qemu.package = lib.mkForce (pkgs.qemu_test.override {canokeySupport = fido;});

    # Options passed to QEMU
    virtualisation.qemu.options =
      if fido
      then ["-device canokey,file=/tmp/canokey-file"]
      else [];

    # Whether to enable systemd in initrd
    boot.initrd.systemd.enable = fido;
  };
}
