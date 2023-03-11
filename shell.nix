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

pkgs.mkShell {
  # enable experimental feature: nix flakes
  NIX_CONFIG = "experimental-features = nix-command flakes";

  # run-time dependencies for running installation script
  nativeBuildInputs = with pkgs; [
    git # acess to repository
    nix # access nix-shell & nix-build commands
  ];
}
