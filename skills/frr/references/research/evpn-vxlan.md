# EVPN-VXLAN with FRRouting (FRR) on Linux/NixOS — research note

**Scope**: how FRR builds EVPN-VXLAN networks (L2 stretch and L3 EVPN) on
plain Linux/NixOS hosts — extending the FRR-on-NixOS skill beyond its current
BGP focus (eBGP site meshes, Cilium BGP control plane, BFD/GR). Fetched
2026-10-24. Existing notes (`frr-docs.md`, `bgp.md`, `cilium-nixos-integration.md`,
`bfd-autodiscovery.md`, `nixos.md`, `operations.md`) are untouched; this note
adds the EVPN overlay story.

Sources:

1. FRR official EVPN documentation —
   <https://docs.frrouting.org/en/latest/evpn.html> (citations use anchors
   relative to this base URL; command references from the BGP chapter
   <https://docs.frrouting.org/en/latest/bgp.html> and zebra chapter
   <https://docs.frrouting.org/en/latest/zebra.html>, fetched in full).
2. Federico Paoletti (fedepaol), "L3EVPN using FRR and Linux vxlans",
   2024-05-09 — <https://fedepaol.github.io/blog/2024/05/09/l3evpn-using-frr-and-linux-vxlans/>
   (plus his series follow-ups, §4).
3. Vincent Bernat, "VXLAN & BGP EVPN", 2017 — <https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn>
4. Ivan Pepelnjak (ipSpace), "Worth Reading: EVPN/VXLAN with FRR on Linux
   Hosts", 2022-10-01 — <https://blog.ipspace.net/2022/10/worth-reading-evpn-vxlan-unix-hosts/>
   and the linked/follow-up collection (§4).
5. nixpkgs `frr` package (nixos-unstable) —
   <https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/pkgs/by-name/fr/frr/package.nix>
   and the NixOS `services.frr` module; kernel config verified empirically on
   this host (NixOS 6.18.50).

---

## 1. FRR EVPN documentation reference

From `evpn.html` (fetched complete; the page ends at the
`#displaying-evpn-information` section) and the EVPN command sections of
`bgp.html` / `zebra.html`.

### 1.1 Concepts as FRR documents them (`#evpn-concepts`)

- **EVPN** (RFC 7432) is a BGP extension signaling bridged (L2) and routed
  (L3) VPNs over a common network; relevant updates: **RFC 9135** (IRB),
  **RFC 9136** (IP prefix advertisement), **RFC 8584** (DF election
  extensibility), **RFC 8365** (VXLAN NVO). FRR supports **All-Active
  Layer-2 Multihoming (MHD)** via LACP Ethernet Segments, and **both
  symmetric and asymmetric IRB**. FRR implements MAC-VRFs with a
  **"VLAN-Based Service Interface"** model (one VNI per EVI), and processes
  symmetric IRB routes per the **"Interface-less IP-VRF-to-IP-VRF Model"**
  (RFC 9136). There is no VLAN-aware-bundle service model in FRR.
- With the VLAN-based model, **a single VNI = one EVPN instance (EVI)** with
  its own Route Distinguisher and import/export Route Targets.
- A VNI is either **Layer-2** (bound to a MAC-VRF: a bridging table — MAC/fdb
  + ARP/NDP entries) or **Layer-3** (bound to an IP-VRF: a routing table,
  operating like a traditional L3VPN VRF). An IP-VRF : MAC-VRF relationship
  is many-to-one; in FRR the L3VNI association of an L2VNI is determined by
  the SVI of the VLAN and the VRF membership of that SVI — no SVI, or SVI not
  enslaved to a VRF ⇒ the L2VNI is associated with the **default** VRF.
- An **SVI** is an L3 interface bound to a bridging domain; on Linux either a
  traditional bridge or a VLAN subinterface of a VLAN-aware bridge.

### 1.2 Route Targets — the import rule (`#evpn-route-targets`)

> "IP-VRFs and EVIs are identified by Route Targets, **never by labels**
> (VNIs or MPLS labels). The Route Targets alone determine into which IP-VRF
> or EVI a received route is imported."

The VNI/MPLS label in a route is **pure dataplane information** — it tells
the ingress VTEP which label to put on the wire so the egress VTEP can map
packets to the right VRF/bridge (see downstream VNI, §1.8). Labels don't have
to match between peers. Operational consequence, verbatim from the docs: *"a
Route Target mismatch shows up as routes missing from the receiving IP-VRFs /
EVIs, while a label (VNI / MPLS Label) problem shows up as imported routes
whose traffic is dropped or misdelivered by the dataplane."*

- **Wildcard RTs** (`#evpn-wildcard-route-targets`): `*:N` matches any fully
  qualified RT (`AS2:N`, `AS4:N`, `A.B.C.D:N`) whose local administrator is
  `N`; an FRR convenience (non-standard). Local admin is typically the VNI.
  Crucial for eBGP fabrics where each leaf has a unique AS and therefore
  originates a different `AS:VNI` RT: *"A single wildcard import Route Target
  imports routes from all other leafs without having to list every leaf AS."*
  (2-byte-AS RTs compare the full 4-byte local admin; 4-byte-AS and IPv4 RTs
  only have a 2-byte local admin, so `route-target import *:70000` can never
  match them.)
