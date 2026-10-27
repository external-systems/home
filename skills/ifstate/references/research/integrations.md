# IfState integration patterns — research report

Date: 2026-10-27. Scope: IfState 2.5.1, FRR 10.7, Cilium 1.20, NixOS (nixpkgs), clan-core fleets.

**Evidence labels used throughout:**

- **[OBSERVED-SRC]** — read directly from IfState 2.5.1 source/docs (clone at
  `/tmp/ifstate-research/ifstate-upstream`, pinned to tag `2.5.1`, commit `9ac7caa`),
  FRR 10.7 primary docs/source, Cilium 1.20 primary docs, or nixpkgs module source.
- **[OBSERVED-LAB]** — behavior documented in lab/field write-ups (cited), not
  re-verified here.
- **[DESIGN]** — design guidance derived from the above. Not a vendor recipe;
  test before production use.

---

## 1. What IfState is (and is not)

IfState is a Python 3/pyroute2 declarative frontend for the Linux kernel
netlink API. It covers: links (all virtual kinds + physical), addresses,
neighbours, FDB, routes, PBR rules, VRF, netns, sysctl, tc, wireguard, XDP.
It explicitly positions itself as a base layer for dynamic routing daemons:
"It is possible to skip routes configuration in IfState if a routing daemon
like *bird* or *FRR* does handle it." **[OBSERVED-SRC]** —
<https://ifstate.net/>, §"About".

Non-negotiable default: `ifstatecli apply` **shuts down and removes any
interface not declared** in the config (with a builtin ignore list), and the
2.x builtin defaults (`parameters.defaults_builtin`) clear undeclared
addresses, FDB, neighbours, tc, and set `state: down, master: null` on
managed links. **[OBSERVED-SRC]** — <https://ifstate.net/> §Usage,
<https://ifstate.net/docs/upgrades/> §"Cleanup by default",
`src/libifstate/parser/base.py` (tag 2.5.1) `_default_ifstates`.

**Ownership model in one sentence:** IfState owns *static local network
identity* (links, addresses, permanent FDB/neighbours, its own routes);
FRR/zebra owns *dynamic routing state* (RIB, kernel routes for BGP/OSPF/...,
EVPN FDB/neighbours); the kernel FIB is the shared output both write to,
demarcated by route protocol.

## 2. IfState ↔ FRR/zebra ownership boundary

### 2.1 The route-protocol demarcation [OBSERVED-SRC]

IfState's builtin `ignore.routes`/`ignore.rules` list
(`src/libifstate/parser/base.py` lines 88–128) skips kernel routes/rules by
`rtm_protocol`:

| Proto # | Name | Writer | Builtin-ignored? |
|---|---|---|---|
| 1 | RTPROT_REDIRECT | ICMP redirects | yes |
| 2 | RTPROT_KERNEL | kernel (connected, etc.) | yes |
| 8 | RTPROT_GATED | gated | yes |
| 9 | RTPROT_RA | IPv6 RA | yes |
| 10 | RTPROT_MRT | Merit MRT | yes |
| 11 | RTPROT_ZEBRA | FRR internal (NHG, others) | yes |
| 12–16 | BIRD, DNROUTED, XORP, NTK, DHCP | — | yes |
| 18 | RTPROT_KEEPALIVED | keepalived | yes |
| 42 | RTPROT_BABEL | babeld | yes |
| 186 | RTPROT_BGP | FRR bgpd | yes |
| 187–189 | ISIS, OSPF, RIP | FRR | yes |
| 192 | RTPROT_EIGRP | FRR | yes |
| `to: ff00::/8` | IPv6 multicast | kernel | yes |
| **4** | RTPROT_STATIC | foreign static (systemd-networkd, hand-added) | **NO** |
| **196** | **RTPROT_ZSTATIC** | **FRR staticd static routes** | **NO** |
| 3 | RTPROT_BOOT | **IfState's own default** | NO (that is its marker) |

