# clan-cli at the same clan-core pin the machines use, for the devenv
# shell's `clan` script (devenv.nix) and `nix run .#clan-cli`. A
# re-export, not a build: home builds no packages of its own.
_: {
  perSystem = {
    inputs',
    lib,
    pkgs,
    ...
  }: {
    # clan-core pins nixVersions.nix_2_31 for its own CI timing; the org
    # nixpkgs (which clan-core follows) has removed it. Use the default
    # nix instead.
    packages.clan-cli =
      (inputs'.clan-core.packages.clan-cli.override {inherit (pkgs) nix;}).overrideAttrs
      (old: {
        # Structured attributes preserve list-item boundaries, so split
        # clan-core's combined --unset arguments for makeWrapper.
        makeWrapperArgs =
          lib.concatMap (
            arg:
              if lib.hasPrefix "--unset " arg
              then lib.splitString " " arg
              else [arg]
          )
          old.makeWrapperArgs;
      });
  };
}
