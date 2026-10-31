# Dev partition: the org base (treefmt, lock-sync, docs) from pkgs.
# Machine evaluation never reads it. `nix flake check` also evaluates
# every nixosConfiguration (the clan machines) on its own.
{inputs, ...}: {
  imports = [
    inputs.org-pkgs.flakeModules.dev
    ../documentation/flake-module.nix
  ];

  # Full-size desktop wallpapers are kept as-is; sizelint's 2 MB cap is
  # meant for code and generated files.
  perSystem.treefmt.settings.formatter.sizelint.excludes = [
    "documentation/docs/assets/wallpapers/*"
  ];
}