FRR's mapping is confirmed in FRR 10.7 source: `zebra2proto()` in
`zebra/rt_netlink.c` (stable/10.7) maps `ZEBRA_ROUTE_BGP → RTPROT_BGP`,
`ZEBRA_ROUTE_STATIC → RTPROT_ZSTATIC`; `RTPROT_ZSTATIC` is defined as **196**
in `zebra/rt_netlink.h` (FRR reserves 192–198: LDP 193, SHARP 194, PBR 195,
ZSTATIC 196, OPENFABRIC 197, SRTE 198). IfState installs its own declared
routes with `proto 3` (boot) unless a route specifies `proto`
(`RT_LOOKUPS_DEFAULTS` in `src/libifstate/routing/__init__.py`).

Consequences:

1. **BGP/OSPF/ISIS/RIP/Babel-learned routes are never touched by IfState**
   — safe to let FRR own the FIB entirely. Upstream doc: routes can be
   skipped when FRR handles them (<https://ifstate.net/>).
2. **FRR `staticd` routes (proto 196) and foreign static routes (proto 4)
   are deleted by `ifstatecli apply`** unless (a) also declared in the
   IfState config, or (b) covered by a user ignore entry:
   `parameters.ignore.routes: [{"proto": 196}, {"proto": 4}]`.
   **[OBSERVED-SRC gap; DESIGN mitigation]** Note the trap: you cannot add
   `{"proto": 3}` to the ignore list without breaking IfState's own routes.
3. Route matching during reconciliation compares `(dst, priority, proto)`
   (`route_matches` defaults in `src/libifstate/routing/__init__.py`), so an
   IfState-declared route and an FRR route for the same prefix *coexist* in
   the FIB as separate entries — avoid declaring prefixes in IfState that FRR
   also originates; zebra's admin-distance arbitration (static 1 < eBGP 20 <
   iBGP 200) decides forwarding, which is invisible to IfState.
