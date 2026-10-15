{
  perSystem = {pkgs, ...}: {
    # Formatter: `nix fmt .`
    formatter = pkgs.alejandra;

    # Mkdocs (mkdocs-flake module, imported in flake.nix):
    #   nix build .#documentation      → ./result is the static website
    #   nix run .#watch-documentation  → live preview on http://127.0.0.1:8000
    documentation = {
      mkdocs-root = ../documentation;
      # Broken links / missing nav pages fail the build instead of warning.
      strict = true;
    };
  };
}
