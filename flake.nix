{
  description = "Dendritic Nix Flake";

  nixConfig = {
    extra-substituters = [
      "https://openshell.cachix.org"
      "https://devenv.cachix.org"
      "https://cache.clan.lol"
      "https://nix-community.cachix.org"
      "https://chaotic-nyx.cachix.org"
      "https://cache.geninf.io"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "openshell.cachix.org-1:OAr5MunsfH5PZvUsfD08OtGx5RtcwdNZGJdU5FqLm5w="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cache.clan.lol-1:3KztgSAB5R1M+Dz7vzkBGzXdodizbgLXGXKXlcQLA28="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n8ae7W70yP3m9y9633ndgliTLGsQI="
      "cache.geninf.io-1:uhEViaczNKSoerYM+w7uqXUzlAhnbEBKsFzgg9n3cvI="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    # Nixpkgs — owned by clan-core (single source of truth for the pin)
    nixpkgs.follows = "clan-core/nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Clan.lol
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";

    # Clan.lol Community
    clan-community = {
      url = "git+https://git.clan.lol/andrewthomaslee/clan-community.git?ref=feat/rancher";
      inputs.clan-core.follows = "clan-core";
    };

    # Mkdocs
    mkdocs-flake = {
      url = "github:applicative-systems/mkdocs-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # MkDocs + reveal.js slides: exports flakeModules.slides
    # (packages.slides, apps.serve-slides, /slides/ embed into the docs
    # site) and lib.mkSlides. The reveal.js pin travels inside it.
    presenting = {
      url = "github:external-systems/presenting";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        mkdocs-flake.follows = "mkdocs-flake";
      };
    };

    # Home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # KDE
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Utility Flakes
    flake-parts.follows = "clan-core/flake-parts";
    import-tree.url = "github:denful/import-tree";

    # ------ Packages ------ #
    # Zen Browser
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Scripts
    moscripts = {
      url = "https://flakehub.com/f/andrewthomaslee/moscripts/*";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Jovian NixOS
    jovian.url = "github:Jovian-Experiments/Jovian-NixOS";

    # MCP-NixOS — MCP server for NixOS / Home Manager / nix-darwin
    # package & option search (opencode mcp server).
    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # devenv — developer environments CLI (auto-activation hook, `devenv
    # mcp` MCP server). Pinned to the release tag; builds are served by
    # the devenv.cachix.org substituter already trusted in
    # nixosModules/nix.nix.
    devenv.url = "github:cachix/devenv?ref=v2.4.0";
    # Required for devenv container builds:
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # NVIDIA Agent Sandboxing
    openshell.url = "github:NVIDIA/OpenShell?ref=v0.1.2";

    # ArtifactHub MCP — stdio MCP server for Helm charts on artifacthub.io
    # (opencode mcp server). Repo has no flake.nix, so the source tree is
    # pinned to the v1.1.1 tag and built with buildNpmPackage in
    # packages/artifacthub-mcp.nix.
    artifacthub-mcp = {
      url = "github:AlexW00/artifacthub-mcp?ref=v1.1.1";
      flake = false;
    };

    # Headroom — context compression layer for AI agents.
    # Pinned to the v0.40.0 manylinux_2_28 x86_64 wheel (abi3, compatible with
    # CPython 3.10–3.13). This is the prebuilt maturin/Rust extension; using
    # the wheel avoids rebuilding the cdylib from source. Used as `src` for
    # buildPythonApplication { format = "wheel"; } in packages/headroom.nix.
    headroom = {
      url = "https://files.pythonhosted.org/packages/03/1c/383f4a2d33ad18d40869037ca6221e1db24bc4da5e92befe70793220b138/headroom_ai-0.40.0-cp310-abi3-manylinux_2_28_x86_64.whl";
      flake = false;
    };

    # Whisper Dictation — local push-to-talk speech-to-text daemon (whisper.cpp)
    whisper-dictation.url = "github:jacopone/whisper-dictation";

    # numtide/llm-agents.nix — Nix packages for AI coding agents, daily
    # updated and built from source. Used for the Kimi Code CLI
    # (packages.<system>.kimi-code, exposed here as pkgs.kimi-code via
    # overlays/default.nix). nixpkgs is deliberately NOT followed: the
    # package is a from-source pnpm build, and only the pinned nixpkgs
    # combination is covered by the numtide binary cache (see nixConfig).
    llm-agents.url = "github:numtide/llm-agents.nix";

    agents = {
      url = "git+https://code.m3ta.dev/m3tam3re/AGENTS";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # ------ External agent skill sources ------ #
    # Source-only repos (no flake.nix consumed — flake = false), composed
    # into the shared agents skills tree by inputs.agents.lib.mkSkills in
    # flake-parts/homeModules/agents.nix (homeSpec.agents.skills) and
    # flake-parts/ociImages/code-agent.nix (/opt/skills in the sandbox
    # image). Keep both consumers' externalSkills lists in sync.
    # Cherry-picking happens at the consumer side via selectSkills.
    #
    # OpenShell skills need no input here: the openshell input above is
    # the full source tree, reused as a skill source (skills/ +
    # .agents/skills/ both ship SKILL.md dirs).
    skills-anthropic = {
      url = "github:anthropics/skills";
      flake = false;
    };
    skills-cloudflare = {
      url = "github:cloudflare/skills";
      flake = false;
    };
    skills-payloadcms = {
      url = "github:payloadcms/skills";
      flake = false;
    };
    skills-supabase = {
      url = "github:supabase/agent-skills";
      flake = false;
    };
    skills-fluxcd = {
      url = "github:fluxcd/agent-skills";
      flake = false;
    };
    skills-terraform = {
      url = "github:antonbabenko/terraform-skill";
      flake = false;
    };
    skills-google = {
      url = "github:google/skills";
      flake = false;
    };
    mattpocock = {
      url = "github:mattpocock/skills";
      flake = false;
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
      ];

      # Expose flake.debug.options (module-system declarations) for nixd's
      # "flake-parts" option provider and `nix repl` inspection.
      # https://flake.parts/debug
      debug = true;

      imports = [
        (inputs.import-tree ./flake-parts)
        inputs.mkdocs-flake.flakeModules.default
        # Slide deck (packages.slides, apps.serve-slides, /slides/ embed).
        # flakeModules.slides, NOT .default: mkdocs-flake is already
        # imported above, and .default would declare its options twice.
        inputs.presenting.flakeModules.slides
        inputs.clan-core.flakeModules.default
        inputs.home-manager.flakeModules.home-manager
        # devenv flake-parts module: evaluates devenv/default.nix through
        # devenv.shells.default (see flake-parts/devShells.nix) so
        # `nix develop` and the devenv CLI share one module.
        inputs.devenv.flakeModule
      ];
    };
}
