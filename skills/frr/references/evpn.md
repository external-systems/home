# EVPN-VXLAN with FRR

How FRR builds EVPN-VXLAN overlays on Linux/NixOS hosts: L2 stretch
(MAC-VRF), L3 EVPN (IP-VRF, type-5 routes, IRB), and the kernel
dataplane contract that actually makes it work. Verbatim configs and
per-source detail:
[research/evpn-vxlan.md](research/evpn-vxlan.md). FRR docs:
[evpn.html](https://docs.frrouting.org/en/latest/evpn.html) +
[bgp.html](https://docs.frrouting.org/en/latest/bgp.html) EVPN sections.

## Concepts in one minute

- EVPN (RFC 7432) is BGP signaling for VPNs over VXLAN (RFC 8365).
  FRR speaks `address-family l2vpn evpn` and supports **type-2**
  (MAC/IP), **type-3** (IMET — "which VNIs am I in", builds the BUM
  replication list), **type-5** (IP prefixes — L3 EVPN), type-1
  (Ethernet A/D, multihoming), and both **symmetric and asymmetric IRB**.
- A VNI is either **L2** (bound to a MAC-VRF = a Linux bridge) or **L3**
  (bound to an IP-VRF = a Linux VRF routing table). An L2VNI's tenant
  VRF is inferred from its SVI's VRF membership — no SVI ⇒ default VRF.
- **Route Targets identify EVIs/IP-VRFs, never labels.** The VNI in a
  route is pure dataplane information; a **RT mismatch shows up as
  missing routes**, a label problem as imported routes whose traffic is
  dropped. This one rule explains most EVPN failures.

## NixOS readiness (verified, no customization needed)

- Kernel: `CONFIG_VXLAN`, `CONFIG_BRIDGE` (+VLAN filtering), `CONFIG_NET_VRF`,
  8021q, macvlan are stock modules on the default NixOS kernel (checked
  on 6.18.50). `vxlan external` (SVD) needs ≥4.9-era, `vnifilter` ≥5.15,
  per-port `neigh_suppress` ≥4.16 — any current kernel is past all of
  these.
- Package: nixpkgs FRR 10.7.1 has **EVPN unconditionally compiled into
  bgpd** — no configure flag, nothing to enable beyond
  `services.frr.bgpd.enable = true`.
- Tooling: `iproute2` plumbing is not expressible in plain
  systemd-networkd `.netdev` files (bridge_slave attributes,
  `bridge vlan tunnel_info`) — run it from a oneshot/ExecPost script.

## The dataplane contract (where the real work is)

Two models (FRR manages neither — netlink learns what exists):

- **Traditional**: one bridge + one vxlan device per VNI, `nolearning`
  (remote VTEPs come from BGP, not flood-and-learn), `neigh_suppress on`
  + `learning off` on the bridge_slave. L2VNI with IRB SVI and L3VNI:

  ```bash
  ip addr add 10.0.0.1/32 dev lo                     # VTEP-IP on lo
  ip link add red type vrf table 1001 && ip link set red up
  # L2VNI 110 with SVI (IRB gateway)
  ip link add br10 type bridge
  ip link set br10 master red addrgenmode none
  ip link set br10 addr aa:bb:cc:00:00:64            # UNIQUE per VTEP
  ip addr add 192.168.10.1/24 dev br10
  ip link add vni110 type vxlan local 10.0.0.1 dstport 4789 id 110 nolearning
  ip link set vni110 master br10 addrgenmode none
  ip link set vni110 type bridge_slave neigh_suppress on learning off
  ip link set vni110 up && ip link set br10 up
  # L3VNI 100: an L3-SVI MUST exist and must NOT have any IP
  ip link add br100 type bridge
  ip link set br100 master red addrgenmode none
  ip link set br100 addr aa:bb:cc:00:00:65
  ip link add vni100 type vxlan local 10.0.0.1 dstport 4789 id 100 nolearning
  ip link set vni100 master br100 addrgenmode none
  ip link set vni100 type bridge_slave neigh_suppress on learning off
  ip link set vni100 up && ip link set br100 up
  ```

- **SVD (single vxlan device, `external` flag)**: one multi-VNI vxlan
  per UDP port carrying all VNIs into a VLAN-aware bridge; needs
  per-VNI `bridge vlan add ... tunnel_info id <vni>` mappings, a unique
  **routermac** per VTEP, and enables anycast gateways (same gateway
  MAC+IP per L2VNI on all VTEPs via macvlan; critically
  `bridge fdb add <anycast-mac> dev br0 self local`). The docs call SVD
  "recommended for most EVPN deployments".

VTEP-IP lives on `lo` and must be reachable by other VTEPs (advertise
the /32 in the underlay — any IGP/BGP works).

## FRR config

Underlay BGP instance carries the EVPN AF; a per-VRF instance originates
type-5s:

```
vrf red
 vni 100                     ! gives the VRF its L3VNI
exit-vrf
!
router bgp 65001
 neighbor 192.168.0.2 remote-as external
 !
 address-family ipv4 unicast
  network 10.0.0.1/32        ! VTEP reachability
 exit-address-family
 !
 address-family l2vpn evpn
  neighbor 192.168.0.2 activate
  advertise-all-vni          ! mandatory; enables EVPN + defines underlay VRF
  advertise-svi-ip           ! self type-2s for SVI MAC/IP (don't combine
                             ! with advertise-default-gw)
 exit-address-family
!
router bgp 65001 vrf red
 !
 address-family ipv4 unicast
  redistribute connected
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast     ! export VRF RIB as type-5 (opts: [gateway-ip]
                             ! [route-map R] [skip-evpn-imported])
 exit-address-family
```

- **Route targets need zero manual config in multi-AS fabrics**: auto
  import = wildcard `*:VNI`, auto export = `(AS&0xFFFF):VNI`. Wildcard
  `*:N` matches any peer's `ASN:VNI` — that's how per-leaf-AS eBGP
  fabrics scale. Manual control: `route-target import|export ...` at
  the VRF level (IP-VRF, attaches to type-2/5) or under `vni N` inside
  the EVPN AF (per-EVI, type-2/3); `auto-route-target
  <import|export|both> <add-always|add-never|add-if-no-manual|rfc8365-compatible>`.
- RDs are auto-derived `vtep-ip:vni`.
- BUM: floods head-end-replication by default; `flooding
  <disable|head-end-replication>` globally or per `vni`.
- `advertise-pip` (default on) controls system-IP vs anycast-IP as the
  EVPN next-hop in MLAG setups; **downstream VNI** (egress dictates the
  VNI, label2) requires the SVD dataplane.
- There is **no `next-hop-unchanged` for EVPN** in current FRR — with a
  directly connected eBGP EVPN session the VTEP is the next-hop; in
  multi-hop topologies fix reachability with `allowas-in` (below).
- EVPN multihoming (ESI, `evpn mh es-id/es-sysmac`, EAD routes, DF
  election, MAC-ECMP) exists since FRR 7.5 and is the documented
  replacement for MLAG/anycast VTEPs — see the research note §1.6.

## Fabric designs

- **eBGP spine of a different AS between same-AS leaves**: spine is a
  pure pass-through (carries underlay + `l2vpn evpn` between leaves,
  no reflection needed). Leaves need `neighbor <spine> allowas-in
  origin` in **both** the `ipv4` and `l2vpn evpn` families, or the
  sibling leaf's routes silently never arrive (fedepaol's gotcha).
- **iBGP fabric**: use route reflectors with a listen range —
  `bgp listen range <vtep-subnet> peer-group fabric`, EVPN AF with
  `neighbor fabric route-reflector-client`, `capability extended-nexthop`,
  RR can run `bgpd --no_kernel` (no zebra). Bernat's 2018 caveat: for
  multi-vendor interop prefer a vendor RR or GoBGP — FRR RR "may mangle
  received routes" (not re-validated on 10.x).
- **Interops both ways**: Junos vMX (2017) and SR Linux 22.6 (2022)
  both verified against FRR VTEPs; netlab generates correct multi-vendor
  configs (~80 lines of YAML for symmetric IRB + RFC 8950 unnumbered).

## Gotchas that actually happen

- **Duplicate bridge MACs across VTEPs** break forwarding — keep the
  per-VTEP bridge MAC unique (e.g. `aa:bb:cc:00:00:6X`).
- **`allowas-in` missing in one AF** (usually forgotten under
  `l2vpn evpn`) = remote type-5s absent while underlay looks fine.
- **ARP suppression needs IP in type-2, which needs the local neighbor
  table**: zebra takes the IP from the leaf's kernel neigh entry. In
  pure-L2 setups the ARP reply is unicast and never populates it, so
  type-2 routes go out MAC-only and remote `neigh_suppress` has nothing
  to proxy. Populate by pinging from the SVI, or accept flooding.
- **Silent hosts + distributed subnets**: ARP to a silent host only
  resolves when the IRB has an **anycast gateway IP** — without one,
  the host must generate traffic first.
- **RT debugging**: missing route ⇒ check RT import/export (targets,
  not VNIs); traffic blackholed on imported routes ⇒ check the VNI/
  label side (dataplane).
- Logs first: fedepaol's advice — when routes don't flow, read
  `journalctl -u frr`; the logs usually say why.

## Verification path

1. `vtysh -c "show bgp l2vpn evpn summary"` — session up, prefixes
   exchanged (`[json]` for scripts).
2. `vtysh -c "show bgp l2vpn evpn route"` — type-2 `[2]:[0]:[48]:[mac]`
   (+`[32]:[ip]`), type-3 `[3]:[0]:[32]:[vtep]`, type-5
   `[5]:[0]:[24]:[prefix]` with `RT:<as>:<vni> Rmac:<rmac>`; filter
   `[type macip|multicast|prefix]` / `[detail]`.
3. `vtysh -c "show vrf vni"` / `show evpn vni` — L3VNI↔VRF↔RMAC state,
   remote VTEP lists per VNI.
4. `vtysh -c "show evpn mac vni 110"` / `show evpn arp-cache vni 110` —
   local vs remote (`extern_learn`) entries; `show evpn vni <N>`
   confirms zebra<->kernel agreement.
5. `bridge fdb show dev vni110` — all-zeros `dst <vtep>` = BUM list
   (type-3); per-MAC `dst <vtep>` = type-2 unicast. This is the
   dataplane truth.
6. Dataplane: ping across the overlay; `tcpdump -i <uplink>` shows only
   `IP <vtepA> > <vtepB>.4789: VXLAN, vni <N>`.

## When to choose EVPN (and when not)

Choose **EVPN-VXLAN** for: L2 stretch across hosts/sites (MAC
mobility), large multi-tenant fabrics (per-EVI policy via RTs, wildcard
imports scaling to per-leaf ASNs), anycast gateways / distributed IRB
(symmetric routing over an L3VNI, ARP suppression).

Stay with the skill's **plain eBGP site mesh** (loopbacks, unicast
underlay, BFD/GR) when routed reachability between sites is all you
need — L2 extension buys nothing there, and EVPN adds real operational
surface (the kernel dataplane contract, neigh-table coupling, RT
hygiene). Middle path proven in the field: EVPN only on legs that need
stretch, plain eBGP everywhere else.

For k8s specifically: Cilium's BGP control plane advertises pod CIDRs /
LB VIPs but does not do EVPN; the node-local-FRR pattern
([cilium.md](cilium.md)) can peer with an EVPN fabric like any other
BGP speaker — see fedepaol's "Extending the Kubernetes host network
with EVPN tunnels and FRR" in the research note §4 for a worked example.
