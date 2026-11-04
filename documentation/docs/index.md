# Welcome to Andrew's Home Flake

<div align="center">
  <img src="assets/brand/andrewthomaslee-transparent-logo.png" alt="Andrew's Logo" width="400">
</div>

<p align="center">
  <a href="https://github.com/external-systems/home/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/external-systems/home/ci.yml?branch=main&amp;label=ci&amp;logo=github" alt="ci"></a>
  <a href="https://github.com/external-systems/home/releases/latest"><img src="https://img.shields.io/github/v/release/external-systems/home?label=release&amp;color=d97757" alt="release"></a>
  <a href="https://home.external.systems/"><img src="https://img.shields.io/website?url=https%3A%2F%2Fhome.external.systems%2F&amp;label=docs&amp;up_message=online&amp;down_message=offline" alt="docs"></a>
  <a href="https://github.com/external-systems/home/blob/main/LICENSE"><img src="https://img.shields.io/github/license/external-systems/home" alt="license"></a>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/built_with-Nix-5277C3?logo=nixos&amp;logoColor=white" alt="built with Nix"></a>
</p>


<h3 align="center">
  <strong>🏠 Home Repository for my <u>NixOS Machines</u>❄️ and <u>Kubernetes</u>☸️</strong>
</h3>


## Features

### ❄️ **NixOS**
`Clan.lol` • `flake-parts` • `home-manager` • `Tailscale` • `KDE` • `Wayland` • remote builds

This repo is only the fleet: machines, the clan inventory and home's own clan
services. Everything else comes from the org flakes:

| Flake | Provides |
| ----- | -------- |
| [external-systems/pkgs](https://github.com/external-systems/pkgs) | nixpkgs, flake-parts, import-tree, the overlay (headroom, kimi-code, ...) and the dev tooling |
| [external-systems/modules](https://github.com/external-systems/modules) | NixOS (`hostSpec.*`) and home-manager (`homeSpec.*`) modules |
| [external-systems/skills](https://github.com/external-systems/skills) | agent skills, through modules |
| external-systems/secrets (private) | addresses, interfaces, deploy targets, the clan domain and Storage Box logins |

## Machines

| Machine       | Role                                                        |
| ------------- | ----------------------------------------------------------- |
| `nixos`       | Intel desktop — dev + NVIDIA gaming (jovian)                |
| `kamrui-h1`   | AMD dev + gaming desktop — KDE/Wayland (jovian), deployed   |
| `beelink`     | Shared AMD desktop, deployed                                |
| `ghost`       | Intel desktop — dev                                         |
| `hp-notebook` | Wife's Intel laptop                                         |
| `euc-hel-0`   | Hetzner Robot server — remote builder and CI build box      |

See [Fleet](fleet/index.md) for networking and
[Remote builder](fleet/remote-builder.md) for euc-hel-0.

## Project layout

    flake.nix        # inputs (org-pkgs, clan-core, modules, secrets); org-pkgs.flakeModules.dev
    inventory.nix    # clan inventory: machines, tags, service instances
    machines/        # per-machine configuration.nix, disko.nix, facter.json
    clanServices/    # home's clan services: machine-type, tags (remote-builder: external-systems/clanServices)
    users/           # user accounts (home-manager profiles in flake-parts/)
    flake-parts/     # import-tree: clan wiring, nixpkgs, the networking shim, profiles, docs settings
    devenv.yaml      # the org devenv shell (devenv.nix: home's additions)
    documentation/   # this site and the slides
    sops/ vars/      # clan vars (sops-encrypted)