- **Automatic RTs** (`#evpn-automatic-route-targets`): FRR derives one auto RT
  per direction for every IP-VRF with an L3VNI and every EVI/L2VNI, unless a
  manual RT is configured:
  - auto **import** RT = wildcard `*:VNI`;
  - auto **export** RT = fully-qualified 2-byte-AS `(AS & 0xFFFF):VNI`
    (RFC 4360 type 0x00) — only the low 2 bytes of the AS fit (48-bit RT
    payload can't hold 4-byte AS + 3-byte VNI). In asdot+ notation (RFC 5396)
    the low 2 bytes are simply the last integer, enabling AS-block allocation
    like `123.<low-2-bytes>` per pod.
  - Control per direction: `auto-route-target <import|export|both>
    <add-always|add-never|add-if-no-manual|rfc8365-compatible>` (default
    `add-if-no-manual`; RTs are additive, never override). The
    `rfc8365-compatible` form encodes the VXLAN encapsulation type in the
    upper byte of the local-admin field (RFC 8365 §5.1.2.1); instance-level,
    off by default. **Deprecated since 10.8**: `route-target ... auto` and
    `autort rfc8365-compatible` remain as hidden aliases
    (`bgp.html#bgp-evpn-route-target-configuration`).

### 1.3 The Linux (VXLAN) dataplane (`#the-linux-vxlan-dataplane`)

FRR learns interface state via netlink; **it does not manage interfaces** —
iproute2 (or ifupdown2 etc.) sets up the kernel side. Two netdev models:

- **Single VXLAN Device (SVD)** — better read "Multi-VNI VXLAN interface".
  The `external` flag (`VXLAN_F_COLLECT_METADATA`, kernel commit ee122c79d4)
  makes one vxlan device receive traffic for **all VNIs** on a UDP port;
  **only one such device per UDP port** unless `vnifilter`:
  ```
  ip link add dev <vxlanif> type vxlan external ...
  bridge link set dev <vxlanif> vlan_tunnel on neigh_suppress on learning off
  bridge vlan add dev <vxlanif> vid <vlan>
  bridge vlan add dev <vxlanif> vid <vlan> tunnel_info id <vni>
  ```
  `vnifilter` (`VXLAN_F_VNIFILTER`, kernel commit f9c4bb0b24) allows multiple
  SVDs per port/bridge; then also `bridge vlan vni add dev <vxlanif> vni <vni>`
  (works even un-enslaved).
- **Traditional VXLAN device** — no `external` flag; receives a single VNI,
  so one device per VNI.

### 1.4 Sample EVPN configuration (`#frr-configuration`, `#sample-configuration`)

The doc's worked example: IP-VRFs vrf1/vrf2 with L3VNIs 100/200, vrf3 with no
L3VNI; MAC-VRFs VLAN 10/20/30/40/50 ↔ L2VNIs 110/220/330/440/550 in vrf1/
vrf2/vrf3/default/L2-only. FRR side (verbatim):

```
vrf vrf1
 vni 100
exit-vrf
!
vrf vrf2
 vni 200
exit-vrf
!
router bgp 4200000000
 neighbor 192.168.122.12 remote-as internal
 !
 address-family ipv4 unicast
  network 100.64.0.1/32
 exit-address-family
 !
 address-family l2vpn evpn
  neighbor 192.168.122.12 activate
  advertise-all-vni
  advertise-svi-ip
 exit-address-family
exit
!
router bgp 4200000000 vrf vrf1
 !
 address-family ipv4 unicast
  redistribute static
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute static
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast
  advertise ipv6 unicast
 exit-address-family
exit
!
router bgp 4200000000 vrf vrf2
 !
 address-family ipv4 unicast
  redistribute static
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute static
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast
  advertise ipv6 unicast
 exit-address-family
exit
```

Key semantics from the surrounding text:

- `vrf X / vni N` under the top level gives the VRF its **L3VNI**; until then
  zebra sees the VNI from netlink but treats it as an L2VNI (L2 vs L3 context
  visible in `show evpn vni`).
- The **VTEP-IP** (here 100.64.0.1) must be reachable by other VTEPs —
  advertised here via BGP `network`, but static/IS-IS/OSPF work; IPv4 or IPv6.
- `advertise-all-vni` **enables EVPN for the BGP instance** and defines the
  underlay VRF (usually default); **mandatory**, and only one VRF may carry
  it (`bgp.html#clicmd-advertise-all-vni` rejects a second).
- `neighbor ... activate` under `address-family l2vpn evpn` enables EVPN NLRI
  per peer.
- `advertise-svi-ip` originates "self" type-2 routes for the MAC/IP pairs of
  local SVIs.
- In the tenant VRF BGP instance, `advertise <ipv4|ipv6> unicast` under
  `address-family l2vpn evpn` exports the VRF's unicast RIB (locally
  originated, learned, or VRF-leaked — anything valid and selected; routes
  directly imported from EVPN are not re-exported) as **type-5** routes. The
  optional `skip-evpn-imported` keyword prevents re-export loops for
  EVPN-origin routes leaked between VRFs.

### 1.5 Linux interface configuration (`#linux-interface-configuration`)

Config considerations (verbatim-ish list): VTEP-IP always a reachable IP on
`lo`; an **L3VNI must always have an SVI** (the L3-SVI) and the L3-SVI must
**not** be assigned any IP (`addrgenmode none` to disable v6 autoconf); an SVI
for an L2VNI is only needed for IRB routing or ARP/ND suppression —
**suppression is a kernel function**, enabled per bridge_slave via
`neigh_suppress` and only on vxlan interfaces; disable dynamic MAC learning
per bridge_slave (`learning off`) and dynamic VTEP learning per vxlan device
(`nolearning`); **no static `remote` VTEPs** (remote VTEPs come from EVPN).

Traditional model (one bridge + one vxlan per VNI), L3VNI example verbatim:

```
ip addr add 100.64.0.1/32 dev lo
ip link add vrf1 type vrf table 1100
ip link set vrf1 up
ip link add br100 type bridge
ip link set br100 master vrf1 addrgenmode none
ip link set br100 addr aa:bb:cc:00:00:64
ip link add vni100 type vxlan local 100.64.0.1 dstport 4789 id 100 nolearning
ip link set vni100 master br100 addrgenmode none
ip link set vni100 type bridge_slave neigh_suppress on learning off
ip link set vni100 up
ip link set br100 up
```

and L2VNI with IRB SVI:

```
ip link add br10 type bridge
ip link set br10 master vrf1
ip link set br10 addr aa:bb:cc:00:00:6e
ip addr add 10.0.10.1/24 dev br10
ip addr add 2001:db8:0:10::1/64 dev br10
ip link add vni110 type vxlan local 100.64.0.1 dstport 4789 id 110 nolearning
ip link set vni110 master br10 addrgenmode none
ip link set vni110 type bridge_slave neigh_suppress on learning off
```

Ports join via VLAN subinterfaces (`ip link add link eth0 name eth0.10 type
vlan id 10; ip link set eth0.10 master br10`) or directly. Non-routed L2-only
VLANs get `sysctl -w net.ipv{4,6}.conf.<svi>.forwarding=0` and no SVI IP.

