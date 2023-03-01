{ lib }:

{
  # Necessary modules for test virtual machine configuration.
  imports = [
    <nixpkgs/nixos/modules/profiles/installation-device.nix>
    <nixpkgs/nixos/modules/profiles/base.nix>
  ];

  nix.settings = {
    # List of binary cache URLs used to obtain pre-built binaries of Nix packages.
    substituters = lib.mkForce [ ];

    hashed-mirrors = null;

    connect-timeout = 1;
  };

  # Specify the number of cores the guest is permitted to use.
  virtualisation.cores = 4;

  # The memory size in megabytes of the virtual machine.
  virtualisation.memorySize = 8192;

  # The disk size in megabytes of the virtual machine.
  virtualisation.diskSize = 1024 * 16;

  # Additional disk images to provide to the VM.
  virtualisation.emptyDiskImages = [ 512 ];

  # The disk to be used for the root filesystem.
  virtualisation.bootDevice = "/dev/vdb";
}
