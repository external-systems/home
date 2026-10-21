# ADR 0001: Multi-Host Deployment Strategy via FlakeHub Hub and Clan

- **Status:** Accepted
- **Date:** 2026-08-14
- **Deciders:** Andrew Thomas Lee (@andrewthomaslee)
- **Technical Story:** Declarative multi-host configuration management for heterogeneous machines using FlakeHub, Clan.lol, and a pull-based deployment paradigm in an open-source monorepo.

> **2026-10-21 update — partially superseded:** the FlakeHub and CI
> pillars are historical. FlakeHub publishing (the `apply-*` packages)
> and all GitHub Actions workflows/self-hosted runners have been removed;
> deployments are local (`nixos-rebuild --flake <repo>#<host>`) and CI is
> pending re-implementation as ARC (Actions Runner Controller). The clan
> inventory/vars and tiered-networking pillars still stand.

---

## Context and Problem Statement

Managing multiple heterogeneous physical and virtual machines (`nixos` workstation, `ghost` compute/gaming node, `hp-notebook` laptop, and `nixos-installer` ISO) across different physical locations presents significant challenges:

1. **Open-Source vs. Private State**: The infrastructure definitions must remain fully open-source and publicly inspectable without leaking cryptographic secrets or credentials.
2. **Push Pipeline Brittleness**: Traditional push-based deployment tools (e.g., `nixos-rebuild switch --target-host`, Colmena, deploy-rs) require the operator's machine to maintain long-lived, high-bandwidth SSH sessions to all endpoints, which frequently breaks on laptops, roaming nodes, or constrained remote links.
3. **Ecosystem & Package Fragmentation**: Reusable CLI tools, utility scripts (e.g., `vcluster`, `hcloud-ip`, `longhornctl`), and configuration modules need a single source of truth that other flakes and projects can consume.

How do we build a deterministic, fully reproducible, open-source multi-host management and deployment architecture that guarantees complete declarative control while supporting heterogeneous, remote machines?

---

## Decision Drivers

- **Full Open-Source Transparency**: Codebase and host configurations must be public and published on FlakeHub.
- **Strict "All Builds Lead to Nix" Mandate**: All tools, packages, apps, and machine configurations must be packaged as Nix flakes to prevent environment drift.
- **Resilient Remote Deployments**: Deployments must not fail or leave nodes in inconsistent states due to dropped SSH connections.
- **Clear Secret Decoupling**: Separation of public Nix expressions from encrypted secrets via SOPS / Clan vars.
- **Composable Machine Roles**: Rapid composition of hardware drivers, desktop environments, network configurations, and user profiles across nodes.

---

## Considered Options

1. **Option 1: Traditional Push-Based Rebuild (`nixos-rebuild` / Colmena / deploy-rs)**
   - *Pros:* Familiar workflow, immediate feedback on target host.
   - *Cons:* Brittle on roaming laptops (`hp-notebook`) or high-latency remote machines; requires local evaluation and large closure uploads over user uplinks.
2. **Option 2: Pull-Based FlakeHub Hub with Clan.lol (Selected)**
   - *Pros:* Target nodes pull verified closures directly from FlakeHub; CI pre-builds and checks all machine toplevel closures; secrets are managed via SOPS / Clan vars; repo acts as a centralized FlakeHub hub for shared packages.
   - *Cons:* Requires publishing/pushing to FlakeHub; all helper utilities must be wrapped as Nix packages.
3. **Option 3: Dedicated GitOps Agent on Nodes (e.g., NixOS Auto-Upgrade Service)**
   - *Pros:* Fully automated background updates.
   - *Cons:* Less operator control over when reboots and risky system service restarts occur; difficult to orchestrate manual testing.

---

## Decision Outcome

We decided on **Option 2: A Pull-Based FlakeHub Architecture with Clan.lol Tagged Inventory**.

### Core Pillars

1. **The "Hub Flake" Model**:
   - This repository (`home`) serves as the central hub in a multi-flake ecosystem.
   - It exports machine configurations, reusable NixOS/Home Manager modules, devshells, and standalone utility packages (`vcluster`, `tfctl`, `longhornctl`, `apply-*`) that downstream flakes and machines consume.

2. **Pull-Based Closures via FlakeHub**:
   - Target machines pull their system closures directly from FlakeHub using the Determinate Nix CLI (`fh apply nixos "https://flakehub.com/f/andrewthomaslee/home/*" <action>`).
   - GitHub Actions CI builds and verifies all `nixosConfigurations.<host>.config.system.build.toplevel` closures before release.

