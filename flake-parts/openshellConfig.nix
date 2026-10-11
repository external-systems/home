# OpenShell sandbox config, generated: the code-agent sandbox POLICY
# (openshell/policies/code-agent.yaml) and the github-agent PROVIDER
# PROFILE (openshell/profiles/github-agent.yaml), rendered from their
# templates with the exact store paths of the image's own package set.
#
# Why generated: the gateway admits egress per process, matching
# /proc/pid/exe against the binary lists in these files, and the sandbox
# image is content-rebuilt from this flake on every input bump.
# Hand-written `/nix/store/*-pkg-*/bin/pkg` globs drift silently — the
# github MCP server's pin existed in git but not on the gateway, and its
# api.github.com egress died with EACCES while `gh` kept working. The
# templates carry structure + comments; this module interpolates the
# store paths from the SAME pkgs the image is built from
# (flake-parts/ociImages/code-agent.nix), so image and gateway config
# can never disagree about which binary may call which host.
#
# Resolved exes, not bin/ symlinks: the supervisor matches
# /proc/<pid>/exe — the RESOLVED exe — and nixpkgs bin/ entries are not
# always real files. `nix`'s bin/nix is a symlink into another output;
# pinning the symlink path silently denied EVERY nix egress (github.com
# tarball fetches EACCES'd while git/curl worked — same bug class as
# gh's .gh-wrapped and pi's libexec/pi/pi). Every placeholder is
# therefore filled with the readlink -f target, resolved inside the
# render derivation (no IFD), and an unresolved placeholder or
# non-executable target fails the build.
#
# Runtime lifecycle (devenv script): `code-sandbox sync` renders these
# and pushes them to the gateway on drift; `code-sandbox doctor`
# reports read-only; `code-sandbox create` syncs automatically.
#
# Deliberate exception: the kimi_for_coding policy entry keeps the
# `*-nodejs*/bin/node` wildcard (see the policy template) — kimi-code's
# nodejs comes from the llm-agents input's own nixpkgs closure, not this
# flake's pkgs.nodejs, so an interpolated path could deny kimi egress
# after an input bump.
{self, ...}: {
  perSystem = {
    pkgs,
    inputs',
    customLib,
    ...
  }: let
    inherit (pkgs) lib;

    # Fill a template's @bin_*@ placeholders with the RESOLVED exe
    # paths of the given binaries (see the header above).
    renderSandboxConfig = name: template: bins:
      pkgs.runCommand name {} ''
        cp ${template} $out
        for pair in ${
          lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "${n}:${v}") bins)
        }; do
          placeholder="''${pair%%:*}"
          binary="''${pair#*:}"
          target="$(readlink -f "$binary")"
          if [ ! -x "$target" ]; then
            echo "renderSandboxConfig: $binary does not resolve to an executable" >&2
            exit 1
          fi
          sed -i "s|@''${placeholder}@|$target|g" $out
        done
        # Collapse adjacent identical lines: two placeholders can
        # resolve to the same target (bin_python3 and bin_python3_real
        # both resolve to bin/python3.14 — nixpkgs' bin/python3 is a
        # symlink), rendering duplicate `- { path: ... }` entries
        # (observed in the rendered policy, 2026-10). Adjacent-only on
        # purpose: identical adjacent YAML lines are never meaningful
        # here, and collapsing ONLY adjacent dupes cannot touch a
        # repeated endpoint line in a different policy entry.
        awk '{ if ($0 == prev) next; print; prev = $0 }' $out > dedup.tmp
        mv dedup.tmp $out
        # A leftover @bin_<name>@ means the template and this list
        # drifted apart — fail loudly instead of shipping a literal
        # placeholder to the gateway. (Digit-inclusive class: the
        # placeholder names contain digits, e.g. bin_python3.)
        if grep -qE '@bin_[a-z0-9_]+@' $out; then
          echo "renderSandboxConfig: unresolved @bin_*@ placeholder in ${template}" >&2
          exit 1
        fi
      '';
  in {
    packages = {
      # The installable wrapper: baked with THIS repo's source store
      # path (not ".") so hosts can put it on PATH (pkgs.code-sandbox
      # via overlays/default.nix) and run it from ANY directory — no
      # checkout, flake, or devenv required at the call site. All
      # image/policy/profile attrs resolve against the baked ref;
      # `--flake REF` overrides per invocation. `remoteFlake` backs the
      # rev-pinning fallback: with no git metadata in the baked source
      # path, the image builds from the public flake at remote HEAD so
      # the in-image briefing pins a real commit (see
      # documentation/docs/openshell/code-sandbox.md).
      # The script ships WITH its bash completion. code-sandbox is a
      # plain shell wrapper (there is no clap to generate completions
      # from), so the completion is a static file — subcommands +
      # flags, and live sandbox names for connect/delete/exec — merged
      # into the package itself. Every install path gets it then, not
      # just home-manager: NixOS systemPackages, nix run, home.packages.
      code-sandbox = pkgs.buildEnv {
        name = "code-sandbox";
        paths = [
          (pkgs.writeShellScriptBin "code-sandbox" (customLib.mkCodeSandbox {
            flakeRef = builtins.toString self;
            remoteFlake = "github:external-systems/home";
            # The installed wrapper tracks the LIVE repo head: bare
            # `code-sandbox` builds image/policy/profile from
            # github:external-systems/home@<remote HEAD> — never the
            # stale baked store path, never a dirty checkout.
            alwaysRemote = true;
          }))
          (pkgs.writeTextDir "share/bash-completion/completions/code-sandbox" ''
            _code_sandbox() {
              local cur cmds names
              cur="''${COMP_WORDS[COMP_CWORD]}"
              cmds="create delete connect exec ssh-config sync doctor"
              if [ "$COMP_CWORD" -eq 1 ]; then
                COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
                return
              fi
              case "''${COMP_WORDS[1]}" in
                connect | delete | exec)
                  if [ "$COMP_CWORD" -eq 2 ]; then
                    names="$(openshell sandbox list 2>/dev/null \
                      | awk 'NF && $1 !~ /^[Nn][Aa][Mm][Ee]|^-+$/ {print $1}')"
                    COMPREPLY=($(compgen -W "$names" -- "$cur"))
                  fi
                  ;;
                create)
                  COMPREPLY=($(compgen -W "-y --yes --cpu --memory --flake --provider --sync --no-sync --include-workdir --no-include-workdir --ssh-config --no-ssh-config --ssh-config-file -h --help" -- "$cur"))
                  ;;
              esac
            }
            complete -F _code_sandbox code-sandbox
          '')
        ];
      };
      code-agent-policy = renderSandboxConfig "code-agent-policy" (customLib.relativeToRoot "openshell/policies/code-agent.yaml") {
        bin_nix = "${pkgs.nix}/bin/nix";
        bin_git = "${pkgs.git}/bin/git";
        bin_curl = "${pkgs.curl}/bin/curl";
        bin_wget = "${pkgs.wget}/bin/wget";
        bin_claude = "${pkgs.claude-code}/bin/claude";
        bin_claude_wrapped = "${pkgs.claude-code}/bin/.claude-wrapped";
        bin_pi = "${pkgs.pi-coding-agent}/libexec/pi/pi";
        bin_headroom = "${pkgs.headroom-slim}/bin/headroom";
        bin_python3 = "${pkgs.python3}/bin/python3";
        # pip runs in-process, so its connections carry the RESOLVED
        # interpreter exe — pin both (nixpkgs' bin/python3 is a symlink
        # to the versioned binary). python3.interpreter IS the resolved
        # absolute path already (don't re-prefix it with /bin).
        bin_python3_real = pkgs.python3.interpreter;
        bin_uv = "${pkgs.uv}/bin/uv";
        bin_go = "${pkgs.go}/bin/go";
        bin_mcp_nixos = "${inputs'.mcp-nixos.packages.mcp-nixos}/bin/mcp-nixos";
      };

      github-agent-profile = renderSandboxConfig "github-agent-profile" (customLib.relativeToRoot "openshell/profiles/github-agent.yaml") {
        bin_git = "${pkgs.git}/bin/git";
        bin_gh = "${pkgs.gh}/bin/gh";
        bin_gh_wrapped = "${pkgs.gh}/bin/.gh-wrapped";
        bin_github_mcp_server = "${pkgs.unstable.github-mcp-server}/bin/github-mcp-server";
      };
    };
  };
}
