---
name: frr
description: "FRRouting (FRR) BGP on NixOS: configure, run, and debug FRR with the services.frr module, bgpd, vtysh, and frr-reload. Load for any FRR or BGP task: BGP peering and sessions, advertising or filtering routes (route-maps, prefix-lists, communities), BGP unnumbered and RFC 8950 IPv6 next-hops, BFD, ECMP, graceful restart, EVPN-VXLAN overlays (L2 stretch, L3 EVPN, IRB, anycast gateways), Cilium BGP control plane integration (node-local FRR fronting, TOR peering, auto-discovery), WireGuard site-to-site BGP meshes, or troubleshooting stuck sessions and missing routes with show bgp summary and debug bgp. Use this skill even when the user does not name FRR but asks about BGP routing on a NixOS host, a flat layer-3 network for Kubernetes, or EVPN on Linux hosts."
---

# frr

[FRRouting](https://frrouting.org) is a suite of cooperating routing
daemons, not a single program: each protocol runs in its own daemon
(`bgpd`, `ospfd`, ...), protocol daemons exchange routes with `zebra`
(the kernel/dataplane broker), and `vtysh` is one CLI frontend that
proxies commands to all daemons over Unix sockets and implements the
integrated config model — a single `/etc/frr/frr.conf` for everything.
This skill covers running FRR on **NixOS** with BGP as the focus
protocol, most often fronting **Cilium's BGP control plane** to build a
flat L3 network for Kubernetes (pod CIDRs + service VIPs advertised
natively between sites).

## Version rule

- **FRR 10.7.1 is the verified baseline** (nixpkgs `nixos-unstable` @
  2026-10-24; multipath 64-way, gRPC off, all protocol daemons on).
  Confirm on the host with `show version` — defaults shift between
  releases (see [references/bgp.md](references/bgp.md) §Version-dependent
  defaults).
- Docs are versioned: use `https://docs.frrouting.org/en/frr-10.7/...`
  for this baseline, `.../en/latest/...` for development.
- Cilium integration facts are pinned to **Cilium v1.20** (this repo's
  Cilium baseline).

## Choose the reference

| Task | Read this reference |
|---|---|
| `services.frr` on NixOS: generated files, systemd/reload semantics, firewall, vtysh access, per-node templating | [references/nixos.md](references/nixos.md) |
| BGP config language: peers, address families, route-maps/prefix-lists, unnumbered/RFC 8950, ECMP, BFD, graceful restart, inter-site filtering | [references/bgp.md](references/bgp.md) |
| Run and debug: `show bgp summary` triage, RIB-vs-kernel, `debug bgp`, logging, packet dumps, safe reloads | [references/operations.md](references/operations.md) |
| Cilium BGP control plane integration: CRDs, node-local FRR pattern, direct TOR peering, BGP auto-discovery, WireGuard site mesh, end-to-end verification | [references/cilium.md](references/cilium.md) |
| EVPN-VXLAN overlays on NixOS hosts: MAC-VRF/IP-VRF, type-2/3/5 routes, kernel dataplane contract, IRB, anycast gateways, verification | [references/evpn.md](references/evpn.md) |

Source-evidence research files (keep unchanged):
[references/research/frr-docs.md](references/research/frr-docs.md)
(official FRR docs),
[references/research/cilium-nixos-integration.md](references/research/cilium-nixos-integration.md)
(Cilium v1.20 RST, nixpkgs module source, denizaydin lab, bella.network),
[references/research/bfd-autodiscovery.md](references/research/bfd-autodiscovery.md)
(FRR bfd.html, Cilium auto-discovery article, OPNsense WG+BFD thread),
[references/research/evpn-vxlan.md](references/research/evpn-vxlan.md)
(FRR evpn.html + bgp.html EVPN sections, fedepaol/Bernat walkthroughs,
ipspace collection).

## NixOS quick start

```nix
{ services.frr = {
    bgpd.enable = true;
    config = ''
      frr defaults datacenter
      router bgp 65001
       bgp router-id 10.0.0.1
       no bgp default ipv4-unicast
       neighbor 172.31.10.1 remote-as 65002
       neighbor 172.31.10.1 description site-b
       !
       address-family ipv4 unicast
        network 10.10.0.0/16
        neighbor 172.31.10.1 activate
       exit-address-family
      exit
    '';
  };
  networking.firewall.allowedTCPPorts = [ 179 ];
}
```

`services.frr.config` becomes `/etc/frr/frr.conf`; the module wraps it
with `hostname`/`log syslog`/`service integrated-vtysh-config` (do not
repeat those). Deploy with the usual `nixos-rebuild switch`; then verify:

```
vtysh -c 'show bgp summary'    # State/PfxRcd column = number ⇒ session up
```

## Gotchas that bite every setup

- **One integrated config only.** `services.frr.config` (or
  `configFile`) is the whole story; per-daemon config options were
  removed from the NixOS module, and FRR's own per-daemon files are
  deprecated.
- **Reload ≠ restart.** A config edit reloads in place
  (`frr-reload.py --reload`, sessions stay up). Changing the *daemon
  set* (e.g. enabling `bfdd`) needs `systemctl restart frr` — reload
  will not start a newly enabled daemon.
- **The module opens no firewall ports.** eBGP needs TCP 179 inbound,
  BFD needs UDP 3784 (+4784 multihop).
- **`(Policy)` in `show bgp summary`** means `bgp ebgp-requires-policy`
  is discarding routes in that direction — attach a route-map or
  prefix-list (or disable the knob).
- **The `r` flag in `show ip route`** = zebra holds the route but the
  kernel rejected it (classic "BGP sees it, forwarding doesn't"). Cross
  check `ip route`; `systemctl restart frr` clears stale rejections.

## Resilient site-to-site networking

The layer cake every resilient design needs, fastest detection innermost:

- **Keep timers coherent end to end: BFD ≪ BGP hold ≪ GR restart time.**
  A 150 ms BFD profile is wasted against a 90 s Cilium hold timer; set
  detection on *every* participating box, including Cilium PeerConfig
  timers (Cilium has no BFD — its hold/keepalive timers **are** its
  detection). Details: [references/bgp.md](references/bgp.md) §BFD,
  [references/cilium.md](references/cilium.md).
- **BFD echo mode is FRR↔FRR only** (or distributed-BFD offload); to
  heterogeneous peers run async control-packet BFD, and never echo on
  multihop (RFC 5883). `bfd strict` hard-couples BGP bring-up to BFD —
  deliberate choice, damp with `hold-time`.
- **Graceful restart needs `bfd check-control-plane-failure` (C-bit)**
  or a BFD-down during the peer's restart purges the stale routes GR
  was preserving. Both sides must agree: restarter signals via BGP GR,
  helper honors it.
- **ECMP only protects paths it monitors**: one BFD session per ECMP
  member (`maximum-paths` + per-neighbor `bfd`); a member without BFD
  silently reverts to slow hold-time convergence. On listen ranges
  (Cilium auto-discovery), add `maximum-prefix` + inbound route-maps.
- **WireGuard transport is cryptokey routing, not IP routing**:
  overlapping `AllowedIPs` on one listener silently breaks (peer shows
  `allowed ips: (none)`) — one listener per full-table peer, and keep
  explicit per-peer remote subnets as a backstop even when FRR "owns"
  routing. Field proof: OPNsense 3-site HA thread, ~2 pings lost per
  WAN/firewall failure with FRR BGP+BFD ([research note](references/research/bfd-autodiscovery.md)).
- **Verify both sides of every session**: `show bfd peers brief` +
  `show bfd peers counters` + `show bgp summary` together catch
  half-configured pairs (one side with `neighbor … bfd`, the other
  without, converges asymmetrically).

## Core doc URLs

| Topic | URL |
|---|---|
| FRR docs home (latest) | https://docs.frrouting.org/en/latest |
| BGP chapter | https://docs.frrouting.org/en/latest/bgp.html |
| vtysh | https://docs.frrouting.org/en/latest/vtysh.html |
| frr-reload | https://docs.frrouting.org/en/latest/frr-reload.html |
| Filters (prefix/access/as-path lists) | https://docs.frrouting.org/en/latest/filter.html |
| Route-maps | https://docs.frrouting.org/en/latest/routemap.html |
| BFD | https://docs.frrouting.org/en/latest/bfd.html |
| EVPN | https://docs.frrouting.org/en/latest/evpn.html |
| zebra (kernel, ECMP, distance) | https://docs.frrouting.org/en/latest/zebra.html |
| Daemon/service setup | https://docs.frrouting.org/en/latest/setup.html |
| Cilium BGP control plane (v1.20) | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane |
| Cilium BGP auto-discovery writeup | https://medium.com/@simardeep.oberoi/simplifying-network-management-with-ciliums-bgp-auto-discovery-feature-2f340d2225f8 |
| NixOS module source | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/frr.nix |
| nixpkgs package source | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/fr/frr/package.nix |
