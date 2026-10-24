# FRR × Cilium BGP control plane

Integration patterns for using FRR (on NixOS) with Cilium's BGP
control plane. Cilium facts are pinned to **v1.20** (see the `cilium`
skill for full CRD field documentation; this file carries the
FRR-facing view). Verbatim lab configs and CRD YAML live in
[research/cilium-nixos-integration.md](research/cilium-nixos-integration.md).

## How Cilium's BGP control plane behaves

- A per-node BGP manager embedded in the Cilium agent (built on
  GoBGP). The operator translates cluster-wide CRDs into a per-node
  `CiliumBGPNodeConfig`; the agent dials the configured peers and
  advertises.
- **Dial-out only by default**: the BGP instance has no listening port
  unless `localPort` is set (which needs CAP_NET_BIND_SERVICE via the
  agent securityContext). Consequence for FRR: the Cilium neighbor must
  never be configured `passive` — and whichever side dials, FRR's bgpd
  must be allowed to reach ::1/127.0.0.1:179 (loopback is in
  `allow-reserved-ranges` territory).
- **Advertisement-only**: it announces pod CIDRs and service VIPs; it
  does not program in-cluster reachability (that is native routing /
  tunneling config).
- **No BFD** (still true on main as of 2026-10-24). Use short timers
  for fast detection: `holdTimeSeconds: 9`, `keepAliveTimeSeconds: 3`
  (minimum 3/1).
- AF restriction: it only advertises the address families Cilium itself
  uses (a pure-IPv4 Cilium cannot advertise v6 routes, and vice versa).

## The CRDs (compact) — CiliumBGPClusterConfig + friends

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig          # one per set of nodes; nodeSelector picks them
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels: { rack: rack0 }
  bgpInstances:
  - name: "instance-65999"
    localASN: 65999
    # localPort: 179        # only if FRR must dial INTO Cilium
    peers:
    - name: "local-frr-v6"
      peerASN: 65112
      peerAddress: "::1"                # node-local FRR pattern
      peerConfigRef:
        name: "local-frr"
---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig             # reusable per-peer settings
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
      matchLabels: { advertise: "pods" }
  - afi: ipv6
    safi: unicast
    advertisements:
      matchLabels: { advertise: "pods" }
---
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: pods
  labels: { advertise: "pods" }
spec:
  advertisements:
  - advertisementType: PodCIDR        # also: Service (LB VIPs /32 /128), Interface
  #- advertisementType: Service
  #  service:
  #    addresses: [LoadBalancerIP]
  #  selector:
  #    matchExpressions:
  #    - { key: bgp, operator: In, values: [advertise] }
---
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool        # LB-IPAM; IPs exist only as BGP-advertised routes
metadata:
  name: lab
spec:
  blocks:
  - cidr: "10.100.0.0/24"
  - cidr: "fd00:100::/120"
```

The rule that bites: **without a matching `advertisements` selector, a
session comes up but advertises nothing** (`show bgp summary` shows
PfxRcd 0 from Cilium's side).

## Next-hop semantics (the core of every FRR pairing)

- The advertised next-hop is the **session's local address**
  (auto-detected from egress; overridable with
  `transport.sourceInterface` or a `CiliumBGPNodeConfigOverride`).
- Therefore peering over `::1` makes Cilium advertise `::1` as the
  next-hop — a martian for FRR. FRR side needs:
  - `allow-reserved-ranges` (global) — permits ::1/127.0.0.0-8 peering
    and ULA pod/VIP prefixes (FRR ≥ 8.4);
  - `bgp allow-martian-nexthop` (in `router bgp`) — accept the loopback
    next-hop instead of resetting the session;
  - an **inbound route-map rewriting the next-hop** to the node's real
    address, otherwise the fabric learns an unreachable next-hop:
    ```
    route-map cilium-nexthop permit 10
     set ipv6 next-hop global fd00:ff::102
    ```
- IPv4 NLRI rides the IPv6 session fine (MP_REACH with an IPv6
  next-hop — RFC 8950 style): one `::1` session carries both families;
  a second 127.0.0.1 session is redundant.

## Pattern A — node-local FRR → fabric (multi-homed production)

Cilium (same ASN on every node, e.g. 65999) peers only with `::1`; the
node's FRR owns everything fabric-facing: unnumbered RFC 8950 eBGP to
both TORs, ECMP, BFD, next-hop rewrite, default-route install. No TOR
address ever appears in a Kubernetes manifest — racks can be rewired
without touching Cilium config.

Node FRR distilled (full verbatim template in the research file):

```text
frr defaults datacenter
allow-reserved-ranges                     ! GLOBAL, not under router bgp
!
router bgp 65112                          ! per-node ASN
 bgp router-id 10.0.0.102
 no bgp default ipv4-unicast
 bgp bestpath as-path multipath-relax
 bgp allow-martian-nexthop
 neighbor enp2s0 interface remote-as external   ! tor1, unnumbered
 neighbor enp3s0 interface remote-as external   ! tor2
 neighbor enp2s0 bfd profile fast
 neighbor enp3s0 bfd profile fast
 neighbor ::1 remote-as 65999              ! cilium
 !
 address-family ipv4 unicast
  neighbor enp2s0 activate
  neighbor enp3s0 activate
  neighbor ::1 activate                   ! v4 NLRI over the v6 session
  neighbor ::1 route-map cilium-nexthop in
  maximum-paths 8
 exit-address-family
 address-family ipv6 unicast
  neighbor enp2s0 activate
  neighbor enp3s0 activate
  neighbor ::1 activate
  neighbor ::1 route-map cilium-nexthop in
  maximum-paths 8
 exit-address-family
