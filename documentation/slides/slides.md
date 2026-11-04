# Home Monorepo

The clan fleet flake: machines on top of the org flakes.

Note: Press `S` for the speaker view, `F` for fullscreen.

---

## What it is

- **flake-parts + clan.lol** — dendritic layout, every `.nix` under `flake-parts/` auto-imported
- Machines as inventory: `nixos`, `kamrui-h1`, `beelink`, `ghost`, `hp-notebook`, `euc-hel-0`
- nixpkgs + overlay from external-systems/pkgs, modules from external-systems/modules
- Secrets in sops / clan vars, never in git

Note: dendritic = the flake is composed from a tree of small modules, not one big configuration.nix.

---

## This site, these slides

- Docs: MkDocs + Material from `org-pkgs.flakeModules.default`
- Slides: reveal.js from the same module, zero npm, zero Python installs

```nix
imports = [inputs.org-pkgs.flakeModules.default];
```

One import → `packages.documentation`, `packages.slides`, the live previews, and this deck embedded at `/slides/`.

--

## Build artifacts

```bash
nix build .#documentation   # the whole site, deck included
nix build .#slides          # just this deck
nix run .#serve-slides      # live preview while editing
```

---

## Everything is a module

- NixOS options under `hostSpec.*`
- home-manager options under `homeSpec.*`
- Clan tags attach hardware/desktop per machine; networking lives in each machine's configuration.nix

---

# Questions?

`github.com/external-systems/home`
