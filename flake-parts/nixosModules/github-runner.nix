_: {
  # ------ NixOS Modules ------ #
  # Self-hosted GitHub Actions runners for nix CI, org runners only.
  #
  # Enable per org, per host:
  #   hostSpec.services.github-runner.org.external-systems.enable = true;
  #
  # Each enabled org gets `count` (default 1) ephemeral runners backed by
  # nixpkgs' services.github-runners. Runners register as
  # <hostName>-<org> against https://github.com/<org> and carry the default
  # labels (self-hosted, linux, x86_64) plus <hostName>, <org> and any
  # org-specific extraLabels — workflows target `runs-on: self-hosted` or
  # pin a host (`runs-on: kamrui-h1`). Ephemeral means one registration per
  # job: the runner deregisters when the job finishes, the service restarts
  # with a wiped workdir, and registers anew — jobs never share state and
  # no stale "offline" registrations accumulate. Each start exchanges the
  # PAT for a fresh short-lived registration token (the PAT itself is never
  # consumed), so this costs a few seconds of per-job startup, never a
  # `clan vars generate` (see "Auth" below).
  #
  # Auth: one long-lived PAT per org, prompt-provisioned through clan vars
  # (sops-encrypted, committed under vars/shared/):
  #   github-runner-<org>/pat
  # consumed via the canonical generator file path
  # (config.clan.core.vars.generators.<gen>.files.pat.path — the sops-nix
  # runtime path /run/secrets/vars/shared/github-runner-<org>/pat once
  # deployed; until `clan vars generate` runs, the generator declares no
  # sops entry and .path is the inert "/no-such-path" placeholder). The
  # deployed file is owned by the `github-runner` user, mode 0400 — that
  # alone grants access: sops-nix creates every directory in the
  # /run/secrets chain 0751 root:keys ("other" holds the traverse bit —
  # verified in sops-install-secrets/main.go), so no `keys` group
  # membership is needed.
  #
  # The PAT is NOT consumed by jobs: the nixpkgs service exchanges it for a
  # short-lived registration token only when a (re)configuration happens.
  # `clan vars generate` therefore runs once per PAT, and rotation is:
  # update the var, redeploy.
  #
  # PAT requirements (create at https://github.com/settings/tokens):
  #   fine-grained: resource owner = the org, org permission
  #                 "Self-hosted runners" (Read and write)
  #   classic:      scope admin:org
  #
  # Provisioning (after enabling on a host):
  #   clan vars generate kamrui-h1   # prompts for the PAT
  #
  # The runner user is a nix trusted user (jobs drive the system nix
  # daemon) and is in the kvm group, with /dev/kvm exposed to the nix
  # build sandbox so NixOS VM tests get KVM.
  flake.nixosModules.github-runner = {
    config,
    pkgs,
    lib,
    ...
  }: let
    cfg = config.hostSpec.services.github-runner;
    inherit (config.networking) hostName;
    inherit (config.nixpkgs.hostPlatform) system;

    runnerUser = "github-runner";
    runnerGroup = "github-runner";

    # Orgs actually enabled on this host; everything keys off this set so
    # untouched orgs declare no generators, no runners and no users.
    enabledOrgs = lib.filterAttrs (_: org: org.enable) cfg.org;
  in {
    options.hostSpec.services.github-runner = {
      org = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            enable = lib.mkEnableOption "a GitHub Actions runner for the ${name} org";
            count = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
              description = ''
                Number of parallel ephemeral runner instances for this org
                on this host. Each instance is its own systemd service
                (github-runner-<org>[-<n>]) and its own registration.
              '';
            };
            url = lib.mkOption {
              type = lib.types.str;
              default = "https://github.com/${name}";
              description = "Org (not repo) URL — org-wide tokens 404 against repo URLs.";
            };
            extraLabels = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra labels on top of the defaults and <hostName>/<org>.";
            };
          };
        }));
        default = {};
        description = "GitHub orgs this host runs self-hosted Actions runners for.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          # CI-ready toolset on every runner's PATH (on top of what the
          # nixpkgs service ships: nix, git, coreutils, gnutar, gzip,
          # bash). Keep this lean — jobs should get project tooling from
          # the repo's flake (nix develop / packages), not the host.
          gh # gh run view --log-failed / gh release — no API tokens in workflows
          jq # JSON munging (dynamic matrices, nix eval --json output)
          yq-go # YAML in workflows/scripts
          curl
          wget
          openssh # ssh-ng:// remote builders
          git-lfs # repos with LFS assets check out cleanly
        ];
        defaultText = lib.literalExpression "with pkgs; [ gh jq yq-go curl wget openssh git-lfs ]";
        description = ''
          Extra packages on all runners' PATH (nix, git, coreutils, gnutar,
          gzip and bash ship with the nixpkgs service already). The default
          is the CI-ready set every flake repo workflow assumes is present.
        '';
      };
    };

    config = lib.mkIf (enabledOrgs != {}) {
      # One PAT prompt per org, shared across hosts (reused by any future
      # host enabling the same org). The deployed file is what nixpkgs'
      # tokenFile points at.
      clan.core.vars.generators =
        lib.mapAttrs' (
          name: _:
            lib.nameValuePair "github-runner-${name}" {
              share = true;
              prompts.pat = {
                description = "GitHub PAT (org self-hosted runners R/W / admin:org) for the ${name} org runners";
                display.group = "github";
                type = "hidden";
                persist = true;
              };
              files.pat = {
                owner = runnerUser;
                group = runnerGroup;
                mode = "0400";
              };
            }
        )
        enabledOrgs;

      services.github-runners =
        lib.mapAttrs (
          name: org: {
            enable = true;
            inherit (org) count url;
            name = "${hostName}-${name}";
            # Canonical clan vars consumption: the generator file's .path
            # (the sops-nix runtime path). Inert "/no-such-path" until the
            # var is generated.
            tokenFile = config.clan.core.vars.generators."github-runner-${name}".files.pat.path;
            inherit (config.hostSpec.services.github-runner) extraPackages;
            user = runnerUser;
            group = runnerGroup;
            # Ephemeral: one registration per job, workdir wiped on every
            # service start (see header). The PAT is exchanged for a
            # registration token at each start but never consumed.
            ephemeral = true;
            replace = true;
            extraLabels = [hostName system name] ++ org.extraLabels;
          }
        )
        enabledOrgs;

      users.users.${runnerUser} = {
        isSystemUser = true;
        group = runnerGroup;
        # kvm: /dev/kvm for NixOS VM tests. No sops `keys` group needed —
        # the 0751 /run/secrets dirs let any user traverse to the
        # owner-tagged file (see header).
        extraGroups = ["kvm"];
      };
      users.groups.${runnerGroup} = {};

      nix.settings = {
        # CI jobs run nix builds through the system daemon.
        trusted-users = [runnerUser];
        # Honor each repo flake's own nixConfig (extra-substituters +
        # trusted-public-keys) so jobs use the binary caches the flake
        # declares instead of rebuilding from source. Safe here: the
        # flake-config substituters are only honored for trusted users,
        # and the runner user is trusted (above).
        accept-flake-config = true;
        # NixOS VM tests (nix build .#checks.*) need the host's KVM device
        # visible inside the build sandbox.
        extra-sandbox-paths = ["/dev/kvm"];
      };
    };
  };
}
