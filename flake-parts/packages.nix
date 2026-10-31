# clan-cli at the same clan-core pin the machines use, for the devenv
# shell's `clan` script (devenv.nix) and `nix run .#clan-cli`. A
# re-export, not a build: home builds no packages of its own.
_: {
  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    # clan-core pins nixVersions.nix_2_31 for its own CI timing; the org
    # nixpkgs (which clan-core follows) has removed it. Use the default
    # nix instead.
    packages.clan-cli = inputs'.clan-core.packages.clan-cli.override {inherit (pkgs) nix;};
  };
}
