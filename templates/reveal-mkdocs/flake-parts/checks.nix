{
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    config,
    ...
  }: {
    # `nix flake check` builds everything here.
    checks = {
      # Both build artifacts must build.
      inherit (config.packages) documentation slides;

      # Lint gate: alejandra (format), statix (anti-patterns), deadnix
      # (unused code). Fix findings with `nix fmt .`, `statix fix .` and
      # `deadnix -e .` (all three are in `nix develop`).
      lint =
        pkgs.runCommand "lint" {
          nativeBuildInputs = with pkgs; [alejandra statix deadnix];
        } ''
          cd ${lib.sources.sourceFilesBySuffices self [".nix"]}
          alejandra --check .
          statix check .
          deadnix --fail .
          touch $out
        '';
    };

    # `nix develop` — the linters, for running them outside a check.
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [alejandra statix deadnix];
    };
  };
}
