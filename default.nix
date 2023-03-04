{ pkgs ? let
    # if pkgs is not defined, instanciate nixpkgs from locked commit
    lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
    nixpkgs = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
  in
  import nixpkgs { }
}:

{
  # series of tests that can be run to validate script functionality
  # accessible through `nix-build -A tests.<name>`
  tests = {
    default = pkgs.nixosTest ./tests/default.nix;
    hibernate = pkgs.nixosTest ./tests/hibernate.nix;
    hibernate2 = pkgs.nixosTest ./tests/hibernate2.nix;
    luks = pkgs.nixosTest ./tests/luks.nix;
    luks2 = pkgs.nixosTest ./tests/luks2.nix;
    fido = pkgs.nixosTest ./tests/fido.nix;
    fido2 = pkgs.nixosTest ./tests/fido2.nix;
  };
}
