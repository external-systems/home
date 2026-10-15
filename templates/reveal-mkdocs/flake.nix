{
  description = "Static website (MkDocs) + slide deck (reveal.js), built with Nix";

  # Every outside dependency is an input below. `flake.lock` records the
  # exact commit + content hash of each one, so every machine builds the
  # same site. Update them with `nix flake update` (all) or
  # `nix flake update <name>` (one).
  inputs = {
    # Nixpkgs — the package set (python, mkdocs' runtime, alejandra, ...).
    # Pinned to a stable release branch; flake.lock holds the exact commit.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Utility Flakes
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";

    # Mkdocs — flake-parts module: set `documentation.mkdocs-root` and get
    # `packages.documentation` + `apps.watch-documentation`
    # (flake-parts/default.nix). Ships mkdocs + Material + common plugins.
    mkdocs-flake = {
      url = "github:applicative-systems/mkdocs-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    # reveal.js — source only (not a flake). Release tags commit the
    # prebuilt `dist/` (reveal.js, themes, plugins), so the slides need
    # zero npm: flake-parts/slides.nix copies `dist/` next to slides/.
    # Upgrade by bumping the tag, then `nix flake update reveal-js`.
    reveal-js = {
      url = "github:hakimel/reveal.js?ref=6.0.2";
      flake = false;
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      # Add "aarch64-linux" / "aarch64-darwin" here to build on those too.
      systems = [
        "x86_64-linux"
      ];

      imports = [
        # Every .nix file under ./flake-parts is a flake-parts module,
        # loaded automatically — no import list to keep in sync.
        (inputs.import-tree ./flake-parts)
        inputs.mkdocs-flake.flakeModules.default
      ];
    };
}
