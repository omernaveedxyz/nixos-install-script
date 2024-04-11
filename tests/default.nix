{pkgs}: {
  base = pkgs.nixosTest ./base.nix;
  hibernate = pkgs.nixosTest ./hibernate.nix;
  luks = pkgs.nixosTest ./luks.nix;
  luks-hibernate = pkgs.nixosTest ./luks-hibernate.nix;
  fido = pkgs.nixosTest ./fido.nix;
  zfs = pkgs.nixosTest ./zfs.nix;
  zfs-luks = pkgs.nixosTest ./zfs-luks.nix;
}