SVD model essentials (verbatim): one VLAN-aware bridge + one `external
vnifilter` vxlan carrying all VNIs; a per-VTEP unique **routermac** set on
both bridge and vxlan device (advertised with type-2-with-IP and type-5
routes, used for symmetric routing); per-VNI `bridge vlan add ... tunnel_info
id` mappings; L3VNI bound with a VLAN subinterface of the bridge enslaved to
the VRF (`ip link add vrf1br link br0 type vlan id 1100; ip link set vrf1br
master vrf1`, no address, routermac).

Anycast gateways with SVD (`#anycast-gateways-with-single-vxlan-device`):
same MAC for each L2VNI on all VTEPs; a macvlan device per L2VNI carries the
shared gateway IP; **critical**: `bridge fdb add <anycast-mac> dev br0 self
local` so packets to the anycast MAC don't traverse the overlay. "This
approach is recommended for most EVPN deployments as it simplifies
configuration management and improves host mobility."

### 1.6 EVPN command reference (from `bgp.html`)

- **BUM handling** (`#clicmd-advertise-all-vni` area): `flooding
  <disable|head-end-replication>` globally or per-`vni` context; default
  floods BUM to all VTEPs in the EVI.
- **Route-target configuration** (`#bgp-evpn-route-target-configuration`) at
  two levels: IP-VRF/L3VNI — under `address-family l2vpn evpn` of
  `router bgp AS vrf NAME`; EVI/L2VNI — under `vni N` inside the AF in the
  underlay VRF (rejected elsewhere: "This command is only supported under
  EVPN VRF"). Verbatim example:
  ```
  router bgp 64496
   !
   address-family l2vpn evpn
    advertise-all-vni
    vni 1234
     route-target import 555:666
     route-target export 1234:1234
    exit-vni
   exit-address-family
  ```
  and VRF level:
  ```
  router bgp 64496 vrf myvrf
   !
   address-family l2vpn evpn
    route-target import 64496:12344
    route-target import 64496:17000000
    route-target import *:12345
    route-target export 64496:12344
  ```
  IP-VRF RTs attach to type-2/type-5 routes; EVI RTs to type-2/type-3.
  Export RTs apply only to locally originated routes.
- **`advertise-pip`** (`#bgp-evpn-advertise-pip`): for symmetric-routing MLAG
  setups. Normally all EVPN routes use the anycast IP (vxlan local tunnel IP)
  as next-hop and the L3VNI SVI MAC as Router-MAC (RMAC). `advertise-pip`
  makes **type-5 and self type-2** routes use the system's individual IP
  (default BGP instance router-id; overridable) and system MAC (SVI MAC; a
  MAC-VLAN subinterface of the L3VNI SVI provides the anycast MAC) — avoiding
  suboptimal routing when traffic lands on the "wrong" MLAG member.
  **Enabled by default**; CLI `advertise-pip [ip <addr> [mac <addr>]]`.
- **`advertise-svi-ip`** (`#evpn-advertise-svi-ip`): originates the SVI
  IP/MAC as a type-2 route so a unique SVI IP is reachable without overlay
  flooding. *"Note that you should not enable both the advertise-svi-ip and
  the advertise-default-gw at the same time."* (`advertise-default-gw` itself
  is only mentioned in passing in current docs — it advertises the anycast
  gateway default as a type-2; see gaps §6.)
- **Type-5 origination knobs** (`#clicmd-advertise-ipv4-ipv6-unicast-gateway-ip-...`):
  `advertise <ipv4|ipv6> unicast [gateway-ip] [route-map RMAP_NAME]
  [skip-evpn-imported]` and `advertise <ipv4|ipv6> vpn [route-map RMAP_NAME]`
  (VPN-route export, incl. SRv6 SID propagation). With `gateway-ip`, all
  paths are exported via AddPath and each path's nexthop becomes the type-5's
  gateway IP (RFC 9136 overlay index); route-map form: `set evpn gateway-ip
  <ipv4|ipv6> <addr>`; receiving side needs `enable-resolve-overlay-index`
  under the EVPN AF. Overlay-index requirements: **asymmetric routing model
  only**, traditional (non-VLAN-aware) bridge model only, all L2VNIs present
  on all PEs, L3VNI required.
- **MAC-VRF Site-of-Origin**: SoO extended community on routes originated
  from a MAC-VRF plus a self-SoO import filter (type-2/type-3 only) — solves
  MLAG anycast-VTEP ownership conflicts / spurious MAC-mobility events.
- **EVPN multihoming commands** (`#clicmd-evpn-mh-es-id-...`): interface/zebra
  side `evpn mh es-id <(1-16777215)|ESINAME>`, `evpn mh es-sys-mac X:X...`
  (sysmac+discriminator ⇒ 10-byte type-3 ESI; ESINAME is a type-0 ESI),
  `evpn mh es-df-pref (1-16777215)` (preference-based DF election per
  draft-ietf-bess-evpn-pref-df); EAD-per-ES/EAD-per-EVI (type-1) routes
  advertise/learn ESs, `disable-ead-evi-rx|tx` interop knobs, `use-es-l3nhg`
  (L3 nexthop groups for symmetric-IRB fast failover), `evpn mh redirect-off`,
  `evpn mh uplink` (protodown server links when the underlay is cut),
  `evpn mh neigh-holdtime|mac-holdtime (0-86400)` (proxy advertisement
  holdtimes, draft-rbickhart-evpn-ip-mac-proxy-adv), `evpn mh startup-delay
  (0-3600)`, BGP-side `ead-es-frag evi-limit (1-1000)`. EVPN-MH is positioned
  as the **replacement for MLAG/anycast VTEPs**, introducing MAC-ECMP (an FDB
  entry pointing at a list of remote VTEPs). (The former standalone
  `evpn-multihoming.html` page is gone from current docs — these commands in
  `bgp.html` are what remains; see §6.)
- **Downstream VNI** (`#bgp-evpn-downstream-vni`): the egress VTEP dictates
  the VNI the ingress uses (label2 of type-2 / label of type-5), so VRF-leak
  topologies don't need identical VNIs everywhere; **requires the SVD
  dataplane** — will not work with traditional vxlan devices.
