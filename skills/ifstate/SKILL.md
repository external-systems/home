---
name: ifstate
description: "IfState 2.5.1 on NixOS: declarative netlink configuration for physical and virtual interfaces, addresses, routes, rules, netns, WireGuard, VXLAN/EVPN, FRR/Cilium integration, live updates, and debugging. Use this skill whenever the user mentions ifstate, replacing systemd-networkd or NixOS netdev configuration, declarative router or fleet networking, no-reboot network changes, WireGuard/netns/VRF/VXLAN configuration, or IfState integration with clan-core, FRR, BGP, Cilium, or NixOS VM hosts."
---

# IfState on NixOS

IfState converges the Linux network stack to one declarative configuration through netlink. It owns links, addresses, permanent neighbours/FDB entries, declared routes/rules, sysctls, traffic control, and WireGuard state; it is not a routing daemon or a continuously running network manager. Use it as the static base under FRR, keepalived, Cilium, or virtual-machine networking.

## Version and evidence

This skill targets **IfState 2.5.1**, upstream tag commit [`9ac7caaedb55e853347c701197eccb7a245d4c07`](https://codeberg.org/routerkit/ifstate/src/commit/9ac7caaedb55e853347c701197eccb7a245d4c07). Do not assume `pkgs.ifstate` has that version: nixpkgs may lag. Check `config.networking.ifstate.package.version` and use the tested override in [references/nixos.md](references/nixos.md) when necessary.

At the 2.5.1 tag, `ifstatecli --version` incorrectly prints `2.5.0` because the embedded runtime string was not bumped. The package metadata and source tag are authoritative for detecting the override; do not “fix” this by treating the host as a 2.5.0 installation. [Upstream evidence](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/__init__.py#L77)

The operational claims in this skill are grounded in the pinned source, nixpkgs source, and ephemeral NixOS VM runs. See `references/research/` for the evidence reports and [references/research/vm-verification.md](references/research/vm-verification.md) for executed assertions.

## Choose the reference

| Task | Read |
|---|---|
| Enable on NixOS, pin 2.5.1, understand rebuild/initrd behavior, handle secrets or clan integration | [references/nixos.md](references/nixos.md) |
| Translate YAML to Nix; configure NICs, bonds, bridges, VLANs, routes, rules, netns, DHCP hooks, or WireGuard | [references/configuration.md](references/configuration.md) |
| Integrate FRR/BGP, EVPN-VXLAN, Cilium native routing, spine-leaf fabrics, redundant underlays, or VM hosts | [references/routing.md](references/routing.md) |
| Preview, apply, maintain, troubleshoot, or recover a host | [references/operations.md](references/operations.md) |
| Verify a claim against source or an executed VM test | `references/research/` |

## The convergence contract

`ifstatecli apply` is a full reconcile, not an incremental “create these objects” command. Undeclared virtual interfaces are deleted; undeclared physical interfaces are shut down. Built-in defaults also clear unconfigured addresses, alternate names, FDB entries, neighbours, and TC state, and detach links from masters. Built-in ignores protect common dynamic objects, but not every VM, Cilium, or appliance interface.

This is why a dry run is the first operational step, not an optional convenience:

```bash
ifstatecli validate       # parse and schema-check only
ifstatecli check          # dry-run the same reconciliation algorithm as apply
ifstatecli showall        # include built-in defaults and ignore rules
```

Read every proposed deletion and every unexpected physical-link change before applying. Extend `parameters.ignore` for objects owned by other software; do not weaken cleanup globally just to hide one ownership bug. [Defaults and ignores](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/defaults.md) · [Ignore reference](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/ignore.md)

## NixOS quick start

The `settings` attrset is the upstream YAML tree with the same keys. This example identifies a physical NIC by its permanent MAC, adds a dummy loopback, and installs a default route:

```nix
{pkgs, ...}: {
  networking = {
    useDHCP = false;
    ifstate = {
      enable = true;
      package = pkgs.ifstate; # ensure this evaluates to 2.5.1
      settings = {
        interfaces = {
          outside = {
            addresses = [
              "192.0.2.10/24"
              "2001:db8:dead:c0de::10/64"
            ];
            link = {
              kind = "physical";
              state = "up";
            };
            identify.perm_address = "8c:16:45:dc:b1:ad";
          };
          loop0 = {
            addresses = ["10.255.0.1/32"];
            link = {
              kind = "dummy";
              state = "up";
            };
          };
        };
        routing.routes = [
          {
            to = "0.0.0.0/0";
            via = "192.0.2.1";
          }
        ];
      };
    };
  };
}
```

Generate real identification candidates on the host with `ifstatecli identify`. Prefer permanent MAC or PCI/bus identity over an enumeration-dependent kernel name for physical NICs.

NixOS validates the rendered YAML against the package's JSON schema during the build. A bad key normally fails before deployment. Runtime `!include` targets are different: their existence and readability are checked when IfState parses the config on the host.

Apply through the normal NixOS activation flow, or deliberately reapply the current generation:

```bash
sudo systemctl start ifstate.service
journalctl -u ifstate.service -b --no-pager
```

A successful oneshot becomes `inactive (dead)`; judge success from the journal and resulting kernel state, not from a persistent `active` status. Stage-2 settings changes apply live during `nixos-rebuild switch` or `test`; they do not normally require reboot. Initrd changes do.

## Ownership boundaries

Give each kernel object one writer:

- **IfState:** physical and virtual links, static addresses, static routes/rules you declare, sysctls, and WireGuard peers.
- **FRR:** BGP/OSPF/etc. routes and EVPN control-plane state. Zebra installs them in the kernel; bgpd computes routes but does not configure interfaces.
- **Cilium:** pod datapath and its own interfaces. IfState supplies host networking; FRR or the underlay supplies off-node pod reachability.
- **VM/container runtimes:** tap and runtime-created interfaces. Declare the durable bridge in IfState and ignore the dynamic ports.
- **keepalived:** VRRP state transitions. Use IfState's VRRP integration for objects explicitly marked `vrrp`.

IfState's built-in route ignores preserve FRR BGP, OSPF, ISIS, RIP, zebra, and related protocol routes. They do **not** preserve FRR `staticd` routes (protocol 196) or foreign static routes (protocol 4); declare those routes in IfState or add explicit route ignores. Do not add protocol 3 to the ignore list: that is IfState's own default route protocol. [Routing integration](references/routing.md)

## Safe change loop

1. Establish one owner per interface, address, route, rule, and namespace. Disable NetworkManager and legacy DHCP ownership; also disable any systemd-networkd ownership of the same links—the module does not assert that conflict for you.
2. Pin the package and build the NixOS configuration so schema validation runs before activation.
3. Inspect `/etc/ifstate/ifstate.yaml`, then run `ifstatecli validate` and `ifstatecli -v check` on the target. Confirm no unexpected cleanup.
4. Activate during a maintenance window with out-of-band access for routers or remote hosts. IfState may briefly set links down while changing them, and an SSH drop does not interrupt an in-progress apply.
5. Verify links, addresses, routes, rules, WireGuard handshakes, and routing-daemon RIB/FIB state. Re-run `ifstatecli check`; unexpected remaining diffs mean convergence failed or another writer is fighting IfState.
6. Keep the last known-good NixOS generation and console access. IfState does not provide transactional rollback across the whole network stack; rolling back the generation and reapplying is the recovery mechanism.

## High-value gotchas

- **Secrets:** never put a private key in `settings` or a `pkgs.writeText` path. Use `!include /run/secrets/...` (or another runtime path) with sops-nix, clan vars, or an equivalent secret store. Store-referenced includes are world-readable and are unsuitable for keys.
- **Other managers:** NetworkManager and `networking.useDHCP` have explicit assertions; systemd-networkd does not. Use IfState hooks for DHCP rather than running a second global DHCP owner.
- **Partial failure:** a nonexistent physical NIC or failed hook can leave a partial result while other objects are configured. Always inspect the journal and post-apply state.
- **Udev race:** the NixOS unit waits for udev with a best-effort `udevadm settle`; this is not a device-readiness guarantee. Identify physical devices stably and retry after inspecting the failure.
- **WireGuard:** peers are keyed by public key. AllowedIPs select the peer cryptographically; avoid overlapping AllowedIPs on one interface. `wireguard.table` creates IfState-owned routes from AllowedIPs, so do not treat them as FRR routes.
- **EVPN:** use the traditional per-VNI bridge+VXLAN model with IfState 2.5.1. Its schema cannot express the single-VXLAN-device `external`/`vnifilter`/`tunnel_info` model.
- **Version upgrades:** read the pinned changelog. In particular, 2.4 introduced reproducible default MAC addresses and 2.5 moved to Python ≥3.11 and the `uv_build` backend. [Changelog](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/CHANGELOG.md)

## Primary references

- [IfState 2.5 documentation](https://ifstate.net/2.5/)
- [2.5.1 source and schema](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1)
- [CLI reference](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/cli.md)
- [NixOS module in current nixpkgs](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ifstate.nix)
- [NixOS VM tests](https://github.com/NixOS/nixpkgs/tree/nixos-unstable/nixos/tests/ifstate)
- [FRR 10.7 EVPN documentation](https://docs.frrouting.org/en/stable-10.7/evpn.html)
