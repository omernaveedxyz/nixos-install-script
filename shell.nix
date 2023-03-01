{ pkgs ? import <nixpkgs> { } }: pkgs.mkShell {

  # Run-time dependencies for running installation script.
  nativeBuildInputs = with pkgs; [
    git # Acess to repository
    nix # Access nix-shell & nix-build commands
    systemd # Access to systemd-cryptenroll
    util-linux # Various system utilities
    gptfdisk # Format UEFI partitions
    dosfstools # Format into FAT32 partition
    btrfs-progs # Format into BTRFS paritions
  ];

}