- **Show commands** (documented): `show bgp l2vpn evpn route [type
  <ead|1|macip|2|multicast|3|es|4|prefix|5>] [detail] [self-originate]
  [brief] [json]`; `show bgp vni <all|VNI> [vtep VTEP] [type ...] [detail|json]`;
  per-neighbor `show [ip] bgp l2vpn evpn neighbors <PEER> routes [json]`
  (`bgp.html`); `show evpn mac vni (1-16777215) detail [json]`, `show vrf
  [<NAME|all>] vni [json]` (`evpn.html#displaying-evpn-information`); zebra:
  `show evpn access-vlan [IFNAME VLAN-ID | detail] [json]`, `debug zebra
  vxlan` (VxLAN/EVPN events), `debug zebra evpn mh <es|mac|neigh|nh>`.

### 1.7 Symmetric vs asymmetric IRB

FRR supports both (`#evpn` intro). Symmetric IRB = routed via the L3VNI
(tenant VRF ↔ L3VNI bound by `vni` under `vrf`; type-5 for prefixes, RMAC in
routes, "Interface-less IP-VRF-to-IP-VRF" per RFC 9136). Asymmetric IRB =
routing happens on the L2VNI's SVI at the ingress VTEP only (all L2VNIs must
exist on all VTEPs; the gateway-ip overlay-index feature is asymmetric-only).
The fedepaol walkthrough (§2) demonstrates L3VNI-only symmetric-style L3
EVPN; Bernat (§3) demonstrates pure L2 (no IRB at all).

### 1.8 Overlay/next-hop and VTEP-IP handling

The docs do not document an `evpn next-hop-unchanged` command (nor any
`next-hop-unchanged` knob) in current bgpd — with a directly connected eBGP
EVPN session the advertising VTEP is itself the next-hop, and `advertise-pip`
(§1.6) exists precisely to control which of system-IP vs anycast-IP is used
as the EVPN next-hop in MLAG/anycast setups. Next-hop handling in multi-hop
eBGP EVPN topologies (spine in the middle, same-AS leaves) is dealt with
operationally via `allowas-in` (see §2). No `next-hop-self`-style EVPN knob
is documented (gap, §6).

---

## 2. fedepaol — "L3EVPN using FRR and Linux vxlans" (2024-05-09)

Full fetch. First post of his EVPN series; lab repo referenced throughout
(`fedepaol/evpnlab` on GitHub). Topology: eBGP spine (AS 64612) with two
leaves (AS 64512, FRR 9.0.0 containers via containerlab), each leaf with one
host on an L3 leg (Host1 192.168.10.0/24, Host2 192.168.11.0/24). Goal:
connect the hosts across the fabric with **L3EVPN type-5 routes** over a VXLAN
tunnel (L3VNI 100), i.e. routed-only stretch, no L2 adjacency.

### 2.1 Linux/kernel setup per leaf (from his setup steps + FRR docs recap)

- VTEP IP on the **loopback** (100.64.0.1/100.65.0.2), IPs on the leaf↔spine
  and leaf↔host veths.
- A Linux **VRF** ("red") matching the tenant VRF, host-facing veth enslaved
  to it.
- The "EVPN/VXLAN machinery": one **bridge** (br100) + one **vxlan device**
  (vni100) per the FRR docs layout (see §1.5).
- Hosts get their /24 and a default route pointing at the leaf.

### 2.2 Leaf FRR configuration (verbatim from the post)

```
 address-family l2vpn evpn
  neighbor 192.168.1.0 activate
  neighbor 192.168.1.0 allowas-in origin
  advertise-all-vni
  advertise-svi-ip
 exit-address-family
```

