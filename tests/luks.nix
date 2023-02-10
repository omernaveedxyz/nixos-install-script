{ lib, pkgs, system ? builtins.currentSystem, ... }:

with lib;

let

  # Do not execute nixos-install from script. Will be run manually in testScript.
  install-script = (
    pkgs.writeShellScriptBin "install.sh" (
      builtins.replaceStrings [ "nixos-install --no-root-passwd" ] [ "" ] (
        builtins.readFile ../install.sh
      )
    )
  );

  # Configuration of client machine afer installation.
  installedConfig = {
    imports = [
      <nixpkgs/nixos/modules/testing/test-instrumentation.nix>
      <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
      <nixpkgs/nixos/modules/profiles/minimal.nix>
    ];

    boot.initrd.luks.devices."luks".device = "/dev/disk/by-label/luks-luks";

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/luks";
        fsType = "btrfs";
        options = [ "subvol=@" "compress=zstd" "noatime" ];
      };
      "/nix" = {
        device = "/dev/disk/by-label/luks";
        fsType = "btrfs";
        options = [ "subvol=@nix" "compress=zstd" "noatime" ];
      };
      "/persistent" = {
        device = "/dev/disk/by-label/luks";
        fsType = "btrfs";
        options = [ "subvol=@persistent" "compress=zstd" "noatime" ];
        neededForBoot = true;
      };
      "/swap" = {
        device = "/dev/disk/by-label/luks";
        fsType = "btrfs";
        options = [ "subvol=@swap" "compress=zstd" "noatime" ];
      };
      "/snapshots" = {
        device = "/dev/disk/by-label/luks";
        fsType = "btrfs";
        options = [ "subvol=@snapshots" "compress=zstd" "noatime" ];
      };
      "/boot" = {
        device = "/dev/disk/by-label/BOOT";
        fsType = "vfat";
      };
    };

    swapDevices = [{ device = "/swap/swapfile"; }];

    boot.loader.grub.device = "/dev/vda";

    networking.hostName = "luks";
    time.timeZone = "America/Chicago";
    users.users.omer = { isNormalUser = true; initialPassword = "password"; extraGroups = [ "wheel" ]; };
    services.openssh.enable = true;
    nix.settings.trusted-users = [ "@wheel" ];
    security.sudo.wheelNeedsPassword = false;
    boot.initrd.systemd.enable = true;
  };

  installedSystem = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit system;
    modules = [ installedConfig ];
  }).config.system.build.toplevel;

in
{
  name = "Luks Configuration Test";

  # Configuration of machine for install.
  nodes.machine = {
    imports = [
      <nixpkgs/nixos/modules/profiles/installation-device.nix>
      <nixpkgs/nixos/modules/profiles/base.nix>
    ];

    nix.settings = {
      substituters = mkForce [ ];
      hashed-mirrors = null;
      connect-timeout = 1;
    };

    virtualisation.cores = 4;
    virtualisation.memorySize = 4196;
    virtualisation.diskSize = 1024 * 8;
    virtualisation.emptyDiskImages = [ 512 ];
    virtualisation.bootDevice = "/dev/vdb";
  };

  testScript = ''
    def create_named_machine(name):
      machine = create_machine(
        {
          "qemuFlags": "-cpu max ${
            if system == "x86_64-linux" then "-m 2048"
            else "-m 768 -enable-kvm -machine virt,gic-version=host"}",
          "hdaInterface": "virtio",
          "hda": "vm-state-machine/machine.qcow2",
          "name": name,
        }
      )
      driver.machines.append(machine)
      return machine

    # installation
    machine.start()

    machine.fail("echo y | ${install-script}/bin/install.sh --hostname=luks --enable-luks= /dev/vda")

    machine.succeed(
      "echo y | ${install-script}/bin/install.sh --hostname=luks --enable-luks=supersecretpassword /dev/vda",
      "nix-store --load-db < ${pkgs.closureInfo { rootPaths = [ installedSystem ]; }}/registration",
      "nixos-install --root /mnt --system ${installedSystem} --no-root-passwd --no-channel-copy >&2",
    )
    machine.shutdown()

    # verify that client boots with luks encryption
    client = create_named_machine("client")
    client.start()
    client.wait_for_console_text("Please enter passphrase or recovery key for disk luks")
    client.send_console("supersecretpassword\n")
    client.wait_for_unit("multi-user.target")
        
    assert "luks" in client.succeed("hostname")
    assert "4G" in client.succeed("swapon --show | awk 'NR==2 {print $3}'")
    assert "/dev/mapper/luks on / type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /nix type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /persistent type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /swap type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /snapshots type btrfs" in client.succeed("mount")
    assert "/dev/vda1 on /boot type vfat" in client.succeed("mount")
  '';
}
