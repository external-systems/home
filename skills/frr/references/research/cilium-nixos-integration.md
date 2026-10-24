# FRR × Cilium BGP Control Plane × NixOS — integration research

Research date: 2026-10-24. Cilium baseline pinned to **v1.20** (this repo's
Cilium version); nixpkgs baseline **nixos-unstable** (module + package fetched
from `NixOS/nixpkgs@nixos-unstable` on 2026-10-24).

Primary sources:

- Cilium v1.20 docs (canonical RST sources from `cilium/cilium@v1.20`, rendered
  at <https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane>)
- <https://github.com/denizaydin/cilium-containerlab-bgp-multihoming> `main`,
  `v2-node-local-frr/` (fetched 2026-10-24)
- <https://blog.bella.network/internal-bgp-with-wireguard/> (fetched 2026-10-24)
- NixOS `services.frr` module + `pkgs.frr`:
  <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/frr.nix>,
  <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/fr/frr/package.nix>

---

## 1. Cilium BGP Control Plane (v1.20)

Source: `Documentation/network/bgp-control-plane/*.rst` @ v1.20
(<https://github.com/cilium/cilium/tree/v1.20/Documentation/network/bgp-control-plane>).
Rendered index: <https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane>

### 1.1 What it is / how the agent works

- "BGP Control Plane provides a way for Cilium to advertise routes to
  connected routers by using BGP. BGP Control Plane makes Pod networks and/or
  Services reachable from outside the cluster ... Because BGP Control Plane
  does not program the datapath, do not use it to establish reachability
  within the cluster." It is an **advertisement-only** control plane; the
  datapath (tunnel/native routing) is configured separately.
- Enabled with Helm value `bgpControlPlane.enabled=true` followed by
  `kubectl -n kube-system rollout restart ds/cilium`.
- Implementation: a **per-node BGP manager embedded in the Cilium agent**,
  built on **GoBGP** (visible in agent logs:
  `component=gobgp.BgpServerInstance subsys=bgp-control-plane`). The operator
  translates cluster-wide CRDs into a per-node
  `CiliumBGPNodeConfig`; the agent on each selected node instantiates the BGP
  instance(s), dials the configured peers, and injects/advertises routes.
- Address-family restriction: "the BGP Control Plane can only advertise the
  route of the address family that the Cilium is configured to use. You cannot
  advertise IPv4 routes when the Cilium Agent is configured to use only IPv6
  address family" (and vice versa). Single-stack and dual-stack are supported.
- Session direction: "By default, the BGP Control Plane instantiates each
  router instance **without a listening port**. This means the BGP router can
  only initiate connections to the configured peers, but cannot accept
  incoming connections. This is the default behavior because the BGP Control
  Plane is designed to function in environments where another BGP router
  (such as Bird) is running on the same node. When it is required to accept
  incoming connections, the `localPort` field can be used." Listening on port
  179 requires granting `CAP_NET_BIND_SERVICE` via the Helm value
  `securityContext.capabilities.ciliumAgent`.

### 1.2 The v2 API resources

From `bgp-control-plane-configuration.rst`:

- **`CiliumBGPClusterConfig`** (cluster-wide): selects nodes via
  `spec.nodeSelector`; defines one or more `bgpInstances`, each with a unique
  `name`, a `localASN`, an optional `localPort`, and a list of `peers`. Each
  peer has a unique `name`, `peerASN`, `peerAddress`, and a
  `peerConfigRef` (reference to a `CiliumBGPPeerConfig`; `group`/`kind`
  optional, default `cilium.io`/`CiliumBGPPeerConfig`).
- **`CiliumBGPPeerConfig`** (per-peer, reusable across many peers):
  `timers` (`connectRetryTimeSeconds` default 120, `holdTimeSeconds` default
  90, `keepAliveTimeSeconds` default 30), `authSecretRef` (RFC 2385 TCP-MD5,
  secret in the BGP secrets namespace — `kube-system` by default, key name
  `password`), `ebgpMultihop` (TTL), `gracefulRestart`
  (`enabled`, `restartTimeSeconds` default 120), `transport`
  (`peerPort`, `sourceInterface`), and `families` (list of
  `{afi, safi}` — only `ipv4/unicast` and `ipv6/unicast` — each with an
  `advertisements.matchLabels` selector).
  "Without matching advertisements, no prefix will be advertised to the peer.
  Default configuration is to not advertise any prefix." If `families` is
  omitted entirely, both MP-BGP capabilities (RFC 4760) are announced but
  nothing is advertised.
- **`CiliumBGPAdvertisement`**: matched by the peer config's
  `families[].advertisements.matchLabels`. `spec.advertisements[]` supports
  three `advertisementType`s:
  - `PodCIDR` — the pod CIDR **allocated to the local node** (Kubernetes /
    ClusterPool IPAM). With MultiPool IPAM use `CiliumPodIPPool` + a selector
    on `CiliumPodIPPool` resources instead. Other IPAM types: no PodCIDR
    advertisement.
  - `Service` — advertises exact /32 / /128 VIP routes from
    `service.addresses: [LoadBalancerIP, ClusterIP, ExternalIP]` for Services
    matching `service.selector`. Honors `externalTrafficPolicy` /
    `internalTrafficPolicy`: with `Local`, the VIP is only advertised from
    nodes with a local backend. Optional `aggregationLengthIPv4/IPv6`
    aggregates VIPs (caution: black-hole/routing-loop risk on unassigned
    addresses). Also honors `loadBalancerClass` (announces when unset or
    `io.cilium/bgp-control-plane`).
  - `Interface` — advertises /32 / /128 IPs of a named local interface (e.g.
    `lo`); loopback/multicast/link-local addresses excluded. Useful for
    multi-homing node loopbacks.
  - Plus `attributes`: `communities` (`standard`, `large`, `wellKnown` — full
    well-known table in the docs) and `localPreference` (iBGP only).
- **`CiliumLoadBalancerIPPool`** (LB-IPAM; source
  `Documentation/network/lb-ipam.rst` @ v1.20): `spec.blocks[]` as
  `- cidr:` or `- start:/stop:` ranges (dash placement matters — start/stop is
  one list item); optional `spec.allowFirstLastIPs: No` to reserve network /
  broadcast addresses; optional `spec.serviceSelector` (label selector, incl.
  special keys `io.kubernetes.service.namespace` / `io.kubernetes.service.name`)
  restricting which Services may draw IPs; `spec.disabled: true` pauses
  allocation. Overlapping pools are rejected (`Conflicting` status). IPs are
  **not configured on any interface** — they exist only as BGP-advertised
  routes.
- **`CiliumBGPNodeConfigOverride`**: per-node overrides (resource name must
  equal the node name): `routerID`, `localPort`, `localASN`, and per-peer
  `localAddress`. Router-ID allocation is controlled by
  `bgpControlPlane.routerIDAllocation.mode` (`default` = node IPv4, or lower
  32 bits of `cilium_host` MAC in IPv6 single-stack; `ip-pool` = allocate
  from `bgpControlPlane.routerIDAllocation.ipPool`).
- **`CiliumBGPNodeConfig`**: operator-generated per-node resource, the source
  of truth the agent consumes; `.status.bgpInstances[].peers[]` carries live
  `peeringState`, `establishedTime`, per-AFI route counts and applied timers.

### 1.3 YAML examples

Minimal cluster config + peer config pair (verbatim from
`bgp-control-plane-configuration.rst`, minus doc markup):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      rack: rack0
  bgpInstances:
  - name: "instance-65000"
    localASN: 65000
    localPort: 179
    peers:
    - name: "peer-65000-tor1"
      peerASN: 65000
      peerAddress: fd00:10:0:0::1
      peerConfigRef:
        name: "cilium-peer"
    - name: "peer-65000-tor2"
      peerASN: 65000
      peerAddress: fd00:11:0:0::1
      peerConfigRef:
        name: "cilium-peer"
```

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  authSecretRef: bgp-auth-secret      # optional, RFC 2385 TCP-MD5
  ebgpMultihop: 4                     # optional
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
  - afi: ipv4
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "bgp"
  - afi: ipv6
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "bgp"
```

Full example — pod CIDR + LoadBalancer VIPs, both families (assembled from the
per-field examples in `bgp-control-plane-configuration.rst` and
`lb-ipam.rst` @ v1.20):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: pod-and-lb-v4-v6
  labels:
    advertise: "bgp"
spec:
  advertisements:
  - advertisementType: "PodCIDR"
  - advertisementType: "Service"
    service:
      addresses:
      - LoadBalancerIP
    selector:
      matchExpressions:
      - { key: bgp, operator: In, values: [ advertise ] }
---
apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "lab"
spec:
  blocks:
  - cidr: "10.100.0.0/24"
  - cidr: "fd00:100::/120"
```

### 1.4 Diagnostics

- **Cilium CLI** (`cilium` binary on an operator machine; talks to the agent
  API): `cilium bgp peers` (session state, uptime, per-family
  received/advertised counts from all nodes) and
  `cilium bgp routes available|advertised <afi> <safi>`. Example output shows
  per-node `Local AS / Peer AS / Peer Address / Session State` and per-route
  `NextHop`, `AsPath`, `Communities`, `MpReach(...)`.
- **In-pod agent CLI**: `cilium-dbg bgp ...` inside the agent pod (e.g.
  `kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp route-policies`
  shows the generated GoBGP policies: match peers, match prefixes, RIB accept,
  `AddCommunities` path actions). Naming note: the in-agent binary was
  `cilium` up to Cilium 1.13 and was renamed **`cilium-dbg`** in 1.14 to free
  the name for the standalone CLI; the standalone CLI's `cilium bgp`
  subcommands exist on 1.14+ (older flows exec'ed into the pod). Docs @ v1.20
  use `cilium bgp peers`/`cilium bgp routes` for the CLI and
  `cilium-dbg bgp route-policies` in-pod.
- **CRD status** (`.status.conditions`):
  - `CiliumBGPClusterConfig`: `cilium.io/NoMatchingNode` (selector matches
    nothing), `cilium.io/MissingPeerConfigs` (referenced peer config absent),
    `cilium.io/ConflictingClusterConfig` (two ClusterConfigs select the same
    node — the operator rejects the additional one).
  - `CiliumBGPPeerConfig`: `cilium.io/MissingAuthSecret`.
  - `CiliumBGPNodeConfig`: live per-peer `peeringState`, route counts,
    applied timers. Status reporting can be disabled with
    `bgpControlPlane.statusReport.enabled=false` (large clusters).
- **Logs**: agent filter `subsys=bgp-control-plane`; operator filter
  `subsys=bgp-cp-operator`. Example error:
  `msg="sent notification" Data="as number mismatch expected 65003, received 65000"`.
  TCP-MD5 failures show as `dial: i/o timeout` or
  `Failed to fetch secret "secretname": not found (will continue with empty password)`.
- **Metrics** (`Documentation/observability/metrics.rst` @ v1.20; the docs
  tables strip the `cilium_`/`cilium_operator_` prefixes — actual scraped
  names below):
  - `cilium_bgp_control_plane_session_state`
    (labels `instance_name`, `local_asn`, `neighbor`, `neighbor_asn`; Up=1/Down=0)
  - `cilium_bgp_control_plane_advertised_routes`
    (+ `afi`, `safi`)
  - `cilium_bgp_control_plane_received_routes` (+ `afi`, `safi`)
  - `cilium_bgp_control_plane_reconcile_errors_total`,
    `cilium_bgp_control_plane_reconcile_run_duration_seconds` (histogram)
  - operator-side: `cilium_operator_bgp_control_plane_reconcile_errors_total`,
    `..._run_duration_seconds`
- **Common failure modes** (`bgp-control-plane-troubleshooting.rst`):
  1. Resources applied but no peering → check `CiliumBGPNodeConfig` exists;
     check operator logs; check `nodeSelector` matches node labels
     (`NoMatchingNode` condition).
  2. Node selected but session not established → check peer router logs and
     agent logs (`subsys=bgp-control-plane`); ASN mismatch, capability
     mismatch, wrong peer IP; low-level issues (no connectivity, eBGP >1 hop
     without multihop) may not appear in logs — use tcpdump/Wireshark.
  3. Additional `CiliumBGPClusterConfig` not working →
     `ConflictingClusterConfig` (one node = one ClusterConfig).
  4. `CiliumBGPPeerConfig` not taking effect → typo in `peerConfigRef` name →
     `MissingPeerConfigs` condition.
  Operationally (`bgp-control-plane-operation.rst`): agent restart kills
  sessions (routes withdrawn; use Graceful Restart to survive, and pre-pull
  images on upgrade so `restartTimeSeconds` — default 120s — isn't exceeded);
  node shutdown procedure = drain → deselect node from the ClusterConfig
  (e.g. flip an `enable-bgp` node label) → wait for peer route withdrawal →
  shutdown; **Cilium BGP CP does not support BFD** ("currently, Cilium does
  not support it" — still true in `main` as of 2026-10-24), so use short
  timers (`holdTimeSeconds=9`, `keepAliveTimeSeconds=3`; minimum 3/1) for
  fast detection.

### 1.5 Next-hop / source-address behavior

- The session's source IP is auto-detected from the egress interface of a
  route lookup to `peerAddress`; override per-peer with
  `transport.sourceInterface` in the PeerConfig or `peers[*].localAddress` in
  a `CiliumBGPNodeConfigOverride`. The interface "must not have more than one
  non-loopback, non-multicast and non-link-local-IPv6 address per address
  family."
- The **advertised next-hop is the session's local address**, e.g. the docs'
  `cilium bgp routes advertised` sample shows
  `Nexthop: fd00:10:0:1::2` — the node's own address toward the peer.
- Consequence for loopback peering (the FRR designs below): if Cilium peers
  over `::1`, its next-hop is `::1`, which FRR treats as a martian — FRR
  needs `bgp allow-martian-nexthop` and an inbound route-map rewriting the
  next-hop to a real node address before re-advertising to the fabric.
- IPv4 NLRI can ride an IPv6 session (MP_REACH with an IPv6 next-hop,
  RFC 8950-style) — the single `::1` session in the denizaydin design carries
  both families; conversely a pure-IPv4 Cilium cannot advertise IPv6 routes
  (§1.1) and needs the daemon running the other family.
- Peer auto-discovery: v1.20 has `autoDiscovery.mode: DefaultGateway`
  (per-family; discovers the node's default gateway and dials it; ToR side
  needs `bgp listen range ... peer-group` e.g. FRR `bgp listen range
  fd00:10:0:1::/64 peer-group CILIUM` with `neighbor CILIUM local-as 65000
  no-prepend replace-as`). Multi-homing limitation: one session per address
  family (picks the lowest-metric default route), so true dual-TOR peering
  still needs explicit `peerAddress` — which is exactly the gap the
  node-local FRR design fills.

---

## 2. denizaydin/cilium-containerlab-bgp-multihoming — `v2-node-local-frr`

All files verbatim from
<https://github.com/denizaydin/cilium-containerlab-bgp-multihoming/tree/main/v2-node-local-frr>
(fetched 2026-10-24). Lab: three k8s nodes dual-homed to two TORs over
unnumbered L3 links, no bonding/MLAG/ESI; node address on `dummy0`; Cilium
peers with the FRR on its own node over a single `::1` session.

### 2.1 Design (from the README)

- Topology: `gw AS 65090` (border, originates default both families,
  MASQUERADE to internet) — `tor1 AS 65001` / `tor2 AS 65002` (cross-linked)
  — nodes `controller AS 65111 / worker1 AS 65112 / worker2 AS 65113`,
  dual-homed unnumbered to both TORs. Cilium = **AS 65999** on every node.
- Node loopbacks: `dummy0` = `10.0.0.10x/32` + `fd00:ff::10x/128`. Pods
  `10.244.0.0/16` + `fd00:244::/104`, LB VIPs `10.100.0.0/24` +
  `fd00:100::/120`.
- "Cilium peers with the FRR running on its own node over a single `::1`
  session that carries both address families — no IPv4 session needed, and no
  Kubernetes manifest ever contains a TOR address."
- Why node-local FRR: Cilium never learns the fabric. No TOR addresses in any
  manifest; the per-node FRR owns all fabric-facing policy (dual-homing ECMP,
  BFD to TORs, next-hop rewrite, default-route learning). Cilium's only job
  is to hand pod CIDRs + LB VIPs to `::1`.
- Measured traps documented in the README:
  - The duplicate management address (`10.0.0.15` on every VM via slirp)
    wins IPv4 source selection over the unnumbered uplinks and breaks kubeadm
    join / node `INTERNAL-IP` — fix is removing the address entirely (netplan),
    making `dummy0` the only global IPv4. `preferred_lft 0` does not work for
    IPv4; `--node-ip` is a declaration, not a bind.
  - Needs **FRR ≥ 8.4** (uses `allow-reserved-ranges`); Ubuntu 22.04's FRR 8.1
    is too old, image installs FRR 9.1.3 from deb.frrouting.org.
  - `allow-reserved-ranges` and `nht resolve-via-default` are **global**
    commands, not `router bgp` subcommands.
  - Cilium does not listen by default (`ListenPort -1`) → the FRR side must
    dial: `passive` on the Cilium neighbour is wrong.
  - After switching source addresses, zebra keeps ECMP routes but the kernel
    rejects them (visible only as `r` flag in `show ip route`); `systemctl
    restart frr` clears it.
  - Offline note: after cutting management, every image must be pre-loaded
    and reused; `ctr` doesn't expand Docker Hub shorthands; values file, not
    `--set` flags, for helm (flags silently vanished, `helm get values` =
    null).

### 2.2 Route flow

Cilium (per node, AS 65999) → single eBGP(ish) session over `::1` → node FRR
(AS 65xxx) rewrites next-hop (inbound route-map: Cilium's loopback next-hop →
node's `fd00:ff::10x`) → node FRR re-advertises pod CIDRs + LB VIPs to both
TORs (eBGP unnumbered, `maximum-paths 8`, BFD 150ms) → TORs cross-link them
(`no bgp ebgp-requires-policy`, `multipath-relax`). Default route flows the
opposite direction: gw originates it, TORs propagate, nodes install via
`nht resolve-via-default`. LB VIPs are /32 // /128 host routes, so fabric ECMP
follows the nodes that actually hold backends.

### 2.3 Node FRR config (verbatim)

`v2-node-local-frr/frr/node.conf.tmpl` — rendered per node
(`__HOSTNAME__ __ASN__ __V4__ __V6__ __IF1__ __IF2__`):
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/frr/node.conf.tmpl>

```text
! Kubernetes node FRR — template.
! setup renders per node: __HOSTNAME__ __ASN__ __V4__ __V6__ __IF1__ __IF2__
!
! Taken verbatim from the config measured working on the nodes, then
! templated. Do not "tidy" it against memory.
!
! Role: node infrastructure BGP.
!   north: unnumbered to both TORs — advertise the node host route, learn
!          the (real, gw-originated) default
!   south: ONE loopback session for Cilium (ASN 65999), over ::1 only.
!
! MEASURED: no IPv4 session to Cilium is needed. The single ::1 session
! carries BOTH address families — IPv4 NLRI rides the IPv6 session
! (activate ::1 under the ipv4 unicast family). A 127.0.0.1 neighbour is
! redundant; it was tried and then removed.
!
! The traps, all measured:
!   - `allow-reserved-ranges` and `nht resolve-via-default` are GLOBAL
!     commands, NOT `router bgp` ones. Looking for them under `router bgp`
!     returns "% Unknown command" and makes FRR look too old. There is no
!     `bgp allow-reserved-ranges`.
!   - `bgp allow-martian-nexthop` stops FRR answering Cilium's first
!     UPDATE with Invalid NEXT_HOP.
!   - The inbound route-map rewrites Cilium's loopback next hop to the
!     node address. Without it FRR advertises a loopback to the fabric and
!     the TORs can never reach the pods.
!   - `passive` on the Cilium neighbour is wrong: Cilium does not listen
!     (ListenPort -1), so FRR must be the dialling side.
! Needs FRR >= 8.4. Ubuntu 22.04 ships 8.1, which is why the node image
! installs FRR from deb.frrouting.org (9.1.3).
!
frr defaults datacenter
hostname __HOSTNAME__
allow-reserved-ranges
service integrated-vtysh-config
!
interface dummy0
 ip address __V4__/32
 ipv6 address __V6__/128
exit
!
router bgp __ASN__
 bgp router-id __V4__
 no bgp default ipv4-unicast
 bgp bestpath as-path multipath-relax
 neighbor __IF1__ interface remote-as external
 neighbor __IF1__ description tor1
 neighbor __IF1__ bfd
 neighbor __IF1__ bfd profile fast
 neighbor __IF2__ interface remote-as external
 neighbor __IF2__ description tor2
 neighbor __IF2__ bfd
 neighbor __IF2__ bfd profile fast
 neighbor ::1 remote-as 65999
 neighbor ::1 description cilium
 bgp allow-martian-nexthop
 !
 address-family ipv4 unicast
  network __V4__/32
  neighbor __IF1__ activate
  neighbor __IF2__ activate
  neighbor ::1 activate
  neighbor ::1 route-map cilium-ipv6-nexthop in
  maximum-paths 8
 exit-address-family
 !
 address-family ipv6 unicast
  network __V6__/128
  neighbor __IF1__ activate
  neighbor __IF2__ activate
  neighbor ::1 activate
  neighbor ::1 route-map cilium-ipv6-nexthop in
  maximum-paths 8
 exit-address-family
exit
!
route-map cilium-ipv6-nexthop permit 10
 set ipv6 next-hop global __V6__
exit
!
ip nht resolve-via-default
!
ipv6 nht resolve-via-default
!
bfd
 profile fast
  transmit-interval 150
  receive-interval 150
 exit
exit
!
line vty
!
```

Note there is **no `next-hop-self` and no `next-hop-unchanged`** — the design
relies on the inbound route-map (`set ipv6 next-hop global __V6__`) rewriting
Cilium's loopback next-hop to the node address; eBGP to the TORs then
naturally advertises the node as next-hop. (`allow-reserved-ranges` is
present, global scope, for the fd00::/fd00:100:: ULA pod/VIP prefixes FRR
otherwise refuses.)

### 2.4 TOR + gw configs (verbatim)

`v2-node-local-frr/frr/tor1.conf` (tor2.conf is identical with
`65002/10.255.0.2/fd00:255::2/10.2.2.1 fd00:2::1`):
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/frr/tor1.conf>

```text
! tor1 — ASN 65001
! MEASURED interface map (6-NIC generic_vm, 2026-08-06):
!   ens2=controller  enp1s3=worker1  ens4=worker2
!   enp1s5=cross     enp1s6=ext1    enp1s7=gw
frr defaults datacenter
hostname tor1
!
interface lo
 ip address 10.255.0.1/32
 ipv6 address fd00:255::1/128
!
interface enp1s6
 ip address 10.1.1.1/24
 ipv6 address fd00:1::1/64
!
bfd
 profile fast
  receive-interval 150
  transmit-interval 150
  detect-multiplier 3
 exit
exit
!
router bgp 65001
 bgp router-id 10.255.0.1
 no bgp ebgp-requires-policy
 no bgp default ipv4-unicast
 bgp bestpath as-path multipath-relax
 !
 neighbor FABRIC peer-group
 neighbor FABRIC remote-as external
 neighbor FABRIC bfd profile fast
 neighbor ens2 interface peer-group FABRIC
 neighbor ens2 description controller
 neighbor enp1s3 interface peer-group FABRIC
 neighbor enp1s3 description worker1
 neighbor ens4 interface peer-group FABRIC
 neighbor ens4 description worker2
 neighbor enp1s5 interface peer-group FABRIC
 neighbor enp1s5 description cross
 neighbor enp1s7 interface peer-group FABRIC
 neighbor enp1s7 description gw
 !
 ! No default-originate anywhere: the REAL default comes from gw and is
 ! simply propagated. (The Phase 0 lab faked it from the TORs.)
 address-family ipv4 unicast
  maximum-paths 8
  network 10.1.1.0/24
  network 10.255.0.1/32
  neighbor FABRIC activate
 exit-address-family
 !
 address-family ipv6 unicast
  maximum-paths 8
  network fd00:1::/64
  network fd00:255::1/128
  neighbor FABRIC activate
 exit-address-family
!
line vty
!
```

`v2-node-local-frr/frr/gw.conf`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/frr/gw.conf>

```text
! gw — border/edge, ASN 65090, FRR container.
!
! eth0 = containerlab management bridge (docker NAT -> internet)
! eth1 = tor1, eth2 = tor2 — unnumbered
!
! Originates the DEFAULT for the whole fabric, both families. This is
! the real default: v4 traffic is masqueraded out eth0 (see gw-nat.sh).
! v6 has no internet path (containerlab has none) — the v6 default still
! comes from here so the fabric's routing is uniform; NAT64 is the
! deferred piece if an IPv6-only phase needs real v6 egress.
!
frr defaults datacenter
hostname gw
!
interface lo
 ip address 10.255.0.90/32
 ipv6 address fd00:255::90/128
!
router bgp 65090
 bgp router-id 10.255.0.90
 no bgp ebgp-requires-policy
 no bgp default ipv4-unicast
 !
 neighbor eth1 interface remote-as external
 neighbor eth1 description tor1
 neighbor eth2 interface remote-as external
 neighbor eth2 description tor2
 !
 address-family ipv4 unicast
  neighbor eth1 activate
  neighbor eth1 default-originate
  neighbor eth2 activate
  neighbor eth2 default-originate
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor eth1 activate
  neighbor eth1 default-originate
  neighbor eth2 activate
  neighbor eth2 default-originate
 exit-address-family
!
line vty
!
```

### 2.5 Cilium BGP manifests (verbatim)

`v2-node-local-frr/bgp/cluster-config.yaml` — one `CiliumBGPClusterConfig`
per node, all peering `::1`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/bgp/cluster-config.yaml>

```yaml
# One config per node: Cilium (65999) peers the FRR running on its OWN
# node, which then re-advertises the PodCIDRs and LB VIPs to both TORs.
#
# MEASURED: a single ::1 peer is enough. Cilium negotiates both address
# families on it, and the node FRR activates ::1 under ipv4 unicast too —
# IPv4 NLRI rides the IPv6 session. A 127.0.0.1 peer is redundant; it was
# tried and removed.
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: controller
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: controller
  bgpInstances:
  - name: main
    localASN: 65999
    peers:
    - name: local-frr-v6
      peerASN: 65111
      peerAddress: "::1"
      peerConfigRef:
        name: local-frr
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: worker1
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker1
  bgpInstances:
  - name: main
    localASN: 65999
    peers:
    - name: local-frr-v6
      peerASN: 65112
      peerAddress: "::1"
      peerConfigRef:
        name: local-frr
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: worker2
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker2
  bgpInstances:
  - name: main
    localASN: 65999
    peers:
    - name: local-frr-v6
      peerASN: 65113
      peerAddress: "::1"
      peerConfigRef:
        name: local-frr
```

`v2-node-local-frr/bgp/peer-config.yaml`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/bgp/peer-config.yaml>

```yaml
# Shared peer settings. Timers are short so a change is visible in seconds
# instead of minutes while debugging.
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: local-frr
spec:
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  families:
  - afi: ipv4
    safi: unicast
    advertisements:
      matchLabels:
        advertise: pods
  - afi: ipv6
    safi: unicast
    advertisements:
      matchLabels:
        advertise: pods
```

`v2-node-local-frr/bgp/advertisement.yaml`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/bgp/advertisement.yaml>

```yaml
# What Cilium offers to the node's FRR: the PodCIDR it was allocated.
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: pods
  labels:
    advertise: pods
spec:
  advertisements:
  - advertisementType: PodCIDR
```

`v2-node-local-frr/bgp/advertisement-services.yaml`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/bgp/advertisement-services.yaml>

```yaml
# Advertise LoadBalancer VIPs as /32 and /128. Cilium only advertises a
# VIP from nodes that actually have a backend for it, so the fabric's
# ECMP follows the pods.
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: services
  labels:
    advertise: pods
spec:
  advertisements:
  - advertisementType: Service
    service:
      addresses:
      - LoadBalancerIP
    selector:
      matchExpressions:
      - key: bgp
        operator: In
        values: ["advertise"]
```

`v2-node-local-frr/bgp/lb-pool.yaml`:
<https://raw.githubusercontent.com/denizaydin/cilium-containerlab-bgp-multihoming/main/v2-node-local-frr/bgp/lb-pool.yaml>

```yaml
# LoadBalancer addresses. These are NOT on any interface — Cilium hands
# them out and then advertises them via BGP, which is the point: the
# fabric learns the VIP from the node that owns the backends.
#
# Ranges deliberately outside the pod and node pools so a route to them
# can only have come from this advertisement.
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: lab
spec:
  blocks:
  - cidr: 10.100.0.0/24
  - cidr: fd00:100::/120
```

Relevant `v2-node-local-frr/cilium-values.yaml` bits: `bgpControlPlane.enabled: true`,
`routingMode: native`, `kubeProxyReplacement: true`, `ipv4NativeRoutingCIDR:
10.244.0.0/16`, `ipv6NativeRoutingCIDR: fd00:244::/56`, masquerade off both
families, `ipam.mode: cluster-pool` with per-node /24 (v4) and /120 (v6;
measured note: cilium's clusterSubnetMaxDiff allows at most 16 bits between
pool prefix and per-node mask).

### 2.6 Why the single `::1` session works

Both daemons run on the same node, so loopback is a valid transport. Cilium
negotiates MP-BGP so one TCP session over `::1` carries `ipv4/unicast` and
`ipv6/unicast`; the node FRR explicitly activates `::1` under the v4
address-family, so v4 NLRI (pod CIDRs, v4 VIPs) rides the v6 session with an
IPv6 next-hop. FRR ≥ 8.4's `allow-reserved-ranges` permits advertising the
ULA pod/VIP prefixes, `bgp allow-martian-nexthop` accepts Cilium's loopback
next-hop, and the inbound `route-map cilium-ipv6-nexthop` rewrites that
next-hop to the node's real `fd00:ff::10x` so the fabric can actually forward
to the pods. On session direction, the source's measured comment says:
"`passive` on the Cilium neighbour is wrong: Cilium does not listen
(`ListenPort -1`), so FRR must be the dialling side" — i.e. don't mark the
`::1` neighbour passive. Note this phrasing sits oddly next to the Cilium
docs' statement that a BGP instance *without* `localPort` "can only initiate
connections ... but cannot accept incoming connections" (which implies Cilium
dials and FRR, listening on 179 by default, accepts) — the operational
takeaway either way: no `passive` on the Cilium neighbour, and FRR's bgpd
must be allowed to listen on `::1:179`.

---

## 3. bella.network — WireGuard + internal BGP site mesh

Source: <https://blog.bella.network/internal-bgp-with-wireguard/> (fetched
2026-10-24). "Dynamic site to site networking using WireGuard and BGP."

### 3.1 Topology

- Three sites: **Network A** (primary, public IP; `10.10.0.0/16` DC,
  `10.20.0.0/16` office + `2001:db8:10::/48`, `2001:db8:20::/48`),
  **Network B** (static IP; `10.100.0.0/16`, `2001:db8:100::/48`),
  **Network C** (dynamic/non-public IP, behind NAT; `10.101.0.0/16`,
  `2001:db8:101::/48`).
- **Transfer networks**: `172.31.10.0/24` carved as /31 (v4) and
  `2001:db8::/32` carved as /112 (v6) per peering. Naming scheme
  `s2svpNN` = "Server 2 Server VPN Peering NN"; peering N uses
  `172.31.10.2N/31` and `2001:db8::N:.../112`.
- One WireGuard interface per peering (`s2svp00`, `s2svp01`, ...), preshared
  key + `AllowedIPs = 0.0.0.0/0, ::/0`, addresses added out-of-band with
  `ip addr add 172.31.10.0/32 peer 172.31.10.1/32 dev s2svp00` (ptp /32 +
  /112 style), link-local `fe80::` v6 addresses too, `PersistentKeepalive =
  25`.
- Site C behind NAT: peers omit `Endpoint` (hub-and-spoke inbound); A/B keep
  `Endpoint` for outbound. B↔C can be added for hub-loss resilience — a full
  mesh of BGP sessions over the tunnels.
- AS numbers: A=65001, B=65002, C=65003 — each site uses its own private ASN,
  so sessions between sites are **eBGP** (the blog's "internal BGP" means
  private-AS / non-transit routing, not same-AS iBGP); neighbors are the
  tunnel /31 and /112 addresses, one session per address family per peer.

### 3.2 FRR config (verbatim, Network A)

```text
hostname <network A unique hostname of router>
log stdout informational
log syslog
!
debug bgp neighbor-events
debug bgp updates in
debug bgp updates out
!
router bgp 65001
 bgp log-neighbor-changes
 no bgp ebgp-requires-policy
 no bgp suppress-duplicates
 no bgp hard-administrative-reset
 no bgp default ipv4-unicast
 no bgp graceful-restart notification
 bgp graceful-restart
 no bgp network import-check
 neighbor 172.31.10.1 remote-as 65002
 neighbor 172.31.10.1 description network-b
 neighbor 2001:db8::0:1 remote-as 65002
 neighbor 2001:db8::0:1 description network-b
 bgp fast-convergence
 !
 address-family ipv4 unicast
  network 10.10.0.0/16
  network 10.20.0.0/16
  network 172.31.10.0/31
  redistribute static
  neighbor 172.31.10.1 activate
  neighbor 172.31.10.1 addpath-tx-all-paths
 exit-address-family
 !
 address-family ipv6 unicast
  network 2001:db8:10::/48
  network 2001:db8:20::/48
  network 2001:db8::0:0/112
  redistribute static
  neighbor 2001:db8::0:1 activate
  neighbor 2001:db8::0:1 addpath-tx-all-paths
 exit-address-family
exit
do wr mem
```

Network B is the same shape with `65002`, its own networks, and neighbors
`172.31.10.0` / `2001:db8::0:0`. Adding Network C adds another neighbor pair
(`172.31.10.3 remote-as 65003` etc.). Verify with
`show ip bgp summary` (`State/PfxRcd` > 0 = session up).

Notable knobs: `no bgp ebgp-requires-policy` (no route-map requirement),
`no bgp default ipv4-unicast` (explicit per-family activation),
`no bgp network import-check` (allow `network` statements for prefixes not in
the RIB), `redistribute static`, `addpath-tx-all-paths`, `bgp
fast-convergence`, `bgp graceful-restart`.

### 3.3 Route filtering

Per-site prefix-lists + route-maps control which networks may talk (verbatim,
Network A):

```text
router bgp 65001
  address-family ipv4 unicast
  network 10.10.0.0/16 route-map ANNOUNCE-v4
  network 10.20.0.0/16 route-map ANNOUNCE-v4
  network 172.31.10.0/31 route-map ANNOUNCE-v4
  redistribute static
  neighbor 172.31.10.1 activate
  neighbor 172.31.10.1 soft-reconfiguration inbound
  neighbor 172.31.10.1 route-map FILTER-INBOUND in
  neighbor 172.31.10.1 route-map ANNOUNCE-v4 out
 exit-address-family
exit
!
ip prefix-list MY-NETWORKS seq 10 permit 10.10.0.0/16
ip prefix-list MY-NETWORKS seq 20 permit 10.20.0.0/16
ip prefix-list MY-NETWORKS seq 30 permit 172.31.10.0/24
ip prefix-list MY-NETWORKS seq 100 deny 0.0.0.0/0
!
ip prefix-list INBOUND-FILTER seq 87 permit 10.0.0.0/8 ge 9
ip prefix-list INBOUND-FILTER seq 88 permit 172.16.0.0/12 ge 13
ip prefix-list INBOUND-FILTER seq 89 permit 192.168.0.0/16 ge 17
ip prefix-list INBOUND-FILTER seq 100 deny 0.0.0.0/0
!
route-map ANNOUNCE-v4 permit 10
 match ip address prefix-list MY-NETWORKS
exit
!
route-map ANNOUNCE-v4 deny 20
exit
!
route-map FILTER-INBOUND permit 10
 match ip address prefix-list INBOUND-FILTER
exit
!
route-map FILTER-INBOUND deny 20
```

The `ge 9/13/17` bounds accept only sub-prefixes of the RFC1918 ranges (so a
leaked `10.0.0.0/8` aggregate is dropped). Verify with `show ip bgp`.

---

## 4. NixOS `services.frr` (nixos-unstable, fetched 2026-10-24)

Module: `nixos/modules/services/networking/frr.nix` @ nixos-unstable
(<https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/nixos/modules/services/networking/frr.nix>,
317 lines). Package: `pkgs/by-name/fr/frr/package.nix` — **FRR 10.7.1**
(`pname = "frr"; version = "10.7.1"`, src `FRRouting/frr@frr-10.7.1`).

### 4.1 What `services.frr.config` generates

- `services.frr.config` (type `lines`) is wrapped into a single **integrated
  vtysh config** — the module builds
  `configFile = pkgs.writeText "frr.conf"` containing:

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

  and installs it as **`/etc/frr/frr.conf`** (`environment.etc."frr/frr.conf".source`).
- `services.frr.configFile` (nullOr path) overrides the generated file
  entirely — point it at your own file (e.g. a flake-tracked frr.conf
  `pkgs.writeText`/`./frr.conf`) to bypass `config`.
- The module also writes:
  - `/etc/frr/vtysh.conf` with exactly `service integrated-vtysh-config`
    (system-wide vtysh always enabled — one merged config view);
  - `/etc/frr/daemons`, the Debian-style daemon manifest:

    ```text
    # This file tells the frr package which daemons to start.
    #
    # The watchfrr, zebra and staticd daemons are always started.
    #
    # This part is auto-generated from services.frr.<daemon>.enable config
    bgpd=yes            # one line per daemon in the fixed `daemons` list
    ospfd=no
    ...

    vtysh_enable=yes

    # options from services.frr.<daemon>.options / .extraOptions
    zebra_options="-A 127.0.0.1 -s 90000000"
    mgmtd_options="-A 127.0.0.1"
    bgpd_options="-A 127.0.0.1"
    ...
    ```

- **Systemd shape**: ONE unit, `frr.service` — there are no per-daemon units.
  It runs `${pkgs.frr}/libexec/frr/frrinit.sh start` (Type=forking,
  PIDFile `/run/frr/watchfrr.pid`, watchdog via watchfrr, Restart=always,
  Nice=-5, LimitNOFILE = `services.frr.openFilesLimit`, default 1024 —
  raise it for large BGP meshes). `watchfrr`, `zebra`, `mgmtd`, `staticd`
  always start; enabled daemons come from the `daemons` list:
  `bgpd ospfd ospf6d ripd ripngd isisd pimd pim6d ldpd nhrpd eigrpd babeld
  sharpd pbrd bfdd fabricd vrrpd pathd`.
- Daemon CLI flags: `services.frr.<daemon>.options` (list of str, default
  from `daemonDefaultOptions`, e.g. `bgpd = "-A 127.0.0.1"` — vtysh listens on
  loopback only) and `.extraOptions` appended. To expose the VTY on the
  network: change `options`/add `-P 2605` etc.
- **Reloads**: `reloadIfChanged = true` with `restartTriggers = [configFile
  daemonList]` — a config change triggers `ExecReload =
  ${pkgs.frr}/libexec/frr/frrinit.sh reload`, which (FRR 10.7.1
  `tools/frrinit.sh.in`) runs `frr-reload.py --reload --bindir ... --confdir
  ... --rundir ... /etc/frr/frr.conf` — a graceful in-place reload (no
  session reset for unchanged peers) as long as the python tools are present
  (they are, in the nixpkgs build). Note: changing the *daemons* list is also
  only a reload — `frrinit.sh reload` does not start newly enabled daemons;
  a fresh start/`nixos-rebuild switch` boot path or `systemctl restart frr`
  is needed when the daemon set changes.
- **Users/groups**: `frr` user + `frr` group; `frrvty` group exists and
  `frr` is a member — "Members of the frrvty group can use vtysh". Add your
  admin user to `frrvty` for non-root vtysh. `/run/frr` created via tmpfiles
  (`0755 frr frr`). `vtysh` is on PATH via `environment.systemPackages =
  [pkgs.frr]` ("for the vtysh tool").
- **Renames/removals** (agent gotchas): the old `services.frr.bgp.enable`
  names were renamed to `services.frr.bgpd.enable` (same for ospf→ospfd,
  bfd→bfdd, etc.); `zebra`/`staticd`/`mgmtd` have no enable option (always
  on); per-daemon `config`/`configFile`/`vtyListenAddress`/`vtyListenPort`
  options were **removed** — "FRR switched to integrated-vtysh-config, please
  use services.frr.config". Don't hand-write a `router bgp` block under a
  per-daemon key; everything goes in the one `services.frr.config`.

### 4.2 Package features (FRR 10.7.1 on nixos-unstable)

From `pkgs/by-name/fr/frr/package.nix` (abridged — flags shown were readable
in full from source): `bgpdSupport ? true`, `bfddSupport ? true`,
`staticdSupport ? true`, all other protocol daemons default-true,
`snmpSupport ? true`, `rpkiSupport ? true`, `numMultipath ? 64`,
`watchfrrSupport ? true`, `mgmtdSupport ? true`, `scriptingSupport ? true`,
`grpcSupport ? false` ("Experimental as 10.1"). Configure flags include
`--disable-zeromq`, `--enable-configfile-mask=0640`,
`--enable-logfile-mask=0640`, `--enable-group=frr`, `--enable-user=frr`,
`--enable-vty-group=frrvty`, `--enable-multipath=64`,
`--enable-config-rollbacks`, `--localstatedir=/var`,
`--sbindir=$out/libexec/frr`, `--sysconfdir=/etc`, plus per-daemon
`--enable-*` toggles and `--enable-bgp-announce/--enable-bmp/--enable-vnc`.
`passthru.tests = { inherit (nixosTests) frr; }` — a NixOS VM test exists.

### 4.3 NixOS-specific caveats for an agent

- **Firewall**: the module opens nothing. eBGP needs
  `networking.firewall.allowedTCPPorts = [ 179 ];` (and 179 inbound on the
  relevant interfaces), BFD needs UDP 3784 (+4784 multihop) if you enable
  `bfdd`. WireGuard UDP ports are separate (`networking.wireguard` /
  `networking.firewall` / nftables).
- **vtysh access**: root can run `vtysh` directly; non-root users must be in
  the `frrvty` group. `vtysh -b` (boot load) is invoked by frrinit on start;
  `vtysh -c "show ip bgp summary"` is the read-only inspection pattern.
- **/etc/frr permissions**: daemons run as user `frr` group `frr`; files FRR
  itself writes are masked 0640. NixOS's `environment.etc` entries are
  symlinks into the store — world-readable, which FRR accepts (it checks
  ownership where it matters); don't `chmod` the symlinks, fix the store
  file / use `configFile` with a properly owned path if a stricter setup
  demands it.
- **Config semantics**: with `service integrated-vtysh-config`, `frr.conf` is
  the one file `vtysh -b` loads into all daemons on start, and
  `frr-reload.py` diffs against it on reload. Keep the whole BGP block
  (`router bgp ...`, route-maps, prefix-lists, bfd block) inside
  `services.frr.config` — no per-daemon split is possible anymore.
- **Template rendering**: for per-node configs (the denizaydin node.conf.tmpl
  pattern), generate the `config` string with `lib.replaceStrings` /
  `pkgs.substituteAll` / mustache-style templating in Nix, or ship one
  `configFile` per host from the flake.
- Minimal NixOS sketch for the node-local-FRR role:

  ```nix
  {
    services.frr = {
      bgpd.enable = true;
      bfdd.enable = true;
      config = ''
        frr defaults datacenter
        allow-reserved-ranges
        router bgp 65112
         no bgp default ipv4-unicast
         neighbor enp2s0 interface remote-as external
         neighbor ::1 remote-as 65999
         bgp allow-martian-nexthop
         address-family ipv4 unicast
          neighbor enp2s0 activate
          neighbor ::1 activate
          neighbor ::1 route-map cilium-nexthop in
         exit-address-family
         address-family ipv6 unicast
          neighbor enp2s0 activate
          neighbor ::1 activate
          neighbor ::1 route-map cilium-nexthop in
         exit-address-family
        exit
        route-map cilium-nexthop permit 10
         set ipv6 next-hop global fd00:ff::102
        exit
        ipv6 nht resolve-via-default
      '';
    };
    networking.firewall.allowedTCPPorts = [ 179 ];
  }
  ```

---

## 5. Design patterns — which integration model when

**A. Cilium → node-local FRR → fabric (denizaydin v2).**
Cilium peers only with `::1` (its own node's FRR); FRR owns all fabric
facing: dual-homing ECMP to two TORs, BFD, next-hop rewrite, default-route
install, any route-policy. Choose when: multi-homed nodes (Cilium's
`DefaultGateway` auto-discovery only builds one session per family), you want
BFD on fabric links (Cilium BGP CP has no BFD), the fabric speaks unnumbered
RFC 8950 eBGP, TOR addresses must not appear in k8s manifests, or you need
FRR-side filtering/rewriting between Cilium and the fabric. Costs: an FRR
instance per node to operate; careful source-address hygiene (the `10.0.0.15`
trap); FRR ≥ 8.4 for `allow-reserved-ranges`; the martian-next-hop + route-map
incantation is mandatory.

**B. Cilium → TOR/fabric direct peering (Cilium docs model).**
`CiliumBGPClusterConfig` with explicit TOR `peerAddress`es (or
`DefaultGateway` auto-discovery with FRR `bgp listen range` on the ToR).
Choose when: single-homed or simple L3-to-TOR racks, one session per family
is enough, you want the smallest moving parts (no per-node FRR), and the TOR
config can be touched to add peers/listen-ranges. Costs: every TOR-facing
change is a k8s manifest change; no BFD (short timers only); peering directly
with the node address couples Cilium config to interface addressing.

**C. WireGuard iBGP site mesh (bella.network).**
Independent of the datacenter models: FRR on NixOS site routers, one WG
interface per peering with /31 + /112 transfer nets, per-site BGP with
prefix-list/route-map filtering (`ge 9/13/17` RFC1918 guards). Choose when:
connecting sites/homelabs over untrusted internet without NAT, dynamic
endpoints (keepalive + endpoint-less hub side for NATed spokes), granular
inter-site reachability policy. Combines with A or B: the k8s cluster speaks
BGP pattern A/B inside its site; the site router redistributes/announces the
cluster prefix into the WG mesh (announce the VIP pool + pod CIDR from the
site FRR, or let node FRR peer with the site router via a loopback — the
"node FRR as the site's BGP speaker" union of A + C).

**Rule of thumb**: A for production multi-homed clusters where the fabric is
yours; B for labs/single-homed where TORs are config-managed anyway; C for
the site-to-site layer above both. On NixOS, all three reduce to
`services.frr.config` + `bgpd.enable` (+ `bfdd.enable`) + firewall 179, with
WireGuard handled by `networking.wireguard` / wg-quick.

---

## 6. Fetch notes / gaps

- **docs.cilium.io rendered sub-pages**: guessed rendered URLs for the CRD
  sub-pages (`.../bgp-cluster-config/` etc.) returned 404 — in v1.20 those
  topics are anchors; the real pages are
  `bgp-control-plane-configuration`, `bgp-control-plane-operation`,
  `bgp-control-plane-troubleshooting` (fetched as canonical RST from
  `cilium/cilium@v1.20` instead — content is identical to the rendered site).
- **Cilium main branch**: checked for post-v1.20 BFD support in BGP CP — not
  present as of 2026-10-24 (`bgp-control-plane-operation.rst` in `main` still
  says "currently, Cilium does not support it").
- **denizaydin repo**: everything fetched verbatim (README, all 4 FRR
  configs, all 5 BGP manifests, cilium-values.yaml) and re-verified byte-for-byte
  for the FRR configs (`gw.conf` `default-originate` spellings checked — all
  correct in source).
- **bella.network blog**: full text fetched; only the topology diagram image
  did not come through (referenced by URL, not essential).
- **nixpkgs**: module and package fetched from `nixos-unstable` HEAD on
  2026-10-24 (FRR **10.7.1**); the package's long `configureFlags` list was
  partially compressed in transit — all flag *names* listed are accurate,
  but treat the exact default value of each `? true/? false` parameter as
  "read package.nix before overriding".
