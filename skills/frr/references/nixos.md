# FRR on NixOS — the `services.frr` module

Verified against `nixos/modules/services/networking/frr.nix` @
nixos-unstable (2026-10-24, FRR 10.7.1). Source of truth is the module
source — re-read it when nixpkgs moves.

## What the module generates

`services.frr.config` (type `lines`) is wrapped into one integrated
vtysh config installed as `/etc/frr/frr.conf`:

```text
! FRR configuration
!
hostname <networking.hostName>
log syslog
service password-encryption
service integrated-vtysh-config
!
<services.frr.config verbatim>
!
end
```

Implications:

- Do **not** repeat `hostname`, `log syslog`, or
  `service integrated-vtysh-config` inside `config` — the wrapper
  already emits them and duplicates fight the reload diff.
- Add `frr defaults datacenter` (or `traditional`) as the **first line**
  of `config` when you want datacenter profile defaults (BGP timers 3/9,
  `bgp log-neighbor-changes` on). Profile defaults apply to objects
  created after the line, so it must precede everything else.

Also generated:

- `/etc/frr/vtysh.conf` — exactly `service integrated-vtysh-config`
  (system-wide vtysh always on).
- `/etc/frr/daemons` — Debian-style daemon manifest: `bgpd=yes` per
  enabled daemon, `vtysh_enable=yes`, and
  `<daemon>_options="-A 127.0.0.1 ..."` from `options`/`extraOptions`.

`services.frr.configFile` (path) replaces the generated `frr.conf`
entirely — point it at a flake-tracked file when templating per-host
configs outside Nix.

## Systemd model: one unit, and what reload really does

- ONE unit: `frr.service`, running `frr/libexec/frr/frrinit.sh start`
  (Type=forking, watchfrr as supervisor, Restart=always,
  LimitNOFILE = `services.frr.openFilesLimit`, default **1024** —
  raise it for large BGP meshes).
- `watchfrr`, `zebra`, `mgmtd`, `staticd` **always** run; the
  `services.frr.<daemon>.enable` set adds to them.
- The unit has `reloadIfChanged` with `restartTriggers = [configFile
  daemonList]`: a nixos-rebuild that changes the config or the daemon
  list fires `frrinit.sh reload`, which runs
  `frr-reload.py --reload ... /etc/frr/frr.conf` — a diff-based in-place
  apply that keeps established sessions.
- **Trap: changing the daemon set only reloads.** `frrinit.sh reload`
  does not start a newly enabled daemon. After adding e.g. `bfdd.enable
  = true`, run `systemctl restart frr` (drops sessions briefly — see
  graceful shutdown in [bgp.md](bgp.md)) or schedule it with the next
  reboot. Config-only edits reload cleanly.

## Enabling daemons and daemon flags

```nix
services.frr = {
  bgpd.enable = true;
  bfdd.enable = true;                 # needs the restart noted above
  bgpd.options = [ "-A 127.0.0.1" ];  # default: VTY on loopback only
  bgpd.extraOptions = [ "-e 32" ];    # e.g. cap ECMP paths at 32
};
```

- Every daemon takes `.options` (replaces the module default) and
  `.extraOptions` (appended). Defaults like `bgpd_options="-A
  127.0.0.1"` keep the VTY off the network — good; manage via `vtysh`.
- Renames to know: the old `services.frr.bgp.enable` names became
  `services.frr.bgpd.enable` (same for `ospf→ospfd`, `bfd→bfdd`, ...).
  `zebra`/`staticd`/`mgmtd` have no enable option — always on.
- Removed on purpose: per-daemon `config`/`configFile`/
  `vtyListenAddress`/`vtyListenPort`. FRR switched to
  integrated-vtysh-config; everything goes in the one
  `services.frr.config`.

## vtysh access

- `vtysh` is on PATH (`environment.systemPackages = [pkgs.frr]`).
- Root runs it directly; non-root users must be in the `frrvty` group:
  `users.users.<name>.extraGroups = [ "frrvty" ];`
- Scripting pattern (used throughout the FRR docs):
  `vtysh -c 'show bgp ipv4 unicast summary' -c 'show ip route'`.
  For machines, add `terminal length 0` first or pipe through `| include`.

## Firewall

The module opens **nothing**:

- eBGP: `networking.firewall.allowedTCPPorts = [ 179 ];`
- BFD: UDP 3784 (+4784 for multihop) when `bfdd` is enabled.
- WireGuard transport ports are separate (`networking.wireguard` /
  wg-quick / nftables).

## Files, users, permissions

- Daemons run as user/group `frr`; FRR-written files are masked 0640.
- NixOS `/etc/frr/*` are symlinks into the store (world-readable). FRR
  accepts this; don't `chmod` the symlinks — use `configFile` with a
  properly owned path if policy demands stricter perms.
- `write memory` from vtysh rewrites `/etc/frr/frr.conf` through
  watchfrr — on NixOS that file is a store symlink, so **treat
  `write memory` as a no-op trap** (it either fails or your next
  rebuild overwrites it). The NixOS way: edit `services.frr.config`,
  rebuild, reload. Use `write terminal`/`show running-config` read-only.

## Per-node templating

For a fleet of nodes each with its own ASN/addresses (the node-local
FRR pattern in [cilium.md](cilium.md)), render `config` with
`lib.replaceStrings`, `pkgs.substituteAll`, or generate one
`configFile` per host from the flake — the repo's
`lib.custom.relativeToRoot` can point at per-machine files.

## Package facts (FRR 10.7.1 on nixos-unstable)

All protocol daemons default-on (`bgpdSupport`, `bfddSupport`, ...),
`numMultipath = 64`, `grpcSupport = false` (experimental),
`snmpSupport`/`rpkiSupport` on, `--enable-config-rollbacks`,
`passthru.tests.frr` = a NixOS VM test you can run with
`nix build nixpkgs#nixosTests.frr`. Verify exact default flags in
`pkgs/by-name/fr/frr/package.nix` before overriding.

## Working checklist

- [ ] `frr.service` active: `systemctl status frr`
- [ ] `vtysh -c 'show version'` shows the expected FRR
- [ ] `vtysh -c 'show running-config'` contains your block (proves
      `vtysh -b` applied it)
- [ ] Sessions up: `vtysh -c 'show bgp summary'` (PfxRcd = number)
- [ ] Firewall: `tcpdump -ni any port 179` during a peer bounce