("The difference [from the FRR docs] is where we allow the leaves to accept
routes coming from the local ASN (from the spine)") — `allowas-in` is needed
in **both** the `ipv4` and `l2vpn evpn` families: for the remote VTEP's
underlay route and for the other leaf's type-5 routes, since both leaves
share AS 64512 and the spine (AS 64612) is in the path. Tenant VRF:

```
router bgp 64512 vrf red
 !
 address-family ipv4 unicast
  redistribute connected
 exit-address-family
```

(`redistribute connected` so each leaf distributes the route toward its own
hosts.)

### 2.3 Spine FRR configuration (verbatim)

```
 neighbor 192.168.1.1 remote-as 64512
 neighbor 192.168.1.3 remote-as 64512

 address-family ipv4 unicast
  neighbor 192.168.1.1 activate
  neighbor 192.168.1.3 activate
 exit-address-family
 !
 address-family l2vpn evpn
  neighbor 192.168.1.1 activate
  neighbor 192.168.1.3 activate
  advertise-all-vni
  advertise-svi-ip
 exit-address-family
```

The spine is a pure pass-through: different AS from the leaves, so no route
reflection needed; it carries underlay routes to the VTEPs and EVPN routes
between leaves.

### 2.4 Verification sequence (verbatim outputs, abridged)

Underlay: `vtysh -c "show bgp ipv4"` shows the peer's loopback
`*> 100.65.0.2/32 ... 0 64612 64512 i` (and locally originated
`100.64.0.1/32`). L3VNI binding: `vtysh -c "show vrf vni"` →
`red  100  vni100  br100  Up  aa:bb:cc:00:00:65` (VNI 100, vxlan if, L3-SVI
bridge, RMAC). Session: `show bgp l2vpn evpn summary` → Established to the
spine, `PfxRcd 1`. EVPN RIB: `show bgp l2vpn evpn` shows the two type-5s:

```
Route Distinguisher: 192.168.10.2:2
 *> [5]:[0]:[24]:[192.168.10.0]
                    100.64.0.1               0         32768 ?
                    ET:8 RT:64512:100 Rmac:aa:bb:cc:00:00:65
Route Distinguisher: 192.168.11.2:2
 *> [5]:[0]:[24]:[192.168.11.0]
                    100.65.0.2                             0 64612 64512 ?
                    RT:64512:100 ET:8 Rmac:aa:bb:cc:00:00:64
```

(type-5 prefix `[5]:[0]:[24]:[prefix]`, next-hop = remote VTEP IP,
`RT:64512:100` auto-derived export RT — AS 64512 & 0xFFFF = 64512, local
admin = L3VNI 100 — plus `Rmac`.) Dataplane proof: ping Host2→Host1 works
(ttl=62); tcpdump on the leaf↔spine link shows
`IP 100.64.0.1.48561 > 100.65.0.2.4789: VXLAN, flags [I] (0x08), vni 100` —
underlay UDP/4789 between VTEP loopbacks carrying the inner ICMP.

### 2.5 Gotchas he hit (explicitly listed)

- **Same bridge MAC on both leaves** — having selected the same MAC address
  for the Linux bridge on both leaves broke things (uniqueness required; the
  docs' sample uses aa:bb:cc:00:00:64/65 per-leaf).
- **Missing `allowas-in` for the l2vpn address family** — routes from the
  sibling leaf (same AS) silently absent until allowed.
- General advice: when routes don't flow, **read the FRR logs** — "they
  offered the solution straight away the majority of the cases".
- No explicit kernel version requirement is stated anywhere in the post (the
  lab runs FRR 9.0.0 containers on the docker host kernel; gap, §6).

---

## 3. Bernat — "VXLAN & BGP EVPN" (2017, updated 2020-11)

Full fetch. The canonical host-VTEP design doc: hypervisors as VTEPs, Linux
bridges + per-VNI vxlan devices, BGP EVPN with route reflectors, Juniper vMX
interop. Everything below verbatim from the post unless noted.

### 3.1 Problem statement

VXLAN (RFC 7348) needs (1) VTEP discovery and (2) BUM-frame avoidance.
Multicast + source-address learning solve both but don't scale. **BGP EVPN**
(RFC 7432/8365) solves both over MP-BGP: **type-3 (IMET)** routes advertise
"which VNIs I'm interested in", **type-2 (MAC/IP)** routes advertise "which
MACs (and ARP/ND IPs) sit behind me" — plus MAC mobility and multihoming in
the general protocol. Advantages he cites: **interoperability** with other
vendors (Juniper, Cisco), proven **scalability** (millions of routes), and
**fine-grained policy**. FRR is "a fairly complete implementation of BGP
EVPN (type-3 routes for VTEP discovery, type-2 routes with MAC or IP
addresses, MAC mobility when a host changes from one VTEP to another one)
which requires very little configuration." (EVPN support added in FRR 4.0.)

### 3.2 Route reflector setup (FRR, verbatim)

```
router bgp 65000
  bgp router-id 203.0.113.254
  bgp cluster-id 203.0.113.254
  bgp log-neighbor-changes
  no bgp default ipv4-unicast
  neighbor fabric peer-group
  neighbor fabric remote-as 65000
  neighbor fabric capability extended-nexthop
  neighbor fabric update-source 203.0.113.254
  bgp listen range 203.0.113.0/24 peer-group fabric
  !
  address-family l2vpn evpn
   neighbor fabric activate
   neighbor fabric route-reflector-client
  exit-address-family
```

Dynamic neighbors (`bgp listen range`) mean no per-VTEP neighbor config; the
RR can run `bgpd --no_kernel` (no zebra). **2018-04 caveat**: for
multi-vendor interop "it is safer to **not** use FRR as a route reflector:
it may mangle the received routes." Alternatives shown: GoBGP (config
verbatim in post) and Juniper Junos (`family evpn signaling no-install`).

### 3.3 VTEP setup (verbatim)

Per-VNI traditional vxlan device + bridge, `nolearning` because the control
plane syncs FDBs:

```
for vni in 100 200; do
    # Create VXLAN interface
    ip link add vxlan${vni} type vxlan \
        id ${vni} \
        dstport 4789 \
        local 203.0.113.2 \
        nolearning
    # Create companion bridge
    brctl addbr br${vni}
    brctl addif br${vni} vxlan${vni}
    brctl stp br${vni} off
    ip link set up dev br${vni}
    ip link set up dev vxlan${vni}
done
# Attach each VM to the appropriate segment
brctl addif br100 vnet10
brctl addif br100 vnet11
brctl addif br200 vnet12
```

FRR on the VTEP (verbatim) — plain iBGP to two RRs, EVPN AF, no VRF, no SVI
IPs (pure L2 stretch):

```
router bgp 65000
  bgp router-id 203.0.113.2
  no bgp default ipv4-unicast
  neighbor fabric peer-group
  neighbor fabric remote-as 65000
  neighbor fabric capability extended-nexthop
  neighbor 203.0.113.253 peer-group fabric
  neighbor 203.0.113.254 peer-group fabric
  !
  address-family l2vpn evpn
   neighbor fabric activate
   advertise-all-vni
  exit-address-family
```

### 3.4 Verification (his sequence, verbatim commands + outputs)

1. Kernel↔FRR: `show interface vxlan100` — "VNI is 100; the bridge device
   was correctly detected" (`Master (bridge) ifindex ...`).
2. Local MACs: `show evpn mac vni 100` lists `local  eth1.100` entries.
3. Sessions: `show bgp neighbors 203.0.113.254` — `BGP state =
   Established`, `Address family L2VPN EVPN: advertised and received`, prefix
   counts.
4. Sent routes (checked on the RR/Junos): one type-3 per VNI, one type-2 per
   local MAC — Junos form `3:203.0.113.2:100::0::203.0.113.2/304 IM` with
   `Communities: target:65000:268435556 encapsulation:vxlan(0x8)` and
   `2:...::50:54:33:00:00:0a/304 MAC/IP ... Route Label: 100 ESI:
   00:00:00:00:00:00:00:00:00:00`. (FRR RD auto-derived `vtep-ip:vni`; FRR
   `show bgp l2vpn evpn route` shows the same table.)
5. Received → kernel: `show evpn vni` (remote VTEPs per VNI),
   `show evpn mac vni 100` (remote MACs), and the dataplane check
   `bridge fdb show dev vxlan100 | grep dst`:
   ```
   00:00:00:00:00:00 dst 203.0.113.1 self permanent
   00:00:00:00:00:00 dst 203.0.113.3 self permanent
   50:54:33:00:00:0c dst 203.0.113.3 self
   50:54:33:00:00:09 dst 203.0.113.1 self
   ```
   — the all-zeros FDB entries (from type-3) are the BUM replication list;
   the MAC entries (from type-2) are unicast destinations.
6. Interop: Juniper vMX 16.1R1.7 as VTEP works against FRR VTEPs; Junos
   differences — static RD configured (`route-distinguisher 203.0.113.3:1`)
   vs FRR auto, VNI also encoded as Ethernet tag ID, `vrf-target target:
   65000:1 auto`, `multicast-mode ingress-replication`.

### 3.5 Conclusions from the post

- Running BGP EVPN VTEPs on plain Linux hosts works and interops with
  datacenter gear; the host side is "very little configuration" in FRR plus
  per-VNI bridge+vxlan plumbing.
- Without EVPN, VXLAN on Linux is flood-and-learn over multicast — works but
  doesn't scale and needs multicast in the underlay.
- Multihoming note (2018/2020 updates): in 2017 FRR ignored remote
  multihomed segments; **initial EVPN multihoming support landed in FRR 7.5**
  ("wait a couple of releases for the feature set to be complete").

---

## 4. ipSpace collection — "Worth Reading: EVPN/VXLAN with FRR on Linux Hosts" (2022-10-01)

The index post itself is a short pointer; checked live **and** via
web.archive.org (2024-04-11 snapshot) — in both versions it links exactly
**one** external article (the Van Bemmel piece below). To cover the "4–8 most
relevant linked articles" intent, the table also includes the direct
follow-ups in the same series/sidebar that this note fetched in full.

| # | Article | Author / URL | What it demonstrates | Key takeaway |
|---|---------|--------------|----------------------|--------------|
| 1 | "Revisiting BGP EVPN VXLAN to the hosts with SR Linux 22.6.3" (2022-09-27) | Jeroen Van Bemmel — <https://srlinux-at-your-service.medium.com/revisiting-bgp-evpn-vxlan-to-the-hosts-with-sr-linux-22-6-3-586df95f730c> (fetched via web.archive.org; Medium live rate-limited) | THE article the ipspace post points at. netlab 1.3.1 + FRR 8.3.1 containerlab topology `integration/evpn/vxlan-routing-ibgp-over-ebgp-unnumbered.yml`: ~80 lines of YAML build tenant-isolated VRFs, routed VXLAN with EVPN control plane in **symmetric IRB** (RT5 + transit l3vni), iBGP-over-eBGP with RFC 8950 v6-only next hops on link-local. | Multi-vendor interop is a one-flag change (`-s nodes.r2.device=srlinux` — SR Linux vs FRR); netlab templates absorb per-vendor EVPN RT syntax/auto-derivation differences. Underlay uses /32 loopback host routes + ECMP + `allowas-in` (all FRR nodes share one underlay AS). FRR VRF route leaking done with tags + asymmetric import/export (hub-spoke "Internet" VRF) — "somewhat uncommon and experimental, YMMV". **Gotcha**: with distributed subnets, ARP to a *silent* host only works when the IRB has an **anycast gateway IP** — without anycast support, the host must generate a packet first. |
| 2 | "L3EVPN using FRR and Linux vxlans" (2024-05-09) | Federico Paoletti — see §2 | Plain-Linux L3 EVPN (type-5) spine-leaf with containerlab. | `allowas-in origin` in **both** AFs for same-AS leaves behind an eBGP spine; unique bridge MAC per VTEP; `show vrf vni`/`show bgp l2vpn evpn` verify RMAC + `RT:ASN:L3VNI`. |
| 3 | "L2EVPN using FRR and Linux vxlans" (2024-05-17) | Federico Paoletti — <https://fedepaol.github.io/blog/2024/05/17/l2evpn-using-frr-and-linux-vxlans/> | L2-only stretch: host veths enslaved directly to the leaf bridge; **L2VNI 110 ≠ L3VNI 100** (bridge has no IP in pure-L2 mode); still maps into VRF "red" in FRR. | Mechanics visible in the kernel: remote MACs appear as `bridge fdb` entries on `vni110` marked `extern_learn` with `dst 100.64.0.1` — zebra translates BGP type-2 into FDB. Type-2 route format `*> [2]:[0]:[48]:[aa:c1:ab:99:2a:66] ... RT:64512:110 ET:8` (IP-less when only the MAC is known). `show evpn mac vni all` shows local vs remote. |
| 4 | "Some notes about ARP suppression in L2EVPN using FRR and Linux vxlans" (2024-05-21) | Federico Paoletti — <https://fedepaol.github.io/blog/2024/05/21/some-notes-about-arp-suppression-in-l2evpn-using-frr-and-linux-vxlans/> | Why `neigh_suppress` alone doesn't suppress ARP on plain Linux. | Type-2 routes carry an IP **only if the originating leaf's kernel neighbor table has MAC+IP for the host** — zebra fills the IP from the local neigh table. In pure-L2 setups the ARP reply is unicast to the host, so the leaf's neigh table never learns it, IP is missing from type-2, and remote `neigh_suppress` has nothing to proxy. Fix/workaround: ping from the SVI to populate neigh (Cumulus used `neighmgrd` to force entries); verify via `ip neigh ... extern_learn NOARP proto zebra` on the remote leaf. |
| 5 | "Worth Reading: More VXLAN and EVPN Labs" (2026-07-06) | Ivan Pepelnjak — <https://blog.ipspace.net/2026/07/worth-reading-more-vxlan-evpn/> | Points at Ali Bahadır Coşkun's completion of the free netlab EVPN/VXLAN lab track: basic EVPN control plane over a VXLAN underlay, then the VXLAN/IRB/anycast saga. | The netlab EVPN lab suite (six VXLAN + ~a dozen EVPN labs) is the canonical self-study path for these configs; validates that the FRR-on-Linux patterns above are reproducible exercise material. |
| 6 | "VXLAN & BGP EVPN" (2017) | Vincent Bernat — see §3 | The foundation article the whole collection keeps referring back to (host VTEPs + RR + Junos interop). | Type-3 ⇒ BUM FDB list, type-2 ⇒ unicast FDB entries (`bridge fdb show` as the dataplane truth); FRR RR caveat (may mangle routes multi-vendor); multihoming only since FRR 7.5. |

Also part of fedepaol's series (titles from his sitemap, not fetched — listed
for follow-up): "Fixing ARP suppression in Linux L2EVPN with eBPF"
(2024-06-01), "Extending the Kubernetes host network with EVPN tunnels and
FRR" (2024-06-14), "Running EVPN termination inside a Kubernetes pod"
(2024-11-10), "Enabling EVPN termination with Podman pods as systemd units"
(2025-01-06).

