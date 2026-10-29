# Welcome to Andrew's Home Flake

<div align="center">
  <img src="https://blog.andrewlee.fun/favicon.ico" width="400">
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


<div align="center">

## Features

### ☸️ **Kubernetes**
`K3s` • `Rancher` • `Cloudflare WARP`

### ❄️ **NixOS**
`Clan.lol` • `flake-parts` • `dendritic` • `home-manager` • `Tailscale` • `OpenShell` • `Modded Minecraft Server` • `KDE` • `Wayland`

</div>



## Project layout

    flake.nix       # Flake that controls the project
    flake.lock      # Flake's lock file
    inventory.nix   # Clan.lol Inventory of all NixOS machines and Services
    .env.schema     # Varlock schema

    machines/       # NixOS Machines
    clanServices/   # Clan.lol Services
    lib/            # Custom functions accessible via `lib.custom`
    overlays/       # Overlays for Nixpkgs. Adds `pkgs.unstable`

    flake-parts/        # Top-level Flake Part files
                        # Auto-imported via import-tree: every .nix file
                        # here loads, there is no import list to update
        default.nix     # Default flake-parts configuration
        checks.nix      # checks.lint (alejandra/statix/deadnix) + devenv-lock-drift
        tests.nix       # Auto-discovers vm-tests/ into sm/md/lg variants
        devShells.nix   # Development Shells
        apps/           # Applications `nix run .#<app>`
        packages/       # Packages `nix build .#<package>`
        ociImages/      # OCI images (code-agent-image)
        homeModules/    # Home-manager Modules (incl. profiles/)
        nixosModules/   # NixOS Modules

    devenv/             # Shared devenv module (both `devenv shell` and `nix develop`)
    devenv.nix          # devenv CLI entry point
    devenv.yaml         # devenv project settings (pins mirror flake.lock)
    devenv.lock         # devenv lockfile (pins mirror flake.lock)

    documentation/      # MkDocs
        mkdocs.yml      # MkDocs configuration
        docs/           # Documentation source

    .devcontainer/          # Devcontainer

    sops/                   # Encrypted Secrets
    vars/                   # Clan.lol implementaion of SOPS

## Flake Outputs

Flake outputs as of the last refresh — regenerate after output changes with
`nix run .#update-flake-show` (writes both this file and `README.md`).

```console
$ nix flake show
├───allSystems: unknown
├───apps
│   └───x86_64-linux
│       ├───fetch-kubeconfig: app: no description
│       ├───get-keys: app: no description
│       ├───load-code-agent-image: app: no description
│       ├───package-skills: app: Package each skill directory into its own ZIP archive
│       ├───serve-slides: app: Serve slides/ with reveal.js on localhost for live editing.
│       ├───update-flake-show: app: no description
│       ├───vm-test: app: no description
│       └───watch-documentation: app: Run mkdocs in watch mode over your documentation folder. Automatically rebuilds your docs on changes.
├───checks
│   └───x86_64-linux
│       ├───code-agent-policy: derivation 'check-code-agent-policy'
│       ├───devenv-lock-drift: derivation 'devenv-lock-drift'
│       ├───lint: derivation 'lint'
│       ├───skill-frontmatter: derivation 'skill-frontmatter'
│       └───vm-test-resources: derivation 'vm-test-resources'
├───clan: unknown
├───clanInternals: unknown
├───darwinConfigurations: unknown
├───darwinModules: unknown
├───debug: unknown
├───devShells
│   └───x86_64-linux
│       └───default: development environment 'devenv-shell'
├───flakeModules: unknown
├───formatter
│   └───x86_64-linux: package 'alejandra-4.0.0'
├───homeConfigurations: unknown
├───homeModules: unknown
├───legacyPackages
│   └───x86_64-linux omitted (use '--legacy' to show)
├───lib: unknown
├───nixosConfigurations
│   ├───beelink: NixOS configuration
│   ├───ghost: NixOS configuration
│   ├───hp-notebook: NixOS configuration
│   ├───kamrui-h1: NixOS configuration
│   ├───nixos: NixOS configuration
│   └───nixos-installer: NixOS configuration
├───nixosModules
│   ├───amd: NixOS module
│   ├───bluetooth: NixOS module
│   ├───clan: NixOS module
│   ├───clan-machine-beelink: NixOS module
│   ├───clan-machine-ghost: NixOS module
│   ├───clan-machine-hp-notebook: NixOS module
│   ├───clan-machine-kamrui-h1: NixOS module
│   ├───clan-machine-nixos: NixOS module
│   ├───clan-machine-nixos-installer: NixOS module
│   ├───default: NixOS module
│   ├───docker: NixOS module
│   ├───flatpak: NixOS module
│   ├───git: NixOS module
│   ├───intel: NixOS module
│   ├───jovian: NixOS module
│   ├───kde: NixOS module
│   ├───lan: NixOS module
│   ├───motd: NixOS module
│   ├───nix: NixOS module
│   ├───nix-ld: NixOS module
│   ├───ollama: NixOS module
│   ├───openshell-gateway: NixOS module
│   ├───openssh: NixOS module
│   ├───rancher: NixOS module
│   ├───sound: NixOS module
│   ├───ssh: NixOS module
│   ├───storagebox: NixOS module
│   ├───tailscale: NixOS module
│   ├───virtualization: NixOS module
│   ├───wan: NixOS module
│   ├───warp: NixOS module
│   ├───wayland: NixOS module
│   └───whisper-dictation: NixOS module
├───overlays
│   └───default: Nixpkgs overlay
├───packages
│   └───x86_64-linux
│       ├───artifacthub-mcp: package 'artifacthub-mcp-1.1.1'
│       ├───code-agent-env: package 'code-agent-env'
│       ├───code-agent-image: package 'image-code-agent.json'
│       ├───code-agent-policy: package 'code-agent-policy'
│       ├───code-sandbox: package 'code-sandbox'
│       ├───container-processes: package 'image-processes.json'
│       ├───container-shell: package 'image-shell.json'
│       ├───devShell: package 'devenv-shell'
│       ├───devenv-test: package 'devenv-test'
│       ├───devenv-up: package 'devenv-up'
│       ├───documentation: package 'mkdocs-flake-documentation'
│       ├───get-keys: package 'get-keys'
│       ├───github-agent-profile: package 'github-agent-profile'
│       ├───hcloud-ip: package 'hcloud-ip-v0.0.1'
│       ├───headroom: package 'headroom-ai-0.40.0'
│       ├───headroom-slim: package 'headroom-ai-0.40.0'
│       ├───kubernetes-mcp-server: package 'kubernetes-mcp-server-0.0.66'
│       ├───longhornctl: package 'longhornctl-v1.12.0'
│       ├───openshell: package 'openshell-0.1.2'
│       ├───openshell-driver-vm: package 'openshell-driver-vm-0.1.2'
│       ├───openshell-gateway: package 'openshell-gateway-0.1.2'
│       ├───slides: package 'slides'
│       └───tfctl: package 'tfctl-0.16.4'
└───templates
    └───self: template: This Flake
```