exit
route-map cilium-nexthop permit 10
 set ipv6 next-hop global fd00:ff::102    ! node's real address
exit
ipv6 nht resolve-via-default              ! GLOBAL (also `ip nht ...`)
bfd
 profile fast
  transmit-interval 150
  receive-interval 150
 exit
exit
```

Measured traps (all from the lab README — each cost someone a day):

- `allow-reserved-ranges` and `nht resolve-via-default` are **global**
  commands; `% Unknown command` under `router bgp` means you're looking
  in the wrong mode, not at an old FRR. The `nht` knob matters because
  **zebra resolves learned routes' next-hops before installing them**
  — without it, routes reachable only via the default gateway sit in
  bgpd but never reach the FIB, even though `show bgp` looks perfect.
- No `next-hop-self`/`next-hop-unchanged` — the inbound route-map does
  the rewrite; eBGP to the TORs then advertises the node naturally.
- Don't mark the Cilium neighbor `passive`: Cilium doesn't listen by
  default, FRR must be ready to dial (and to accept on loopback).
- After changing the node source address, zebra may keep ECMP routes
  the kernel now rejects — visible only as the `r` flag in
  `show ip route` while `show bgp summary` looks healthy.
  `systemctl restart frr` clears it.
- Duplicate addresses on the node break source selection (the lab's
  every-VM-same-management-IP trap): make the loopback/dummy address
  the node's only global address per family, or traffic leaves with the
  wrong source and BGP-adjacent things (kubeadm joins) mysteriously
  fail. `--node-ip` declares; it does not bind.

## Pattern B — Cilium peering directly with the fabric

`CiliumBGPClusterConfig` with explicit TOR `peerAddress`es per node
group. Smallest moving parts (no per-node FRR), fine for single-homed
racks — but every TOR-facing change is a manifest change, no BFD
(short timers only), and Cilium config couples to interface addressing.
FRR side on the TOR is ordinary
`neighbor <node-addr> remote-as <node-ASN>` per node, or a listen range
when using Cilium's `autoDiscovery.mode: DefaultGateway`:

```text
bgp listen range fd00:10:0:1::/64 peer-group CILIUM
neighbor CILIUM local-as 65000 no-prepend replace-as
```

(one session per family is auto-discovered — the lowest-metric default
gateway — which is why true dual-TOR still wants pattern A.)

### Auto-discovery (DefaultGateway)

Instead of a `peerAddress`, a peer entry can set
`autoDiscovery.mode: DefaultGateway` + an `addressFamily`: Cilium
reads the node's routing table, finds that family's default gateway,
and dials it. Node scale-out/replacement self-peers with **zero
network-side change** — the FRR side needs only a listen range once:

```text
router bgp 65000
 neighbor CILIUM peer-group
 neighbor CILIUM remote-as 65001
 neighbor CILIUM local-as 65000 no-prepend replace-as
 neighbor CILIUM timers 3 9
 bgp listen range 10.1.0.0/16 peer-group CILIUM
 bgp listen range fd00:10::/64 peer-group CILIUM
 address-family ipv4 unicast
  neighbor CILIUM activate
  neighbor CILIUM route-map CILIUM-IN in
  neighbor CILIUM route-map CILIUM-OUT out
  neighbor CILIUM maximum-prefix 1000
 exit-address-family