### What the collection teaches about EVPN on Unix hosts

First, the control plane is the easy part: every article converges on the
same ~15 lines of FRR (`advertise-all-vni`, neighbor `activate` under
`l2vpn evpn`, `vrf X / vni N`, `advertise ipv4 unicast`) — the differentiation
is entirely in the **kernel dataplane contract** (one bridge + one `nolearning`
vxlan per VNI, `neigh_suppress` semantics, unique bridge MACs, VRF enslaving)
and in **operational details nobody documents**: `allowas-in` for same-AS
leaves behind an eBGP spine, RT auto-derivation behavior across vendors,
bridge-MAC uniqueness, and the neighbor-table dependency for ARP suppression.
Second, the workflow matured from hand-built configs (Bernat 2017, brctl era)
to **declarative labs** (containerlab, then netlab with multi-vendor device
templates) — today the fastest path to a correct config is generating it from
netlab's FRR templates and reading what it emits. Third, EVPN-on-Linux
interops both ways with "real" NOSes (Junos vMX in 2017, SR Linux 22.6 in
2022) as long as RT/RD conventions are pinned down — the same property that
makes it useful as a leaf/VTEP on NixOS hosts attached to vendor fabrics.

---

## 5. EVPN on NixOS with FRR — practical synthesis

### 5.1 Kernel pieces (all present on stock NixOS; verified on this host)

