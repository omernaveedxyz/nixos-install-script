{ hostName }:

{
  # necessary modules for test virtual machine configuration
  imports = [
    <nixpkgs/nixos/modules/testing/test-instrumentation.nix>
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];

  # the file systems to be mounted
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/${hostName}";
      fsType = "btrfs";
      options = [ "subvol=@" "compress=zstd" "noatime" ];
    };
    "/nix" = {
      device = "/dev/disk/by-label/${hostName}";
      fsType = "btrfs";
      options = [ "subvol=@nix" "compress=zstd" "noatime" ];
    };
    "/persistent" = {
      device = "/dev/disk/by-label/${hostName}";
      fsType = "btrfs";
      options = [ "subvol=@persistent" "compress=zstd" "noatime" ];
      neededForBoot = true;
    };
    "/swap" = {
      device = "/dev/disk/by-label/${hostName}";
      fsType = "btrfs";
      options = [ "subvol=@swap" "compress=zstd" "noatime" ];
    };
    "/snapshots" = {
      device = "/dev/disk/by-label/${hostName}";
      fsType = "btrfs";
      options = [ "subvol=@snapshots" "compress=zstd" "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };
  };

  # the swap devices and swap files
  swapDevices = [{ device = "/swap/swapfile"; }];

  # the device on which the GRUB boot loader will be installed
  boot.loader.grub.device = "/dev/vda";

  # the name of the machine
  networking.hostName = "${hostName}";

  # the time zone used when displaying times and dates
  time.timeZone = "America/Chicago";

  users.users.omer = {
    # indicates whether this is an account for a “real” user
    isNormalUser = true;

    # specifies the initial password for the user, i.e. the password assigned if the user does
    # not already exist
    initialPassword = "password";

    # he user’s auxiliary groups
    extraGroups = [ "wheel" ];
  };

  # whether to enable the OpenSSH secure shell daemon, which allows secure remote logins
  services.openssh.enable = true;

  # a list of names of users that have additional rights when connecting to the Nix daemon,
  # such as the ability to specify additional binary caches, or to import unsigned NARs
  nix.settings.trusted-users = [ "@wheel" ];

  # whether users of the wheel group must provide a password to run commands as super user via
  # sudo
  security.sudo.wheelNeedsPassword = false;

  # whether to enable systemd in initrd
  boot.initrd.systemd.enable = true;
}
