# Welcome to Andrew's Home Flake

<div align="center">
  <img src="assets/brand/andrewthomaslee-transparent-logo.png" alt="Andrew's Logo" width="400">
</div>

<p align="center">
  <a href="https://github.com/andrewthomaslee/home/releases"><img src="https://img.shields.io/github/v/release/andrewthomaslee/home?include_prereleases&style=for-the-badge" alt="Latest Release"></a>
  <a href="https://github.com/andrewthomaslee/home/blob/main/LICENSE"><img src="https://img.shields.io/github/license/andrewthomaslee/home?style=for-the-badge&color=blue" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/andrewthomaslee/home"><img src="https://img.shields.io/badge/github-repo-24292e?logo=github&style=for-the-badge" alt="GitHub Repo"></a>
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
| external-systems/secrets (private) | addresses, interfaces and deploy targets |

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

    flake.nix        # inputs (org-pkgs, clan-core, modules, secrets) + the dev partition
    inventory.nix    # clan inventory: machines, tags, service instances
    machines/        # per-machine configuration.nix, disko.nix, facter.json
    clanServices/    # home's clan services: machine-type, tags, remote-builder
    users/           # user accounts (home-manager profiles in flake-parts/)
    flake-parts/     # import-tree: clan wiring, nixpkgs, the networking shim, profiles
    dev/             # dev partition: formatter, checks, docs (own flake.lock)
    devenv.yaml      # the org devenv shell (devenv.nix: home's additions)
    documentation/   # this site and the slides
    sops/ vars/      # clan vars (sops-encrypted)