NixOS kernel 6.18.50, `/proc/config.gz` + module tree:

| Feature | Config | Module | Used for |
|---------|--------|--------|----------|
| VXLAN device | `CONFIG_VXLAN=m` | `vxlan.ko` | VTEP encap/decap (UDP 4789) |
| Bridge | `CONFIG_BRIDGE=m`, `CONFIG_BRIDGE_VLAN_FILTERING=y` | `bridge` | MAC-VRF broadcast domain; VLAN-aware (SVD) mode available |
| VRF (l3mdev) | `CONFIG_NET_VRF=m`, `CONFIG_NET_L3_MASTER_DEV=y` | `vrf.ko` | IP-VRF routing tables for L3 EVPN |
| 802.1Q / MACVLAN | `CONFIG_VLAN_8021Q=m`, `CONFIG_MACVLAN=m` | — | trunk subifs; anycast-gateway macvlan pattern |

All in-tree, shipped as modules in the default NixOS kernel — **no custom
kernel config required**. Userspace tooling: `iproute2` (`ip link add ... type
vxlan|vrf|bridge`, `bridge vlan/vni/fdb`) is in the base system closure.
Minimum-kernel-version notes from the docs/features used above: `vxlan
external` (SVD) needs `VXLAN_F_COLLECT_METADATA` (≥4.9 era, commit
ee122c79d4), `vnifilter` ≥5.15 (commit f9c4bb0b24); `neigh_suppress` per-port
is a 4.16+ bridge_slave attribute. Any current NixOS kernel is far past all
of these.

### 5.2 FRR package EVPN availability (nixpkgs nixos-unstable)

`pkgs/by-name/fr/frr/package.nix`, FRR **10.7.1**: `bgpdSupport ? true`,
`bgpVnc ? true`, `bgpAnnounce ? true`, `bgpBmp ? true` — and **no EVPN-related
configure flag exists at all** (zero occurrences of "evpn" in the package; the
only `--disable-*` flag is `--disable-zeromq`). EVPN (`l2vpn evpn` AF) is a
core, unconditional bgpd capability — if `bgpd` is built (default), EVPN is
in. The NixOS module (`nixos/modules/services/networking/frr.nix`) toggles
daemons (`services.frr.bgpd.enable`, `bfdd.enable`, …) and takes a freeform
`services.frr.config` that becomes `/etc/frr/frr.conf` under
`service integrated-vtysh-config` — so EVPN stanzas drop in verbatim.

### 5.3 Minimal end-to-end sketch — two VTEPs, one L2 VNI, one L3 VRF

Topology: VTEP-A (AS 65001, loopback/VTEP-IP 10.0.0.1/32) and VTEP-B (AS
65002, 10.0.0.2/32), direct underlay eBGP on their interconnect link; L2VNI 110
(192.168.10.0/24, bridged to a local access port each side) + tenant VRF
`red` with L3VNI 100 for type-5 routing. Auto RTs make this work with zero
manual RT config: exports are `65001:110`/`65002:110` etc., wildcard imports
`*:110`/`*:100` match both sides (§1.2).

Kernel side (per VTEP; run from a systemd oneshot / networkd `ExecPost` —
bridge_slave attrs need iproute2, they are not expressible in plain
.network/.netdev files):

```bash
ip addr add 10.0.0.1/32 dev lo                     # VTEP-IP on lo
ip link add red type vrf table 1001 && ip link set red up
# L2VNI 110 with IRB SVI
ip link add br10 type bridge
ip link set br10 master red addrgenmode none
ip link set br10 addr aa:bb:cc:00:00:64            # UNIQUE per VTEP
ip addr add 192.168.10.1/24 dev br10               # shared subnet gateway
ip link add vni110 type vxlan local 10.0.0.1 dstport 4789 id 110 nolearning
ip link set vni110 master br10 addrgenmode none
ip link set vni110 type bridge_slave neigh_suppress on learning off
ip link set vni110 up && ip link set br10 up
# L3VNI 100 (no IP on the L3-SVI)
ip link add br100 type bridge
ip link set br100 master red addrgenmode none
ip link set br100 addr aa:bb:cc:00:00:65
ip link add vni100 type vxlan local 10.0.0.1 dstport 4789 id 100 nolearning
ip link set vni100 master br100 addrgenmode none
ip link set vni100 type bridge_slave neigh_suppress on learning off
ip link set vni100 up && ip link set br100 up
# local access port into the L2VNI
ip link set eth1 master br10
```

