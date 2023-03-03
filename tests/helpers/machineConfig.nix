{ lib }:

{
  # necessary modules for test virtual machine configuration
  imports = [
    <nixpkgs/nixos/modules/profiles/installation-device.nix>
    <nixpkgs/nixos/modules/profiles/base.nix>
  ];

  nix.settings = {
    # list of binary cache URLs used to obtain pre-built binaries of Nix packages
    substituters = lib.mkForce [ ];

    hashed-mirrors = null;

    connect-timeout = 1;
  };

  # specify the number of cores the guest is permitted to use
  virtualisation.cores = 4;

  # the memory size in megabytes of the virtual machine
  virtualisation.memorySize = 8192;

  # the disk size in megabytes of the virtual machine
  virtualisation.diskSize = 1024 * 16;

  # additional disk images to provide to the VM
  virtualisation.emptyDiskImages = [ 512 ];

  # the disk to be used for the root filesystem
  virtualisation.bootDevice = "/dev/vdb";
}