```

(from the
[auto-discovery writeup](https://medium.com/@simardeep.oberoi/simplifying-network-management-with-ciliums-bgp-auto-discovery-feature-2f340d2225f8)
— full YAML and a Juniper equivalent in the research note.)

Trade-offs to state plainly: auto-discovery only handles *peer
establishment* (advertisements/communities/GR stay explicit); **peer
selection becomes routing-table interpretation** — whatever answers the
default route becomes a BGP peer, so a mis-provisioned default or a
multi-homed design silently peers with the wrong router. Pin intent per
node with `CiliumBGPNodeConfigOverride` (`peerAddress`/`peerASN`
override a named peer), and keep `maximum-prefix` + inbound route-maps
on the listen range so a rogue node can't flood or attract traffic.
Auto-discovery and explicit peers can coexist in one instance.

## Pattern C — WireGuard site-to-site mesh

For the site layer above A or B: FRR on NixOS site routers, one
WireGuard interface per peering (`s2svpNN`), /31 (v4) + /112 (v6)
point-to-point transfer nets, one eBGP session per family over the
tunnel (each site has its own private ASN, so site-to-site is eBGP —
"internal BGP" here means private/non-transit). NATed spokes drop the
`Endpoint` and rely on the hub's `PersistentKeepalive = 25`; add
B↔C sessions for hub-loss resilience.

**WireGuard `AllowedIPs` is cryptokey routing, not IP routing** — the
tunnel picks the peer key by destination IP, so overlapping
`AllowedIPs` across peers on one listener silently breaks (the running
config shows `allowed ips: (none)` and routing dies; field case:
OPNsense forum thread 29942). Practical rules: one WG listener per
full-table (`0.0.0.0/0`) peer, and even when FRR "owns" routing, keep
explicit per-peer remote-site subnets in `AllowedIPs` as a backstop —
it caps what an FRR route-all can attract through the tunnel. With that
in place, FRR BGP + BFD over the tunnel IPs demonstrably delivers
~2-ping failover across WAN loss and firewall-pair events (measured in
the thread: 3 sites, dual WAN, HA pairs).

**ECMP across WireGuard** — the shadowing rule and ECMP live at two
different layers and do not collide: the no-overlap rule is *within one
interface's* cryptokey table (a destination IP selects one peer key);
ECMP is *cross-interface* in the kernel FIB (the flow hash picks an
interface, then that interface looks up its single peer). Therefore:

- **One peer per interface; ECMP members are different wg interfaces.**
  A tunnel per peering/path (`wg-b1` via WAN1 endpoint, `wg-b2` via
  WAN2, or one per remote node in a node mesh). Identical AllowedIPs
  *across* interfaces is fine — independent tables; two peers with
  overlapping AllowedIPs *on one* interface shadows the second (`(none)`).
- Each interface's AllowedIPs must cover **all** subnets ECMP'd through
  it (remote site/cluster supernets), or some flows fail key lookup.
- FRR: one BGP session per tunnel, both tunnels to the same remote AS;
  `maximum-paths 8` + `bgp bestpath as-path multipath-relax`; zebra
  installs one nexthop per interface; kernel hashes **per flow**
  (`fib_multipath_hash_policy=1` for L4 spread) — one connection pins
  to one tunnel, many flows spread. Per-packet would break TCP.
- One **BFD session per member**; a member's death withdraws one
  nexthop and only flows hashed to it rehash.
- Verify: `ip route show <P>` shows a `nexthop` line per member;
  `wg show` shows no `(none)` peer; `show bgp <P>` flags members with
  `=`; `ip -4 fib match <DST>` shows which member a flow takes;
  tcpdump both tunnels to watch flows spread.

### Getting ECMP to downstream clusters

A border/router (NixOS FRR host or any BGP switch) with 2+ equal-cost
upstreams only helps the cluster if the cluster *learns* all paths —
BGP sends the best path by default:

- **eBGP from each border to the node** (each border advertises its own
  best) — the node runs `maximum-paths` and ECMP forms toward the
  borders. The usual choice toward cluster nodes; pure L2/L3 switches
  without add-path support work fine this way.
- **iBGP add-path**: `neighbor NODE addpath-tx-all-paths` from the
  transit/border so iBGP downstreams receive every path, plus
  `neighbor NODE next-hop-self` so downstream nexthops are the borders
  themselves (ECMP then resolves via the in-site IGP), plus
  `maximum-paths ibgp` on the node.
- The node FRR installs the multipath route via zebra; Cilium native
  routing forwards pod traffic into that FIB — no Cilium involvement in
  the ECMP itself.

Site router distilled (bella.network Network A):

```text
router bgp 65001
 bgp log-neighbor-changes
 no bgp ebgp-requires-policy            ! or keep it and attach filters
 no bgp default ipv4-unicast
 bgp graceful-restart
 bgp fast-convergence
 neighbor 172.31.10.1 remote-as 65002   ! tunnel /31
 neighbor 172.31.10.1 bfd               ! sub-second WAN failure detection
 neighbor 2001:db8::0:1 remote-as 65002 ! tunnel /112
 neighbor 2001:db8::0:1 bfd
 !
 address-family ipv4 unicast
  network 10.10.0.0/16
  network 172.31.10.0/31
  neighbor 172.31.10.1 activate
  neighbor 172.31.10.1 route-map FILTER-INBOUND in
  neighbor 172.31.10.1 route-map ANNOUNCE-v4 out
 exit-address-family
 address-family ipv6 unicast
  network 2001:db8:10::/48
  neighbor 2001:db8::0:1 activate
  neighbor 2001:db8::0:1 route-map FILTER-INBOUND-V6 in
 exit-address-family
