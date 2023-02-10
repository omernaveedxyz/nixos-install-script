{ pkgs ? import <nixpkgs> { } }: {
  tests = {
    default = pkgs.nixosTest ./tests/default.nix;
    hibernate = pkgs.nixosTest ./tests/hibernate.nix;
    luks = pkgs.nixosTest ./tests/luks.nix;
    luks2 = pkgs.nixosTest ./tests/luks2.nix;
    fido = pkgs.nixosTest ./tests/fido.nix;
    fido2 = pkgs.nixosTest ./tests/fido2.nix;
  };
}
