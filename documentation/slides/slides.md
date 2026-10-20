# Home Monorepo

One dendritic Nix flake for every machine.

Note: Press `S` for the speaker view, `F` for fullscreen.

---

## What it is

- **flake-parts + clan.lol** — dendritic layout, every `.nix` under `flake-parts/` auto-imported
- Machines as inventory: `nixos`, `kamrui-h1`, `ghost`, `hp-notebook`, `nixos-installer`
- Secrets in sops / clan vars, never in git

Note: dendritic = the flake is composed from a tree of small modules, not one big configuration.nix.

---

## This site, these slides

- Docs: MkDocs + Material via `mkdocs-flake`
- Slides: reveal.js via `inputs.presenting` — zero npm, zero Python installs

```nix
presenting.slides.dir = ./documentation/slides;
```

One line → `packages.slides`, `apps.serve-slides`, and this deck embedded at `/slides/`.

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
- Clan tags attach hardware/desktop/networking per machine

---

# Questions?

`github.com/andrewthomaslee/home`