```

Inter-site reachability policy = prefix-lists + route-maps on the
session (see [bgp.md](bgp.md) §Inter-site filtering); the blog's
`ge 9`/`ge 13`/`ge 17` RFC1918 bounds drop leaked aggregates while real
site prefixes pass. To inject a Kubernetes cluster into the mesh, the
site router announces the cluster's VIP pool + pod CIDR (learned via
pattern A/B inside the site) into the WG sessions — or the node FRR
peers with the site router over loopback.

## Choosing

- **A** (node-local FRR): multi-homed nodes, BFD on fabric links,
  unnumbered fabric, fabric details must stay out of manifests,
  FRR-side policy between Cilium and fabric. Costs: one FRR per node +
  the martian/nexthop incantation.
- **B** (direct peering): single-homed/simple racks, smallest parts,
  TOR config managed anyway. Auto-discovery variant for dynamic node
  fleets — at the cost of peer selection becoming routing-table
  interpretation (see above). Costs: manifests coupled to fabric, no BFD.
- **C** (WG mesh): the site-to-site layer over untrusted internet;
  combines with A or B.
- Rule of thumb: A for production multi-homed clusters with your own
  fabric; B for labs/single-homed; C for the layer above both.

## End-to-end verification

Cilium side:

- `cilium bgp peers` — per-node session state, per-family counts.
- `cilium bgp routes advertised ipv4 unicast` — what each node offers;
  the `NextHop` column must be the node's real address (after FRR's
  rewrite on the fabric side).
- `kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp
  route-policies` — the generated GoBGP policies.
- CRD conditions: `NoMatchingNode` (selector matches nothing),
  `MissingPeerConfigs` (peerConfigRef typo), `ConflictingClusterConfig`
  (two cluster configs select one node), `MissingAuthSecret`.
- Metrics: `cilium_bgp_control_plane_session_state` (1=up),
  `_advertised_routes`, `_received_routes` (labels afi/safi).
- Logs: agent `subsys=bgp-control-plane`, operator
  `subsys=bgp-cp-operator`; `as number mismatch expected ...` and MD5
  timeouts point at PeerConfig/router config skew.

FRR side: the standard playbook in
[operations.md](operations.md) — `show bgp summary` (PfxRcd > 0 toward
::1), `show bgp ... neighbors ::1 routes` (the pod CIDRs + VIPs
arriving), `show ip route <pod-prefix>` (installed, no `r` flag), then
from an external client: pod IP, VIP, and NodePort reachability.
