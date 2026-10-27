# Routing, fabric, and runtime integration

Use IfState for the kernel-facing static base and a routing daemon for dynamic reachability. The important design rule is **one writer per object**. For deeper BGP, BFD, graceful-restart, and Cilium configuration, use the `frr` and `cilium` skills alongside this one.

## IfState and FRR

IfState explicitly supports leaving route configuration to FRR. FRR learns interface state from netlink but does not create the required Linux interfaces; zebra installs routes in the kernel. [IfState overview](https://ifstate.net/2.5/) · [FRR EVPN interface model](https://docs.frrouting.org/en/stable-10.7/evpn.html)

A clean split is:

| State | Owner |
|---|---|
| Physical NICs, bonds, bridges, VLANs, dummy/loopback addresses | IfState |
| VXLAN/VRF devices and their bridge-port settings | IfState |
| Static default or transfer routes explicitly declared in `routing.routes` | IfState |
| BGP/OSPF/ISIS/RIP learned routes | FRR/zebra |
| EVPN type-2/3/5 control plane, remote MACs, remote VTEPs | FRR/zebra |
| FRR `staticd` routes | FRR, with an explicit IfState ignore; or move them into IfState |

IfState's built-in route ignores include protocols zebra (11), BGP (186), OSPF (188), ISIS (187), RIP (189), and related dynamic-writer protocols. Its own routes default to protocol 3. Two important exceptions are not built-in ignored:

- protocol 196: FRR `staticd` routes;
- protocol 4: foreign static routes, including many routes created outside IfState.

Choose one of these patterns for protocol 196/4 routes; do not leave two writers competing:

```nix
# FRR/other tools own these routes:
parameters.ignore.routes = [
  {proto = 196;}
  {proto = 4;}
];
```

or declare the routes in `networking.ifstate.settings.routing.routes` and remove them from the other writer. Never ignore protocol 3 to make diffs disappear; that disables reconciliation of IfState's own routes. [Built-in route protocols](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/parser/base.py) · [FRR netlink protocol mapping](https://github.com/FRRouting/frr/blob/stable/10.7/zebra/rt_netlink.c)

Verify the boundary after every networking change:

```bash
ifstatecli check
ip -4 route show proto 3       # IfState defaults
ip -4 route show proto bgp     # FRR BGP
ip -4 route show proto zebra   # FRR/zebra
ip -4 route show proto 196     # FRR staticd; check it survived apply
vtysh -c 'show bgp summary' -c 'show ip route'
```

A prefix present in BGP but absent from forwarding is a zebra/kernel problem, not a reason to add a duplicate IfState route. Compare `vtysh -c 'show ip route'` with `ip route`; FRR's `r` flag means the kernel rejected a route zebra tried to install. [FRR zebra documentation](https://docs.frrouting.org/en/stable-10.7/zebra.html)

## WireGuard as an underlay

IfState can create the WireGuard interface, addresses, peers, and optional AllowedIP-derived routes. FRR then peers across that interface and owns the learned routes.

- Give each independent path its own WireGuard interface and BGP/BFD session. ECMP across tunnels means ECMP across interfaces.
- Do not overlap AllowedIPs between peers on one interface. AllowedIPs select the peer's key; they are not ordinary route entries.
- Ensure each interface's AllowedIPs cover every subnet FRR may route through it.
- Use `wireguard.table` only when IfState should own the resulting static routes. For FRR-owned reachability, use transfer addresses and FRR instead.
- Allow the WireGuard UDP port through the firewall and verify both handshakes and allowed IPs.

```bash
wg show wg0 latest-handshakes
wg show wg0 allowed-ips       # '(none)' can indicate shadowing
ip -d link show wg0
ifstatecli check
```

[IfState WireGuard source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/wireguard/__init__.py)

## EVPN-VXLAN

FRR does not create the VXLAN dataplane. IfState must provide:

1. A unique VTEP address, typically `/32` or `/128` on a loopback/dummy interface, reachable through the underlay.
2. Per-VNI bridge and VXLAN devices in the traditional model.
3. VXLAN learning disabled for EVPN-controlled devices.
4. Bridge-port neighbour suppression and learning settings required by the design.
5. Tenant VRFs and L3 SVIs where IRB/type-5 routing is required.

A per-VNI skeleton looks like this:

```nix
interfaces = {
  loop0 = {
    addresses = ["10.255.0.1/32"];
    link = {
      kind = "dummy";
      state = "up";
    };
  };
  br100 = {
    link = {
      kind = "bridge";
      state = "up";
      address = "42:0d:ef:a0:00:01"; # unique per VTEP
      br_stp_state = 0;
    };
  };
  vxlan100 = {
    link = {
      kind = "vxlan";
      state = "up";
      master = "br100";
      vxlan_id = 100;
      vxlan_local = "10.255.0.1";
      vxlan_port = 4789;
      vxlan_learning = false;
    };
    brport = {
      learning = false;
      neigh_suppress = true;
    };
  };
};
```

This is a dataplane skeleton, not a complete EVPN deployment. Configure FRR's `l2vpn evpn` family, `advertise-all-vni`, VNI/VRF mappings, route targets, and any type-5 exports separately. Do not add static remote-VTEP FDB entries when FRR should learn them through EVPN. Allow UDP 4789 between VTEPs. [FRR Linux VXLAN dataplane contract](https://docs.frrouting.org/en/stable-10.7/evpn.html)

**2.5.1 limitation:** the schema does not express the single-VXLAN-device `external`/`vnifilter` model or bridge-VLAN `tunnel_info` mappings. Use the traditional one-VXLAN-device-per-VNI model, or manage that mapping through a deliberately owned out-of-band mechanism. Do not claim an IfState-only SVD configuration. [2.5.1 schema](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/schema/2/ifstate.conf.schema.json)

Verify both planes:

```bash
ip -d link show vxlan100      # learning off, expected VNI/local/port
bridge fdb show dev vxlan100
bridge link show dev vxlan100
vtysh -c 'show bgp l2vpn evpn summary' -c 'show evpn vni'
vtysh -c 'show evpn mac vni 100' -c 'show evpn arp-cache vni 100'
```

Inspect `ifstatecli check` for unexpected FDB deletions on EVPN interfaces. IfState reconciles permanent/NOARP FDB state; if a zebra-created flood entry appears as a diff, stop and establish an explicit `fdb` declaration or ignore rather than repeatedly deleting it.

## Flat L3 versus flat L2 across sites

Prefer routed L3 reachability unless a workload genuinely requires one broadcast domain:

- **Flat L3:** IfState provides site links, WireGuard tunnels, transfer addresses, and loopbacks. FRR advertises host, node, pod, and service prefixes with ECMP/BFD. Failure domains and policy remain routed.
- **Flat L2:** use EVPN MAC-VRFs only for requirements such as MAC mobility or an anycast gateway. IfState provides the per-VNI kernel dataplane; FRR provides EVPN. Expect additional route-target, ARP-suppression, FDB, and MTU failure modes.

Do not stretch L2 merely to avoid configuring BGP. Cilium native routing is an L3 design and does not itself provide EVPN.

## Spine-leaf and redundant underlays

IfState owns the leaf's durable physical/base configuration: identified NICs, optional LACP bonds, VLANs, transfer addresses, and loopbacks. FRR owns per-link eBGP sessions, ECMP, BFD, graceful restart, and route policy.

For dual-homed leaves, use independent uplinks and sessions to each spine. Configure FRR `maximum-paths` and, where AS paths differ, multipath relaxation. Monitor every ECMP member with BFD; an unmonitored member falls back to slower BGP timers. Keep timers coherent: BFD detection faster than BGP hold time, and graceful-restart behavior coordinated with BFD's control-plane-failure flag.

Avoid using IfState static `multipath` for prefixes FRR also manages. Zebra owns dynamic nexthop groups and responds to protocol/BFD events; a second static ECMP writer creates route churn. [FRR BGP documentation](https://docs.frrouting.org/en/stable-10.7/bgp.html) · [FRR BFD documentation](https://docs.frrouting.org/en/stable-10.7/bfd.html)

## Cilium native routing

With `routing-mode: native`, Cilium sends non-local pod traffic to the host's routing stack. The underlay must route pod CIDRs; same-L2 direct routes or an external BGP daemon provide that reachability. Cilium's BGP control plane advertises pod/LB prefixes, while FRR can provide the fabric peering and kernel route installation. [Cilium routing concepts](https://docs.cilium.io/en/v1.20/network/concepts/routing/) · [Cilium BGP control plane](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane)

The ownership split is:

- IfState: host NICs, bonds/bridges/VLANs, node loopback, WireGuard underlay, and any deliberate static routes.
- FRR: fabric sessions and pod/service prefix routes.
- Cilium: pod datapath, Cilium-owned interfaces, and its own advertisements.

Do not declare Cilium pod-CIDR routes in IfState when Cilium/FRR owns them. Add Cilium runtime interfaces to `parameters.ignore.ifname` (commonly `^cilium_` and `^lxc`) so the next apply does not delete them. Keep `ipv4-native-routing-cidr` aligned with the actual pod allocation; a native-routing configuration without off-node pod routes is incomplete.

## NixOS VM hosts

Declare durable VM bridges in IfState and let the runtime attach dynamic tap devices. Built-in ignores cover `virbr*`, Docker-style bridges, and `veth*`, but not every tap name:

```nix
parameters.ignore.ifname = [
  "^vnet"
  "^tap"
];
```

IfState is a oneshot, not a continuous reconciler: a runtime can create a tap after boot, but the next explicit apply will remove it unless it is ignored or declared. This is an ownership rule, not a reason to disable all orphan cleanup. Inspect `ifstatecli check` after VM creation and before the next host activation.
