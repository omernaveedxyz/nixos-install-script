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

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/hibernate";
        fsType = "btrfs";
        options = [ "subvol=@" "compress=zstd" "noatime" "x-systemd.after=local-fs-pre.target" ];
      };
      "/nix" = {
        device = "/dev/disk/by-label/hibernate";
        fsType = "btrfs";
        options = [ "subvol=@nix" "compress=zstd" "noatime" ];
      };
      "/persistent" = {
        device = "/dev/disk/by-label/hibernate";
        fsType = "btrfs";
        options = [ "subvol=@persistent" "compress=zstd" "noatime" ];
        neededForBoot = true;
      };
      "/swap" = {
        device = "/dev/disk/by-label/hibernate";
        fsType = "btrfs";
        options = [ "subvol=@swap" "compress=zstd" "noatime" ];
      };
      "/snapshots" = {
        device = "/dev/disk/by-label/hibernate";
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

    systemd.services.backdoor.conflicts = [ "sleep.target" ];
    powerManagement.resumeCommands = "systemctl --no-block restart backdoor.service";

    boot.resumeDevice = "/dev/disk/by-label/hibernate";
    boot.kernelParams = [ "mem_sleep_default=deep" "resume_offset=140544" ]; # manually calculated with: "btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile | systemd-cat",
    services.logind.lidSwitch = "suspend-then-hibernate";
    systemd.sleep.extraConfig = "HibernateDelaySec=1h";

    networking.hostName = "hibernate";
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
  name = "Hibernation Configuration Test";

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
    virtualisation.memorySize = 8192;
    virtualisation.diskSize = 1024 * 16;
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
    machine.succeed(
      "echo y | ${install-script}/bin/install.sh --hostname=hibernate --enable-hibernation /dev/vda",
      "nix-store --load-db < ${pkgs.closureInfo { rootPaths = [ installedSystem ]; }}/registration",
      "nixos-install --root /mnt --system ${installedSystem} --no-root-passwd --no-channel-copy >&2",
    )
    machine.shutdown()

    # Start up
    hibernate = create_named_machine("hibernate")
    hibernate.start()
    assert "hibernate" in hibernate.succeed("hostname")
    assert "8G" in hibernate.succeed("swapon --show | awk 'NR==2 {print $3}'")

    # Drop in file that checks if we un-hibernated properly (and not booted fresh)
    hibernate.succeed(
      "mkdir /run/test",
      "mount -t ramfs -o size=1m ramfs /run/test",
      "echo not persisted to disk > /run/test/suspended",
    )

    # Hibernate machine
    hibernate.execute("systemctl hibernate >&2 &", check_return=False)
    hibernate.wait_for_shutdown()

    # Restore machine from hibernation, validate our ramfs file is there.
    resume = create_named_machine("resume")
    resume.start()
    resume.succeed("grep 'not persisted to disk' /run/test/suspended")

    # Ensure we don't restore from hibernation when booting again
    resume.crash()
    resume.wait_for_unit("default.target")
    resume.fail("grep 'not persisted to disk' /run/test/suspended")
  '';
}