3. **Decoupled Secret Distribution**:
   - Secrets are encrypted at rest with SOPS / Clan vars (`vars/` directory) using age encryption keys.
   - Secret decryption keys are provisioned to machines out-of-band or uploaded via `clan vars upload`, ensuring zero plaintext leaks in public store paths or Git history.

4. **Tiered Network Routing Priority**:
   - Host addressing and deployment traffic strictly follow a three-tier fallback:
     1. **Tailscale Mesh** (Primary: encrypted overlay, NAT traversal, stable deterministic hostnames regardless of whether a machine is on home WiFi or roaming)
     2. **Public Internet / Cloudflare Tunnels** (Secondary: authenticated ingress for exposed web endpoints and proxies)
     3. **Local LAN** (Tertiary: fallback direct local subnet IP addressing)

5. **Clan Tag-Driven Inventory**:
   - We leverage **Clan.lol** (a declarative management framework for NixOS flakes, secret management, and distributed machine configurations).
   - Host definitions in `inventory.nix` use tags (`pc`, `intel`, `lan`, `wan`, `dev`, `netsa`, `wife`, `iso`) to dynamically attach system modules, user accounts, and hardware drivers without boilerplate duplication across machine files.

---

### Positive Consequences

- **Rock-Solid Deployment Reliability**: Remote nodes pull closures directly from binary caches / FlakeHub, avoiding aborted deployments midway through closure transfers.
- **Safe Remote Reboots**: The `apply-and-reboot` utility introduces a delayed reboot sequence (`sleep 10 && systemctl reboot`), allowing active SSH, Terraform, or CLI management sessions to exit cleanly before the kernel reboots.
- **Unified Tooling**: Everything is built and distributed via Nix flakes, guaranteeing 100% reproducible developer shells and runtime environments across all workstations.
- **Safe Rollback Strategy**: Full NixOS GRUB bootloader rollback capability is preserved on all target systems.

### Negative Consequences / Trade-offs

- **Strict Flake Dependency**: Every new script or tool must be wrapped in a Nix expression and exported through the flake.
- **FlakeHub Publication Latency**: Release workflows must run through CI and FlakeHub before pull-based updates can be fetched by nodes on the latest release tag.
- **Remote Out-of-Band Dependency**: In the event of a severe kernel or networking misconfiguration preventing boot, GRUB rollback requires console access or physical intervention.

---

## Architecture & Implementation Details

### FlakeHub Package Wrappers (`flake-parts/packages/apply.nix`)

The repository exports atomic deployment packages wrapping the Determinate Nix CLI (`fh`):

| Package | Action Executed | Purpose |
|---|---|---|
| `apply-now` | `fh apply nixos ... switch` | Immediately activate the new generation on the running host. |
| `apply-to-boot` | `fh apply nixos ... boot` | Set the new configuration as the default for the next reboot without switching immediately. |
| `apply-and-reboot` | `fh apply nixos ... boot && sleep 10 && systemctl reboot` | Applies to bootloader and cleanly terminates remote SSH/Terraform sessions before rebooting. |
| `apply-test` | `fh apply nixos ... test` | Test configuration in the current session without updating bootloader entries. |
| `apply-dry-activate` | `fh apply nixos ... dry-activate` | Dry-run activation to verify systemd service transitions and file links. |

---

## Operational Playbook

### 1. Validating Changes Locally
```bash
# Evaluate and verify the flake
nix flake check

# Build documentation locally
nix build .#documentation

# Build a specific machine's system closure
nix build .#nixosConfigurations.ghost.config.system.build.toplevel
```

### 2. Triggering Node Deployment
On target machines (or via remote execution over Tailscale):
```bash
# Pull and switch directly from FlakeHub (no local repo checkout required)
nix run "https://flakehub.com/f/andrewthomaslee/home/*#apply-now" -- home

# Or using the installed package locally:
apply-now home

# For kernel / driver updates requiring a clean reboot:
apply-and-reboot home
```

### 3. Managing Secrets
```bash
# Upload / sync secrets to target machine via Clan
clan vars upload ghost
```

### 4. Bootstrapping New Nodes
1. Boot target hardware using the `nixos-installer` ISO.
2. Partition disk via Disko (`machines/<hostname>/disko.nix`).
3. Provision the host age key and initialize Clan variables via `clan vars upload <hostname>`.
4. Deploy the initial system closure from FlakeHub using `apply-and-reboot home`.