4. IfState supports static multipath (`multipath:` list) and cross-family
   nexthops (`to: 0.0.0.0/0, via: fe80::x, dev: eth0`)
   (<https://ifstate.net/docs/routing/>). **[DESIGN]** Do not use IfState
   multipath for paths FRR manages — zebra owns ECMP nexthop groups and
   rewrites them on BGP events; two writers to the same FIB prefix churn.

### 2.2 Interfaces, addresses, FDB, neighbours

- **Interfaces:** declare every physical + virtual interface you want kept;
  use `identify:` (`perm_address`, `parent_dev_name`+bus, ...) for physical
  NICs. Undeclared non-ignored interfaces are taken down/deleted on apply
  (builtin ignore: `br-<hex>`, `docker*`, `ppp*`, `veth*`, `virbr*`,
  `vrrp*` — note `vnet*` (libvirt/QEMU tap) is **not** builtin-ignored).
  FRR learns interfaces via netlink and **does not manage interfaces**
  (FRR EVPN docs, §"Linux Interface Configuration": "FRR learns about the
  system's Linux network interface configuration from the kernel via Netlink,
  however does not manage network interfaces directly").
  **[OBSERVED-SRC]** <https://docs.frrouting.org/en/stable-10.7/evpn.html>
- **Addresses:** builtin default `clear_addresses: true` removes undeclared
  addresses from managed interfaces. zebra normally adds none, but DHCP
  clients/keepalived VIPs need `parameters.ignore.ipaddr` /
  `ipaddr_dynamic: true`. **[OBSERVED-SRC]** `parser/base.py`,
  <https://ifstate.net/docs/ignore/>
- **FDB:** reconciliation only enumerates entries with state
  `NUD_NOARP|NUD_PERMANENT`; kernel `NTF_SELF` entries that are not NOARP are
  skipped (`src/libifstate/fdb/__init__.py`). zebra's EVPN remote MACs are
  `NTF_EXT_LEARNED`/reachable — **never touched**. Risk: on a managed vxlan
  interface, zebra's head-end-replication flood entries (00:00:00:00:00:00 →
  remote VTEP) may enumerate as NUD_NOARP and show as `fdb -` removals in
  `ifstatecli check` — **[DESIGN]** verify per §11 and either declare them or
  add `00:00:00:00:00:00` (or per-VTEP dst) to `parameters.ignore.fdb`.
- **Neighbours:** only `NUD_PERMANENT` entries are reconciled
  (`src/libifstate/neighbour/__init__.py`) — EVPN ARP-suppression neighbours
  are safe. Declared `neighbours:` on an interface gives you permanent
  entries (static ARP) if wanted.
- **Rules (PBR):** same proto-based builtin ignore as routes — rules FRR PBR
  installs with proto zebra/bgp survive; IfState rules default to proto 0
  (`parse_rule` default). **[OBSERVED-SRC]** `routing/__init__.py`.

### 2.3 Ordering on NixOS (boot-time contract) [OBSERVED-SRC]

- `networking.ifstate` renders `/etc/ifstate/ifstate.yaml` (schema-validated
  at eval via `check-jsonschema` + `yq`) and runs a **oneshot**
  `ifstate.service` (`ExecStart=ifstatecli --config ... apply`, `TimeoutStartSec=2min`)
  ordered before `network.target` (after `network-pre.target`).
  nixpkgs `nixos/modules/services/networking/ifstate.nix`; upstream
  `module.nix` (tag 2.5.1) is the same module with `disabledModules =
  ["services/networking/ifstate.nix"]` so the upstream flake can replace it.
- `services.frr` unit: `wants network.target; after network-pre.target;
  before network.target` — i.e. **FRR starts after IfState's oneshot has
  applied the interface/address base**. **[DESIGN]** This is the right order:
  links/addresses must exist before bgpd binds/peers; both are oneshot/simple
  ordering, no runtime dependency needed after boot. Do not make either unit
  `PartOf` the other.
- Module assertions: IfState conflicts with NetworkManager and
  `networking.useDHCP` (use IfState hooks for DHCP —
  <https://codeberg.org/routerkit/ifstate/issues/111>).
- Initrd: `boot.initrd.network.ifstate` (systemd stage-1 only) with
  `cleanupSettings` applied at `ExecStop` to tear the network down before
  stage 2. nixpkgs ships tests incl. `initrd-wireguard.nix`
  (unlock-over-WireGuard). **[OBSERVED-SRC]**
  <https://ifstate.net/docs/nixos-options/>, nixpkgs `nixos/tests/ifstate/`.

## 3. Kernel routing & FIB — who writes what

- bgpd/staticd/etc. decide *which* routes should exist; **zebra alone talks
  netlink to the kernel and owns the install**; admin distance arbitrates
  (connected 0, static 1, eBGP 20, OSPF 110, iBGP 200). "Prefix in BGP but not
  forwarding" is diagnosed zebra-side: `show ip route` (zebra RIB) vs
  `ip route show` (kernel FIB); the `r` flag = kernel rejected the install.
  **[OBSERVED-SRC]** <https://docs.frrouting.org/en/stable-10.7/zebra.html>,
  <https://docs.frrouting.org/en/stable-10.7/setup.html>
- Kernel ECMP after install is governed by
  `net.ipv4.fib_multipath_hash_policy` — FRR has no control post-install.
  **[OBSERVED-SRC]** zebra docs (kernel/route interaction); **[DESIGN]** set
  the sysctl in IfState's global `sysctl:` block if L4-flow spreading is
  wanted on FRR-free paths.
- IfState writes routes with `RTM_NEWROUTE` (pyroute2), proto 3 default; its
  declared statics and FRR's dynamics coexist in one FIB, demarcated by
  proto. **[DESIGN]** For audit, `ip route show proto 3` = IfState-owned,
  `proto zebra|bgp|196` = FRR-owned — this split is the operational contract.

## 4. EVPN-VXLAN

### 4.1 The kernel dataplane contract (prerequisites FRR will not create)

From the FRR 10.7 EVPN docs (§Linux (VXLAN) Dataplane), FRR consumes via
netlink but does not create:

- VTEP-IP as `/32` (or `/128`) on `lo`, reachable in the underlay (advertise
  the /32; any IGP/BGP/static works). **[OBSERVED-SRC]**
- One **VRF** device per tenant routing table (`vrf_table:` in IfState).
- Per VNI (traditional model): one `bridge` (SVI for IRB; unique MAC per
  VTEP; L3VNI's L3-SVI must have **no** IP, `addrgenmode none`) + one `vxlan`
  device: `vxlan_local: <vtep-ip>`, `vxlan_port: 4789`, `vxlan_id: <vni>`,
  `vxlan_learning: false` ("Dynamic MAC/VTEP learning should [be] disabled on
  VXLAN interfaces used in EVPN"), `master: <bridge>`, and bridge-port
  attributes `neigh_suppress: true`, `learning: false` ("ARP/ND suppression
  [and] MAC learning [are] kernel function[s], not managed [by] FRR").
  **[OBSERVED-SRC]** — all expressible in IfState 2.5.1 schema
  (`vxlan_*` attrs, `brport.{learning,neigh_suppress}`, `fdb:`).
- Remote VTEPs: learned via EVPN type-2/3 — **no static `fdb:` dst entries
  and no `vxlan_group`/static flooding in an FRR-EVPN setup** (static
  flooding is only for standalone VXLAN; see IfState's `examples/vxlan.md`,
  which is the no-FRR case). **[DESIGN]**
- FRR side: `vrf X / vni <l3vni>` gives the VRF its L3VNI; underlay BGP
  instance carries `address-family l2vpn evpn` with `advertise-all-vni`
  (mandatory) + `advertise-svi-ip`; per-VRF instance `advertise ipv4
  unicast` exports type-5s. **[OBSERVED-SRC]**
  <https://docs.frrouting.org/en/stable-10.7/evpn.html>

### 4.2 IfState 2.5.1 gap: Single-VXLAN-Device (SVD) model NOT expressible

The SVD/`external` model (one multi-VNI vxlan per UDP port; `vnifilter`;
`bridge vlan add dev vxlan0 vid N tunnel_info id V`) is the FRR-documented
scaling model for multi-VNI deployments (the FRR docs' anycast-gateway
section — which builds on SVD — is "recommended for most EVPN deployments").
IfState 2.5.1's schema has no
`vxlan_external`/`vxlan_vnifilter` link attributes and `brvlan` items carry
only `vid/pvid/untagged/self` — **no `tunnel_info id` mapping**
(`src/libifstate/schema/2/ifstate.conf.schema.json`). **[OBSERVED-SRC gap]**
**[DESIGN]** On 2.5.1 use the traditional one-vxlan-per-VNI model (scales
fine to dozens of VNIs); if SVD is required, the VNI↔VLAN mappings need an
out-of-band `ExecStartPost`/hooks or a newer IfState.

### 4.3 L2 vs L3 site stretching [DESIGN, grounded in OBSERVED-SRC]

- **L3 stretch (default choice):** routed reachability between sites —
  loopback /32s, eBGP (optionally BFD) over WireGuard/underlay. IfState =
  links + VTEP/loopback addresses only; FRR = everything routing. No MACs
  cross sites; least operational surface. FRR docs: VTEP-IP reachability
  "static routes or routing protocols like IS-IS or OSPF can also [be] used".
- **L2 stretch (EVPN MAC-VRF):** only when workloads genuinely need one
  broadcast domain (MAC mobility, anycast gateways). Costs: the §4.1
  dataplane contract, RT hygiene (RT mismatch = missing routes; label/VNI
  mismatch = blackholed traffic), neigh-table coupling (zebra takes ARP-sup
  IPs from the kernel neigh table), per-VTEP unique bridge MACs.
- Middle path (field-proven, **[OBSERVED-LAB]**,
  <https://blog.bella.network/>/fedepaol walkthroughs cited in FRR doc
  ecosystem): EVPN only on legs that need stretch, plain eBGP everywhere else.
- Cilium does **not** do EVPN; Cilium BGP peers with an EVPN fabric like any
  other BGP speaker (node-local FRR pattern, §6).

## 5. WireGuard transport & AllowedIPs

IfState 2.5.1 wireguard surface **[OBSERVED-SRC]**
(<https://ifstate.net/examples/wireguard/>,
`src/libifstate/wireguard/__init__.py`): per-interface `private_key`
(`!include` a file — use sops/vars for the key material),
`listen_port`, `fwmark`, `peers.<pubkey>.{endpoint, allowedips[],
preshared_key}`, and `table:` — when set, IfState auto-derives routes from the
union of peers' `allowedips` into that routing table (wg-quick `Table=`
equivalent). `bind_netns` places the tunnel socket in another netns (tested
in nixpkgs `nixos/tests/ifstate/wireguard.nix`).

Integration rules (mostly field-proven, label as such):

- **AllowedIPs is cryptokey routing, not IP routing** — the destination IP
  selects the peer key. Overlapping `AllowedIPs` between peers on one
  interface silently shadows the later peer (running config shows
  `allowed ips: (none)`). **[OBSERVED-LAB]** (OPNsense 3-site HA thread;
  FRR skill research note). One listener per full-table (`0.0.0.0/0`) peer.
- **[DESIGN]** One WireGuard interface per peering/path. ECMP across WG =
  across interfaces (kernel hashes per flow in the FIB; each interface then
  looks up its single peer). Identical AllowedIPs across *different*
  interfaces is fine. Each interface's AllowedIPs must cover all subnets
  routed through it. One eBGP session per tunnel; `maximum-paths` +
  `bgp bestpath as-path multipath-relax`; one BFD session per member.
- Even when FRR "owns" routing, keep explicit per-peer remote-site subnets
  in `allowedips` as a backstop — it caps what an FRR route-all can attract
  through the tunnel. **[OBSERVED-LAB]**
- IfState `table:` auto-routes are **IfState routes (proto 3)** — they are
  static, not FRR-managed. **[DESIGN]** For FRR-over-WG underlays prefer
  /31+/112 transfer-net addresses on the wg interface + `network` statements
  in bgpd, not ifstate statics; or if you do use ifstate routes for the
  transfer nets, declare them explicitly (proto 3) and keep FRR out of those
  prefixes.
- Firewall: NixOS opens nothing by default; allow UDP `listen_port` (and
  4789/udp for VXLAN, 8472/udp for Cilium).

## 6. Cilium native routing & the node-local FRR pattern

Cilium 1.20 facts **[OBSERVED-SRC]**
(<https://docs.cilium.io/en/v1.20/network/concepts/routing/>):

- Default is encapsulation (VXLAN 8472/UDP or Geneve 6081/UDP); underlying
  network needs no PodCIDR awareness.
- **Native routing** (`routing-mode: native` + `ipv4-native-routing-cidr`):
  "Cilium will delegate all packets not addressed to another local endpoint
  [to the] routing subsystem of the Linux kernel" — the network **must** be
  able to route PodCIDRs. Cilium auto-enables IP forwarding. Same-L2:
  `auto-direct-node-routes: true`; otherwise an external BGP daemon must
  distribute pod routes.
- Cilium's BGP control plane (GoBGP-based, per-node) is **advertise-only**:
  it announces PodCIDRs/LB VIPs; it does not program in-cluster reachability
  and has **no BFD** in 1.20 (hold/keepalive timers are the detection).
  <https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane>

**[DESIGN]** Integration shapes:

- **Pattern A (node-local FRR):** Cilium peers only with `::1`; per-node FRR
  owns fabric peering (unnumbered RFC 8950 eBGP to both TORs, ECMP, BFD,
  next-hop rewrite). Requires `allow-reserved-ranges` (global),
  `bgp allow-martian-nexthop`, inbound route-map rewriting Cilium's ::1
  next-hop to the node's real address, `ipv6 nht resolve-via-default`
  (global) or learned pod routes never reach the FIB. **[OBSERVED-LAB]**
  (lab-verified; FRR skill `cilium.md` research file).
- **Pattern B:** Cilium dials TORs directly (or `autoDiscovery.mode:
  DefaultGateway` against an FRR `bgp listen range`). Peer selection becomes
  routing-table interpretation; add `maximum-prefix` + inbound route-maps.
- **Ownership split with IfState:** IfState manages host links/addresses/lo
  (incl. the node's unique loopback/dummy address — duplicate global
  addresses break source selection **[OBSERVED-LAB]**); FRR manages the BGP
  and the kernel FIB for pod prefixes (proto 186 — invisible to IfState);
  Cilium manages pod datapath. Do **not** declare pod-CIDR routes in
  IfState. `cilium-agent` interfaces (`cilium_*`, `lxc*`) — add
  `^cilium_`, `^lxc`, `^veth` (builtin) to `ignore.ifname`; Cilium 1.20
  creates `cilium_vxlan`/`cilium_geneve`/`cilium_host`/`cilium_net`.
  **[DESIGN]** (ignore list extension; interface names from Cilium docs).

## 7. Spine-leaf / redundant underlays

**[DESIGN, grounded in OBSERVED-SRC FRR docs + field notes]**

- Dual-homed leaf ↔ two spines: unnumbered eBGP (RFC 8950) per spine,
  `maximum-paths 8` + `bgp bestpath as-path multipath-relax` for ECMP, BFD
  per member (150ms profile), graceful restart with C-bit coherence
  (`bfd check-control-plane-failure`), timers ordered BFD ≪ BGP hold ≪ GR.
- Same-AS leaves through a different-AS spine: spine is pure pass-through;
  leaves need `allowas-in origin` in **both** ipv4 and l2vpn-evpn families.
- iBGP fabric: RRs with `bgp listen range`, `capability extended-nexthop`;
  RR can run `bgpd --no_kernel` (no zebra).
- IfState's role at leaves/borders is exactly §2: uplink bonding/LACP
  (supported: `examples/lacp.md`), /31 or unnumbered uplink addresses,
  loopback /32s; FRR owns all underlay routing. Redundancy lives in FRR
  (ECMP+BFD), **not** in IfState multipath.

## 8. NixOS VM hosts

- The NixOS module is a **oneshot at boot**, not a continuously reconciling
  daemon: runtime-created interfaces (VM taps, hotplug) are untouched after
  boot, but the *next* apply (rebuild switch) will remove undeclared ones.
  **[OBSERVED-SRC]** (module ExecStart).
- QEMU/libvirt: builtin ignore covers `virbr*`, `br-<hex>` (libvirt default
  bridges) but **not** `vnet*` (QEMU taps) or `tap*`
  (`parser/base.py` ifname_builtin). **[DESIGN]** VM hosts need
  `parameters.ignore.ifname: ["^vnet", "^tap"]` (or declare per-VM bridges in
  ifstate and let taps attach dynamically).
- IfState-managed bridges for VMs: declare the bridge; set
  `parameters.defaults` to not clear addresses on it; keep `fdb` cleanup in
  mind for the tap ports (they enumerate; `ignore.fdb` multicast defaults
  cover the flooded MACs).
- nixpkgs ships NixOS VM tests for the module (`ping`, `wireguard`,
  `initrd-wireguard`, partial-broken-config) — usable as executable examples
  of the module in a VM host context. **[OBSERVED-SRC]**
  `nixos/tests/ifstate/`.

## 9. Clan-managed fleets: generic clanService interface vs per-machine settings

**[DESIGN]** — grounded in the clanservices authoring conventions
(roles/interface/perInstance/perMachine; JSON-serializable interfaces; vars
generators; exports) and this repo's existing `machine-type`/`tags` services.

Proposed boundary:

- **Generic clanService interface (role settings, fleet-wide):** everything
  topology and policy: fabric ASN + per-site ASN, loopback/VTEP pools,
  WireGuard listen ports, VNI/VLAN allocations, EVPN RT conventions,
  underlay transfer-net ranges, Cilium peering mode (A/B), timers/BFD
  profiles, route-policy knobs. Keep interfaces JSON-serializable; secrets
  never in settings.
- **Vars generators (per machine, in `nixosModule`):** WireGuard keypairs
  (upstream clan-core `wireguard` service pattern: private secret +
  publickey `.secret = false` read cross-machine via `clanLib.getPublicValue`);
  per-machine loopback/VTEP allocations if not settings-driven.
- **Per-machine settings (inventory `machines.<m>.settings`):** only
  hardware identity: `identify` attributes (PCI/bus/permaddr) for physical
  ports, interface names/paths, which NIC is uplink. These are inherently
  machine facts — the interface cannot see `config`, so anything depending
  on machine config must live here or in `perInstance`'s produced module.
- **perInstance produced module:** assembles `networking.ifstate.settings`
  from settings + vars paths, and `services.frr.config`. Namespace by
  `instanceName` (interfaces, generators). Use NixOS `assertions` for
  semantic checks (e.g. VTEP pool vs ASN collisions).
- **Exports (experimental):** endpoints/host metadata between fabric
  services; scope helpers only.
- Fleet hygiene: keep the proto-3/zebra/bgp/196 contract (§2) encoded once
  in the service's IfState template (ignore entries for 196/4, fdb rules,
  `cilium_*`/`vnet*`/`tap*` ignores on virt hosts) rather than re-derived
  per machine.

## 10. Gap & risk register

| # | Item | Evidence | Mitigation |
|---|---|---|---|
| 1 | FRR staticd routes (proto 196) not builtin-ignored → deleted by apply | OBSERVED-SRC both sides | `ignore.routes: [{proto: 196}]` or declare them |
| 2 | Foreign static routes (proto 4) not ignored | OBSERVED-SRC | same, proto 4 |
| 3 | SVD/`external`+`tunnel_info` VXLAN model not expressible | OBSERVED-SRC schema | traditional per-VNI model; or ExecStartPost |
| 4 | zebra BUM flood FDB entries may enumerate as removals on managed vxlan ifs | OBSERVED-SRC (state mask) + DESIGN | `ifstatecli check` inspection; ignore.fdb/declare |
| 5 | `vnet*`/`tap*` VM taps not builtin-ignored | OBSERVED-SRC | ignore.ifname |
| 6 | Cilium `cilium_*`/`lxc*` interfaces not builtin-ignored | DESIGN | ignore.ifname |
| 7 | Overlapping AllowedIPs on one wg interface shadows peer | OBSERVED-LAB | one peer/listener per full-table peer |
| 8 | IfState module asserts vs NetworkManager & useDHCP | OBSERVED-SRC | hooks for DHCP |

## 11. Live-debug command sequences

Ownership drift (run after every ifstate change on an FRR host):

```bash
ifstatecli check                      # dry-run; scan for unexpected 'del'/'fdb -'
ifstatecli showall | sed -n '/ignore:/,/^parameters:/p'   # builtin ignores visible
ip -4 route show proto 3              # IfState-owned statics
ip -4 route show proto zebra; ip -4 route show proto bgp  # FRR-owned
ip -4 route show proto 196            # FRR staticd — must exist AFTER apply
ip -6 route show table all | grep -c proto
ip rule show
```

FRR session/RIB/FIB triage:

```bash
vtysh -c 'show bgp summary' -c 'show ip route'
ip route show <prefix>                # RIB-vs-FIB: 'r' flag in show ip route = kernel rejected
journalctl -u frr -n 200 --no-pager
systemctl reload frr                  # frr-reload.py --reload (NixOS reload path)
```

EVPN dataplane verification:

```bash
vtysh -c 'show bgp l2vpn evpn summary' -c 'show evpn vni' -c 'show vrf vni'
vtysh -c 'show evpn mac vni <N>' -c 'show evpn arp-cache vni <N>'
bridge fdb show dev vni<N>            # type-3 all-zeros dst <vtep> = BUM list; per-MAC dst = type-2
bridge vlan show dev vxlan0           # SVD only: tunnel_info mappings present?
ip -d link show vni<N>                # vxlan_learning must be off for EVPN
tcpdump -ni <uplink> udp port 4789    # VXLAN only between VTEPs
```

WireGuard:

```bash
wg show <if> latest-handshakes; wg show <if> allowed-ips   # '(none)' = shadowed peer
ifstatecli check | grep -A2 'wg'    # would-ifstate remove/replace wg peers?
```

Cilium × FRR:

```bash
cilium bgp peers; cilium bgp routes advertised ipv4 unicast
kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp route-policies
kubectl get ciliumbgpclusterconfigs,cliliumbgppeerconfigs -A   # CRD conditions
```

Kernel FIB flow check (ECMP member selection):

```bash
ip -4 fib match <dst>                 # which member a flow takes
sysctl net.ipv4.fib_multipath_hash_policy
```

## 12. Source index (stable URLs)

IfState 2.5.1 (tag `2.5.1`, commit 9ac7caa; clone: /tmp/ifstate-research/ifstate-upstream):

- Docs home: <https://ifstate.net/> · schema: <https://ifstate.net/2.0/schema/>
- CLI: <https://ifstate.net/docs/cli/> · ignore: <https://ifstate.net/docs/ignore/>
- routing: <https://ifstate.net/docs/routing/> · namespaces: <https://ifstate.net/docs/namespaces/>
- vrrp: <https://ifstate.net/docs/vrrp/> · upgrades (2.x cleanup defaults): <https://ifstate.net/docs/upgrades/>
- NixOS options: <https://ifstate.net/docs/nixos-options/>
- examples: wireguard <https://ifstate.net/examples/wireguard/> · vxlan <https://ifstate.net/examples/vxlan/> · vrf <https://ifstate.net/examples/vrf/>
- Source (per-tag stable):
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/parser/base.py> (builtin ignore protos)
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/routing/__init__.py> (route proto default 3, reconciliation, rules)
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/fdb/__init__.py> (FDB state-mask reconciliation)
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/neighbour/__init__.py>
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/wireguard/__init__.py> (table auto-routes)
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/schema/2/ifstate.conf.schema.json>
  - <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/module.nix> (upstream NixOS module)
- Repo/issue tracker: <https://codeberg.org/routerkit/ifstate>

FRR 10.7:

- EVPN: <https://docs.frrouting.org/en/stable-10.7/evpn.html> (incl. "FRR ... does not manage network interfaces directly", SVD/external/vnifilter, dataplane contract)
- zebra: <https://docs.frrouting.org/en/stable-10.7/zebra.html>
- Source (stable/10.7): <https://github.com/FRRouting/frr/blob/stable/10.7/zebra/rt_netlink.c> (`zebra2proto`, `proto2zebra`), <https://github.com/FRRouting/frr/blob/stable/10.7/zebra/rt_netlink.h> (RTPROT_ZSTATIC=196)

Cilium 1.20:

- Routing concepts (encapsulation vs native routing): <https://docs.cilium.io/en/v1.20/network/concepts/routing/>
- BGP control plane: <https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane>

NixOS:

- Module: <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ifstate.nix>
- Tests: <https://github.com/NixOS/nixpkgs/tree/nixos-unstable/nixos/tests/ifstate>
- FRR module (unit ordering): <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/frr.nix>

clan-core services conventions: <https://clan.lol/> · authoring guide <https://docs.clan.lol/guides/services/community> · reference services wireguard/sshd in <https://github.com/clan-core/clan-core>