FRR side (`services.frr.config`, same shape on both VTEPs):

```
vrf red
 vni 100
exit-vrf
!
router bgp 65001
 neighbor 192.168.0.2 remote-as external
 !
 address-family ipv4 unicast
  network 10.0.0.1/32
 exit-address-family
 !
 address-family l2vpn evpn
  neighbor 192.168.0.2 activate
  advertise-all-vni
  advertise-svi-ip
 exit-address-family
!
router bgp 65001 vrf red
 !
 address-family ipv4 unicast
  redistribute connected
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast
 exit-address-family
```

(VTEP-B mirrors with AS 65002, VTEP-IP 10.0.0.2, peer 192.168.0.1.) If a
spine sits between same-AS leaves, add `neighbor <spine> allowas-in origin`
in **both** address families (§2.5); with a spine of a different AS, no RR is
needed (§2.3), or use iBGP to RRs per §3.2.

### 5.4 Verification path (doc-cited commands, §1.6)

1. `vtysh -c "show bgp l2vpn evpn summary"` — EVPN session Established,
   prefixes exchanged.
2. `vtysh -c "show bgp l2vpn evpn route"` — expect type-2 (`[2]:[0]:[48]:...`
   + `[32]:[ip]` once neigh is populated), type-3 `[3]:[0]:[32]:[vtep]`, type-5
   `[5]:[0]:[24]:[prefix]` with `RT:<as>:<vni> Rmac:<rmac>`; filter with
   `[type macip|multicast|prefix]` and `[json]`.
3. `vtysh -c "show evpn vni"` / `show vrf vni` — L2VNI↔vxlan-if↔remote-VTEP
   list; L3VNI↔VRF↔Rmac state (L3VNIs show `State Up` + RMAC here).
4. `vtysh -c "show evpn mac vni 110"` and `show evpn arp-cache vni 110` —
   local vs remote MAC/neigh (`extern_learn` kernel entries fed by zebra).
5. `bridge fdb show dev vni110` — all-zeros `dst <vtep>` entries = BUM list
   (type-3); per-MAC `dst <vtep>` = type-2 unicast.
6. Dataplane: ping across; `tcpdump -i <uplink>` should show only
   `IP <vtepA> > <vtepB>.4789: VXLAN, vni <N>` — no cleartext inner traffic,
   no flooded ARP once suppression is effective.

### 5.5 When to choose EVPN vs the skill's plain eBGP site routing

Choose **EVPN-VXLAN** when: you need **L2 stretch** across sites/hosts
(same subnet on two VTEPs, MAC mobility), a **large multi-tenant fabric**
(many tenant VRFs/L2VNIs with per-EVI policy via RTs, wildcard `*:VNI` import
scaling to per-leaf ASNs), or **anycast gateways**/distributed IRB (same SVI
IP+MAC everywhere, symmetric IRB over an L3VNI, ARP suppression). Choose the
skill's existing **plain eBGP site mesh** (loopback /32s, unicast underlay,
BFD/GR) when: all you need is routed reachability between sites — L2
extension buys nothing there and EVPN adds real operational surface (the
kernel dataplane contract of §1.3–§1.5, neighbor-table coupling for ARP
suppression of §4 #4, bridge-MAC/RT hygiene). A pragmatic middle path used by
both fedepaol and Van Bemmel: EVPN only on the fabric legs that need
stretch, plain eBGP everywhere else, and let the EVPN anycast gateway ARP
caveat (silent hosts, §4 #1) inform whether IRB is symmetric or centralized.

---

## 6. Fetch gaps

- **`evpn.html` fully fetched** — the page genuinely ends at
  `#displaying-evpn-information` (`show evpn mac vni`, `show vrf vni` only);
  anchors verified against raw HTML. `show evpn vni [detail]` and
  `show evpn arp-cache vni X` (used by Bernat/fedepaol and in §5.4) are
  **runtime commands not documented in current doc chapters** (zebra chapter
  covers only `show evpn access-vlan` + `debug zebra vxlan/evpn mh`).
- **Per-EVI knobs partially documented**: the `vni N` sub-context under the
  EVPN AF (with `route-target`/`exit-vni`) appears only in the bgp.html
  example, not as a dedicated command entry; same for `advertise-default-gw`
  (one passing mention: incompatible with `advertise-svi-ip`) and the old
  `rd auto` spelling (gone from current docs — RDs are auto-derived
  `vtep-ip:vni`, visible in outputs).
- **No `evpn next-hop-unchanged`** (nor any `next-hop-unchanged`) exists in
  current bgpd docs; overlay next-hop behavior is only covered implicitly via
  `advertise-pip` (§1.6). Historical command from older FRR releases; not
  verified against source.
- **Multihoming**: standalone `evpn-multihoming.html` returns RTD 404; the
  MH command set documented in §1.6 (bgp.html) is all that current docs
  carry. ES-bond dataplane requirements on NixOS (LACP bonds, protodown) not
  researched.
- **fedepaol's kernel version requirements**: never stated numerically in
  the L3/L2 posts (FRR 9.0.0 containers; host kernel whatever docker used).
  The 4.x-era `neigh_suppress`/SVD constraints in §5.1 are from the FRR docs'
  kernel-commit references, not from his posts.
- **ipspace index links only one article** (live page and 2024-04-11 Wayback
  snapshot agree); §4's table supplements with the directly-linked series
  follow-ups/sidebar items. Van Bemmel's Medium piece fetched via
  web.archive.org after the live URL returned HTTP 429 — archived copy
  complete (code blocks intact).
- **Bernat's `brctl` (bridge-utils) idioms are 2017-era**; modern equivalent
  is `ip link add name brX type bridge` + `ip link set dev vxlanX master brX`.
  His FRR-RR "may mangle routes" caveat is 2018-era; not re-validated on FRR
  10.x.
- NixOS packaging facts (§5.1–§5.2) verified against nixos-unstable
  2026-10-24 and this host's running kernel; the NixOS module check was
  read-only — no EVPN config was deployed or tested end-to-end on a NixOS
  host.
