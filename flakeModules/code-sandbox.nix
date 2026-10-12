# flake-parts module for projects consuming the code-sandbox wrapper
# from this flake (plain flakes AND devenv projects whose devenv.yaml
# pulls this repo as an input):
#
#   # flake.nix of the consuming project
#   imports = [inputs.home.flakeModules.code-sandbox];
#   perSystem.codeSandbox.imageAttr = "my-agent-image";   # their attrs
#
#   # or, in a devenv project (devenv.nix — no flakeModules there):
#   scripts.code-sandbox.exec = inputs.home.lib.mkCodeSandbox {
#     imageAttr = "my-agent-image"; policyAttr = ...; profileAttr = ...;
#   };
#
# The module is exported with home's mkCodeSandbox already bound (see
# flake-parts/default.nix) — consumers never reference inputs.home
# inside their module config. Consumers get the script only: the bash
# completion that ships in home's own packages.code-sandbox (a static
# file beside the package definition, flake-parts/openshellConfig.nix)
# is not part of the generated wrapper — copy it into your package if
# you want it.
{mkCodeSandbox}: {lib, ...}: {
  # NOTE (fixed 2026-10): current flake-parts declares `perSystem` via
  # mkPerSystemOption (a module type), so options must be declared
  # INSIDE the perSystem module — `options.perSystem.codeSandbox` at
  # the flake-module level no longer evaluates ("its type `module`
  # does not support nested options").
  perSystem = {
    pkgs,
    config,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.codeSandbox;
  in {
    options.codeSandbox = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Expose packages/apps.code-sandbox for this project.";
      };
      flakeRef = mkOption {
        type = types.str;
        default = ".";
        description = ''
          Flake whose `#<attrs>` provide the sandbox image/policy/profile.
          "." resolves to the flake enclosing the cwd at runtime — the
          default for hacking on the project itself. Bake a source path or
          URL (e.g. `builtins.toString self`) for a wrapper that works from
          any directory.
        '';
      };
      remoteFlake = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "github:owner/repo";
        description = ''
          Canonical public flake ref for the rev-pinning fallback: when the
          resolved flake source is a dirty/ahead/behind git tree (or a
          git-less baked source path), the image builds from
          `<remoteFlake>/<remote HEAD>` so the in-image "Image: ... @
          <rev>" briefing always pins a real commit. null disables the
          fallback (the wrapper warns and builds the local source).
        '';
      };
      imageAttr = mkOption {
        type = types.str;
        default = "code-agent-image";
        description = "Flake attr of the nix2container OCI image.";
      };
      loaderApp = mkOption {
        type = types.str;
        default = "load-code-agent-image";
        description = "Flake app that loads the image into the host docker store.";
      };
      policyAttr = mkOption {
        type = types.str;
        default = "code-agent-policy";
        description = "Flake attr of the rendered sandbox policy YAML.";
      };
      profileAttr = mkOption {
        type = types.str;
        default = "github-agent-profile";
        description = "Flake attr of the rendered provider profile YAML.";
      };
      envAttr = mkOption {
        type = types.nullOr types.str;
        default = "code-agent-env";
        description = ''
          Flake attr of the create-time sandbox env file (KEY=VALUE lines,
          passed as `openshell sandbox create --env` flags) — the channel
          that survives the supervisor's env scrub on every spawn path.
          A missing attr warns and continues; null disables.
        '';
      };
      profileId = mkOption {
        type = types.str;
        default = "github-agent";
        description = "Gateway-side provider profile id (drift-checked by sync/doctor).";
      };
      providers = mkOption {
        type = types.listOf types.str;
        default = ["github-agent"];
        description = ''
          Base providers attached to every sandbox and checked by
          sync/doctor (github-agent — git push work is always wanted).
          The inference credential providers are added on top, selected
          per create by --inference (see inferenceProviders).
        '';
      };
      inferenceProviders = mkOption {
        type = types.listOf types.str;
        default = ["kimi-for-coding" "claude-subscription" "claude-code" "openrouter"];
        description = ''
          The inference-provider menu for --inference: which inference
          credential providers a sandbox may attach at create time. The
          image never changes per provider set — every CLI is baked in
          and the single dual-pipeline headroom proxy serves them all.
        '';
      };
      defaultInference = mkOption {
        type = types.str;
        default = "all";
        description = ''
          Default --inference value: a comma-separated subset of
          inferenceProviders, or "all" — every menu provider PRESENT on
          the gateway EXCEPT claude-code (never auto-attached: it would
          shadow claude-subscription, Claude Code ranks
          $ANTHROPIC_AUTH_TOKEN over $CLAUDE_CODE_OAUTH_TOKEN). Missing
          providers warn and are skipped under "all"; an explicit list
          is strict (a missing provider aborts create).
        '';
      };
      imageName = mkOption {
        type = types.str;
        default = "code-agent";
        description = "OCI image name for the content-hash tag.";
      };
      defaultName = mkOption {
        type = types.str;
        default = "code";
        description = "Sandbox name prefix.";
      };
      includeWorkdir = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Default for the --include-workdir toggle: mount the invoking
          directory into the sandbox workdir (/sandbox). The rendered
          policy ships `include_workdir: false` (clean, ephemeral
          sandboxes).
        '';
      };
      cpu = mkOption {
        type = types.str;
        default = "4";
        description = "Default CPUs for created sandboxes.";
      };
      memory = mkOption {
        type = types.str;
        default = "8Gi";
        description = "Default memory for created sandboxes.";
      };
    };

    config = lib.mkIf cfg.enable {
      packages.code-sandbox = pkgs.writeShellScriptBin "code-sandbox" (mkCodeSandbox {
        inherit (cfg) flakeRef remoteFlake imageAttr loaderApp policyAttr profileAttr envAttr profileId providers inferenceProviders defaultInference imageName defaultName includeWorkdir cpu memory;
      });
      apps.code-sandbox.program = "${config.packages.code-sandbox}/bin/code-sandbox";
    };
  };
}
