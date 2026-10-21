---
name: home-manager
description: "home-manager with flakes and flake-parts: NixOS-module integration, the homeSpec.* namespace, the homeModules.default composition filter, and a worked user-profile example (flake-parts/homeModules/profiles/netsa.nix). Load when building or changing a home-manager user profile."
---

# home-manager

How home-manager works, how it composes with flakes and flake-parts, and
a worked example of building a user profile. Docs:
https://nix-community.github.io/home-manager/ (options appendix mirrors
the module options; NixOS-channel users read the manual off that
release).

## How home-manager works

Home-manager manages a user's dotfiles, programs, and services as a
module system evaluation per user: the same option/`mkIf`/`mkMerge`
semantics as NixOS, pointed at `$HOME` instead of `/`. Its outputs are
activation scripts that link `~/.config`, `~/.config/systemd/user`, user
packages, and session env into the user profile.

Mental model, once per user:

```
users.<user>          # NixOS user account (users.users.<name>)
home-manager.users.<name>  # HM config for that account (NixOS-module mode)
```

In the home repo, HM modules use the `homeSpec.*` option namespace (the
repo's own options, named in the style guide's module-system section) and
the NixOS modules use `hostSpec.*`. Namespaces keep the two module sets
composable without collisions.

## How it works with flakes

Two integration shapes, both used here:

1. **NixOS module** (per-machine users): `nixosModules.home-manager`
   provides the `home-manager.users.<name>` option, evaluated inside
   each `nixosConfigurations.<host>` eval. Extra module args — e.g. the
   repo's `customLib` — are threaded once via
   `home-manager.extraSpecialArgs` (set in `nixosModules/default`, not
   per user).
2. **flakeModules** (standalone configs): the flakeModule
   (`inputs.home-manager.flakeModules.home-manager`) exposes options for
   declaring `homeConfigurations.<name>` in flake output land — use when
   a config exists outside any NixOS host.

This flake only uses the first shape: user profiles are exported as
`flake.homeModules.*` and attached per user (see below).

## Home-manager works with flakes and flake-parts

In a flake-parts flake, HM modules are ordinary flake outputs. The home
repo's pattern:

- Modules live at `flake-parts/homeModules/<name>.nix` and define
  `flake.homeModules.<name>` (directory name is organizational only —
  the file declares its own attribute; see the `import-tree` skill).
- The default module `flake.homeModules.default` does the composition:
  `nixpkgs.allowUnfree`, the repo overlay, stateVersion, and `imports`
  of every non-`profile-` module in `self.homeModules` (a filter in
  `flake-parts/default.nix`).
- Chain: `users/<user>/default.nix` (NixOS side) sets
  `home-manager.users.<name> = self.homeModules.profile-<name>;` and
  the profile imports `self.homeModules.default` for the shared
  composition, then sets only its per-user options.

That is exactly the composition filter pattern: `profile-*` modules are
opt-in (wired to a user), everything else auto-applies to every HM user.

## Worked example: a user profile (profile-netsa)

Here is the real profile, from
`flake-parts/homeModules/profiles/netsa.nix`, annotated:

```nix
{self, ...}: {
  # Exported as flake.homeModules.profile-netsa (file lives in
  # homeModules/profiles/ — the path contributes nothing to the name).
  flake.homeModules.profile-netsa = {pkgs, ...}: {
    # Inherit the repo's shared HM config: overlays, stateVersion, all
    # non-profile homeModules (devenv.nix, opencode.nix, ...).
    imports = [self.homeModules.default];
    config = {
      # homeSpec options (namespace from flake-parts/homeModules/*;
      # options the repo owns use `enabled`, module-defined and upstream
      # options keep their names)
      homeSpec = {
        xdg.enable = true;
        programs = {
          plasma-manager.enable = true;
          tmux.enable = true;
          bun.enable = true;
          direnv.enable = true;
          docker.enable = true;
          devenv = {
            # devenv CLI (flake package) + 2.x native auto-activation hook
            enabled = true;
            autoActivate.enabled = true;
          };
          # ... (firefox, ghostty, git, go, k9s, ...) — each lives in its
          # own module under flake-parts/homeModules/.
          opencode = {
            enable = true;
            mcp = {
              # Dev-profile opt-ins (off by module default)
              typeui.enable = true;
              # GitHub MCP via the clan-var PAT method; the per-user
              # "github-<user>" generator + sops deployment is derived
              # automatically by nixosModules/git. Provision with:
              #   clan vars generate <machine>   (prompts for the pat)
              github.auth = "pat";
              cloudflare.enable = true;
              cloudflare-docs.enable = true;
              cloudflare-bindings.enable = true;
              cloudflare-builds.enable = true;
              cloudflare-browser.enable = true;
              cloudflare-containers.enable = true;
              mdn.enable = true;
              artifacthub.enable = true;
              # Kubernetes MCP — exits without a kubeconfig, so the module
              # default is off; dev machines provision one.
              kubernetes.enable = true;
              devenv.enable = true;
              varlock-docs.enable = true;
            };
            plugins = {
              opencode-mem.enable = true;
            };
          };
          headroom.enable = true;
        };
      };
      # Plain home-manager options compose directly alongside homeSpec
      home.packages = with pkgs;
        [moscripts kubefetch]
        ++ (with pkgs.unstable; [
          asciinema
          kalker
          lazyssh
          lazyjournal
          freelens-bin
        ]);
    };
  };
}
```

The steps to add the same shape for a new user:

1. **Module file** — create `flake-parts/homeModules/profiles/<name>.nix`
   with the skeleton above (export `flake.homeModules.profile-<name>`,
   import `self.homeModules.default`, set `config`).
2. **Wire the account** — under `users/<name>/default.nix`:
   `home-manager.users.<name> = self.homeModules.profile-<name>;` next
   to the `users.users.<name>` NixOS account settings.
3. **Enable programs selectively** — flip `homeSpec.programs.<x>.enable`
   toggles; every module default stays off unless enabled here (e.g.
   enable the heavy MCPs only on dev profiles).
4. **`git add`** the files, then run the tool loop
   (`nix fmt .` → `statix check .` → `deadnix --fail .` →
   `nix flake check`) — the `nix-style` skill.

## Machine-conditional HM config

A home module can read machine facts through `osConfig` (the NixOS
config the HM user runs under) — the opencode module does this to
generate per-machine instructions from the machine's `facter.json`. HM
runs as a NixOS module here, so `osConfig.networking.hostName` and any
other NixOS option are available lazily; guard with
`lib.mkIf (osConfig != null)` for standalone-eval safety.
