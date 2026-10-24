# BFD (FRR bfdd) + Cilium BGP auto-discovery — research note

**Scope**: three primary sources backing the FRR-on-NixOS skill's resilience
story (site-to-site BFD fast failover, Cilium BGP control-plane
auto-discovery, and a real-world multi-site FRR/BFD deployment). Fetched
2026-10-24. Companion notes `frr-docs.md` and `cilium-nixos-integration.md`
are untouched; this note adds source evidence they don't cover.

Sources:

1. Simardeep Oberoi, "Simplifying Network Management with Cilium's BGP
   Auto-Discovery Feature", Medium, 2025-06-27 —
   <https://medium.com/@simardeep.oberoi/simplifying-network-management-with-ciliums-bgp-auto-discovery-feature-2f340d2225f8>
2. FRR official BFD documentation —
   <https://docs.frrouting.org/en/latest/bfd.html> (citations below use
   anchors relative to this base URL).
3. OPNsense forum thread "[FIXED] Wireguard multi site to site with FRR
   routing allowed ips: (none)" —
   <https://forum.opnsense.org/index.php?topic=29942.0>

---

## 1. Medium article — Cilium BGP auto-discovery

**Publication context**: practitioner blog post (Medium, ~8 min read),
published **2025-06-27** by @simardeep.oberoi. Written from a data-center
Kubernetes-operator perspective; it is an explainer/how-to, not official
Cilium docs, but all CRD fields shown match the Cilium BGP control plane
API (`cilium.io/v2`).

### What the feature is

Cilium's BGP **auto-discovery** (in the BGP control plane) removes the need
to statically configure each node's `peerAddress`. In **`DefaultGateway`**
mode, Cilium reads the node's existing routing table, finds the default
gateway for the requested address family, and automatically initiates a BGP
session to that gateway. Rationale given in the article: traditional BGP
peering requires knowing every peer's IP/ASN up front, which fights the
"cattle, not pets" model of autoscaling/ephemeral clusters; the default
gateway is "already known to the node through standard routing protocols",
so no extra discovery mechanism is needed.

### Cilium side (verbatim YAML)

`CiliumBGPClusterConfig` with auto-discovery for both families
(`spec.bgpInstances[].peers[].autoDiscovery`):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: datacenter-bgp
spec:
  nodeSelector:
    matchLabels:
      bgp-enabled: "true"
  bgpInstances:
  - name: "main-instance"
    localASN: 65001
    localPort: 179
    peers:
    - name: "tor-autodiscovery-ipv4"
      peerASN: 65000
      autoDiscovery:
        mode: "DefaultGateway"
        defaultGateway:
          addressFamily: ipv4
      peerConfigRef:
        name: "datacenter-peer-config"
    - name: "tor-autodiscovery-ipv6"
      peerASN: 65000
      autoDiscovery:
        mode: "DefaultGateway"
        defaultGateway:
          addressFamily: ipv6
      peerConfigRef:
        name: "datacenter-peer-config"
```

`CiliumBGPPeerConfig` referenced by the peers (MD5 auth, aggressive timers,
graceful restart, eBGP multihop, transport, AFs + advertisement label
matching):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: datacenter-peer-config
spec:
  authSecretRef: bgp-auth-secret
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  ebgpMultihop: 2
  transport:
    peerPort: 179
  families:
  - afi: ipv4
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "datacenter-bgp"
  - afi: ipv6
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "datacenter-bgp"
```

`CiliumBGPNodeConfigOverride` — per-node router ID / ASN / port / source
address, and the escape hatch for multi-homed nodes (`peerAddress` +
`peerASN` **overrides** auto-discovery for a given peer):

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPNodeConfigOverride
metadata:
  name: edge-worker-01
spec:
  bgpInstances:
  - name: "main-instance"
    routerID: "10.1.0.200"
    peers:
    - name: "tor-autodiscovery-ipv4"
      localAddress: "10.1.0.200"
    - name: "secondary-tor"
      localAddress: "10.2.0.200"
      peerAddress: "10.2.0.1"     # override auto-discovery for secondary path
      peerASN: 65000
```

Hybrid config showing auto-discovery and manual peers coexisting in one
instance; a "high-performance" timer set (hold 3 s / keepalive 1 s /
connect-retry 1 s / GR restart 5 s); and advertisements
(`CiliumBGPAdvertisement` with communities for PodCIDR, Service LB IP with
`aggregationLengthIPv4: 24` / `aggregationLengthIPv6: 64`, and
`CiliumPodIPPool` selector-based advertisement) are all in the article and
use only documented v2 CRD fields.

### Peer-router side (verbatim FRR config)

What the ToR router (FRR) must do: a peer-group plus **dynamic neighbor
listen ranges** so any node in the pod ranges can connect without per-node
config. Note the `local-as 65000 no-prepend replace-as` line and the
per-AF `maximum-prefix`:

```
router bgp 65000
 bgp router-id 10.0.0.1
 bgp log-neighbor-changes

 # Peer group for Cilium nodes
 neighbor CILIUM peer-group
 neighbor CILIUM remote-as 65001
 neighbor CILIUM local-as 65000 no-prepend replace-as
 neighbor CILIUM timers 3 9
 neighbor CILIUM timers connect 5

 # Enable dynamic neighbor discovery
 bgp listen range 10.1.0.0/16 peer-group CILIUM
 bgp listen range fd00:10::/64 peer-group CILIUM

 address-family ipv4 unicast
  neighbor CILIUM activate
  neighbor CILIUM route-map CILIUM-IN in
  neighbor CILIUM route-map CILIUM-OUT out
  neighbor CILIUM maximum-prefix 1000
 exit-address-family

 address-family ipv6 unicast
  neighbor CILIUM activate
  neighbor CILIUM route-map CILIUM-IN-V6 in
  neighbor CILIUM route-map CILIUM-OUT-V6 out
  neighbor CILIUM maximum-prefix 1000
 exit-address-family
```

The article also gives the Juniper equivalent (`dynamic-neighbor { 10.1.0.0/16; fd00:10::/64; }` inside a `group cilium-nodes` with `type external; local-as 65000; peer-as 65001;`).

### Operational notes from the article

Verification commands it recommends: `cilium bgp peers`, `cilium bgp routes
advertised`, `cilium bgp routes received`, `ip route show default` /
`ip -6 route show default` (to check what the gateway discovery will find),
`kubectl logs -n kube-system ds/cilium -c cilium-agent | grep bgp`, and
`kubectl get/describe` on the three BGP CRDs.

**Claimed benefits** (paraphrased): peer config becomes generic and portable
across IaC templates; node replacement/scale-out auto-establishes sessions
with no network-side change; no additional service-discovery machinery;
auto-discovery only handles *peer establishment* — advertisements,
communities, local-preference, and GR parameters all remain explicitly
controlled.

**Stated limitations / trade-offs** (quoted intent, condensed): "teams lose
some explicit control over peer selection"; troubleshooting "requires
understanding how Cilium interprets routing tables"; the feature "assumes
that the default gateway is the appropriate BGP peer, which is true in most
standard data center architectures but might not hold in more complex
network designs with multiple routing layers"; and in "complex multi-homed
environments with nuanced routing policies, the automatic selection might
not always align with intended designs."

---

## 2. FRR BFD protocol reference (docs.frrouting.org/en/latest/bfd.html)

Base URL for all anchors: `https://docs.frrouting.org/en/latest/bfd.html`.
Fetched in full 2026-10-24 (page complete through the "Debugging" section).

### 2.1 Protocol model

- BFD detects faults "in the bidirectional path between two forwarding
  engines … with potentially very low latency" — **RFC 5880**, extended by
  RFC 5881 (single-hop), 5882 (generic application), 5883 (multihop).
  (`#bfd`)
- FRR has had **two** BFD implementations: **PTM** (external daemon) and
  **`bfdd`** (in-tree, talks to remote peers). The page documents `bfdd`.
  (`#bfd`)
- **Async mode** (periodic control packets, the RFC 5880 default) is the
  baseline; the page documents the two optional modes explicitly:
  - **`echo-mode`**: echo packets test the forwarding path; the remote
    loops them back. **Caveat**: "If you are not using distributed BFD then
    echo mode works only when the peer is also FRR" — i.e. **between
    heterogeneous boxes, don't use echo** (use async control packets).
    Echo is **not supported on multi-hop setups** (RFC 5883 §3). After
    enabling echo, "it is recommended that the transmission interval of
    control packets … be increased … For example: `transmit-interval 2000`"
    to save bandwidth. Disabled by default. (`#peer-profile-configuration`)
  - **`demand-mode`**: asks the peer to stop periodic control transmission;
    the path is verified only when a Poll Sequence fires (when packet
    contents would change). **Warning**: nothing initiates a Poll Sequence
    on its own — "enabling demand mode on both ends of a connection without
    echo-mode can leave a failed path undetected: neither system transmits
    and neither runs a detection timer. Pair demand mode with echo-mode, or
    ensure some other mechanism verifies the path." Unlike echo, demand
    mode works on multihop. (`#peer-profile-configuration`)
- **Control-plane-independent bit (C-bit)**: FRR exposes it only through the
  BGP knob `neighbor <peer> bfd check-control-plane-failure` — "Allow to
  write CBIT independence in BFD outgoing packets. Also allow to read both
  C-BIT value of BFD and lookup BGP peer status … useful when a BFD down
  event is caught, while the BGP peer requested that local BGP keeps the
  remote BGP entries as staled … the case when graceful restart is enabled,
  and it is wished to ignore the BFD event while waiting for the remote
  router to restart." Default is **off** (FRR pays attention to BFD down
  notifications and does not set C-bit). (`#bgp-bfd-configuration`)
- **Address families**: peer grammar `peer <A.B.C.D|X:X::X:X>` covers IPv4
  and IPv6; `local-address` is **mandatory for IPv6** peers. (`#bfdd-commands`)
- **Single-hop vs multihop**: `multihop` "tells the BFD daemon that we
  should expect packets with TTL less than 254 … and to listen on the
  multihop port (4784)" — i.e. multihop BFD = **UDP 4784**; single-hop BFD
  = **UDP 3784** (the page itself only names 4784; 3784 per RFC 5881).
  `minimum-ttl (1-254)` (default 254) tightens validation for multihop
  sessions. (`#bfdd-commands`, `#peer-profile-configuration`)
- **Distributed BFD**: control-plane/data-plane split. `bfdd --dplaneaddr
  unix:/var/run/frr/bfdd_dplane.sock | ipv4:127.0.0.1 | ipv6:[::1][:port]`
  (default port **50700**; append `c` for client mode, e.g. `ipv4c:`).
  With `--dplaneaddr`, bfdd stops originating sessions and offloads to the
  connected data plane: the data plane sends/receives control+echo packets,
  reports state changes, keeps counters; bfdd keeps session config, counter
  queries, and redistribution into bgpd/ospfd/…. Data planes declare
  capabilities via `BFD_DP_CAPABILITIES` (a plane that never sends it is
  treated as supporting none); a session needing an undeclared feature is
  **not offloaded** and bfdd runs it itself. `BFDDP_CAP_SESSION_AUTH`:
  authenticated sessions are only offloaded to a data plane that declared
  it **and only over a UNIX socket or loopback** — otherwise keys "would
  otherwise be written in the clear"; such a session falls back to bfdd,
  which logs the refusal. `--dplaneaddr` is documented as "an internal,
  trusted interface". (`#starting-bfd`, `#distributed-bfd`)

### 2.2 Daemon startup and config file

- BFD config lives in the integrated `/etc/frr/frr.conf`. Per-daemon files
  (`bfdd.conf`) still get *read* during the mgmtd transition but are **no
  longer written** by `write memory` — transition-only, then remove.
  (`#starting-bfd`)
- bfdd-specific invocation options: `--dplaneaddr` (above) and
  `--vrfs <vrf-list>` — VRFs bfdd listens on; **default: all VRFs present,
  including the default VRF** (which must be listed literally as `default`,
  e.g. `--vrfs public,vrf1,vrf2`). (`#starting-bfd`)

### 2.3 Core config: `bfd` node, peers, profiles

```
bfd
 peer A.B.C.D|X:X::X:X [multihop] [local-address A.B.C.D|X:X::X:X]
                       [interface IFNAME] [vrf NAME]
 profile WORD
```

Peer/profile **shared** session parameters (`#peer-profile-configuration`):

| Command | Range / default | Notes |
|---|---|---|
| `detect-multiplier (1-255)` | default **3** | Multiplier applied to the larger of (local transmit-interval, remote receive-interval) to get the peer's detection timeout. Doc example: local DM 3 + tx 300 ms + remote rx 200 ms ⇒ remote detects loss after **900 ms**. |
| `receive-interval (10-4294967)` | default **300 ms** | Min interval this system can receive control packets. |
| `transmit-interval (10-4294967)` | default **300 ms** | Desired control-packet transmission interval (less jitter). |
| `echo receive-interval <disabled\|(10-4294967)>` | default **50 ms** | `disabled` = this system doesn't want echo packets. |
| `echo transmit-interval (10-4294967)` | default **50 ms** | |
| `echo-mode` | **off** by default | See caveats in §2.1. |
| `demand-mode` | **off** by default | Must pair with echo or another verifier. |
| `shutdown` | — | Disabled peer sends "administrative down" to the remote. |
| `passive-mode` | default **active** | Wait for peer's control packets before replying (star-hub center). |
| `minimum-ttl (1-254)` | default **254** | Multihop only; tighten anti-cross-session validation. |
| `log-session-changes` | off | Log transitions into Up and out of Up. |
| `authentication key-chain NAME` | — | Key-chain of crypto-algorithm + key-string tuples; only **cleartext** and **hmac-sha1** usable; key-string length limits per RFC 5880 (1–16 bytes cleartext, up to 20 hmac-sha1). A key-chain with **no usable key keeps the session down** (never falls back to unauthenticated). `show bfd peer` distinguishes `authentication.enabled` (key in effect) vs `configured` (key-chain only). |
| `authentication algorithm meticulous` | — | Meticulous mode for hmac-sha1 key-chains. |

**Profile semantics** (`peer BFDPROF` inside a peer, `#bfd-peer-specific-commands`):

- Per-peer non-default parameters **override** the profile.
- A `profile` command may reference a **not-yet-existing** profile; it is
  applied once the profile is created.
- Updating a profile applies the new values to all peers using it "**without
  interruptions**" (no session reset).
- **Deleting a profile resets all its peers to default values.**

### 2.4 BGP integration (`#bgp-bfd-configuration`)

All inside the BGP node; X = `<A.B.C.D|X:X::X:X|WORD>`:

| Command | Behavior |
|---|---|
| `neighbor X bfd` | Listen for BFD events for this neighbor's address. BFD down ⇒ bgpd **immediately shuts down** the BGP connection; BFD up ⇒ bgpd is notified to reconnect. |
| `neighbor X bfd strict [hold-time <seconds>]` | BGP **cannot establish** until the BFD session is up; BFD session down **or administratively down** ⇒ BGP session closed **immediately**. With `hold-time`: when the BGP hold-time is zeroed, BGP defers the notification on BFD-down until the hold-time expires — avoids session flapping on transient BFD drops while still bringing the session down on sustained failure. |
| `neighbor X bfd check-control-plane-failure` | C-bit write + remote C-bit read (see §2.1); use with graceful restart to ignore BFD-down while the peer restarts. Default: disabled. |
| `neighbor X bfd profile BFDPROF` | Like `bfd`, but applies the named BFD profile to sessions it creates or that already exist. |

Docs example (`#configuration`):

```
bfd
 peer 192.168.0.1
   no shutdown
 !
!
router bgp 65530
 neighbor 192.168.0.1 remote-as 65531
 neighbor 192.168.0.1 bfd
 neighbor 192.168.0.2 remote-as 65530
 neighbor 192.168.0.2 bfd
 neighbor 192.168.0.3 remote-as 65532
 neighbor 192.168.0.3 bfd
!
```

Profile/multihop/VRF patterns from the same section:

```
bfd
 profile fast
  receive-interval 150
  transmit-interval 150
 !
 peer 192.168.0.6
  profile fast
  no shutdown
 !
 peer 192.168.0.7
  profile fast
  receive-interval 500          # profile override on the peer
  no shutdown
 !
 peer 192.168.0.1 interface eth0
  no shutdown
 !
 peer 192.168.0.2 multihop local-address 192.168.0.3
  shutdown
 !
 peer 192.168.0.3 vrf foo
  shutdown
 !
 no peer 192.168.0.3 vrf foo    # remove
```

### 2.5 Static-route BFD monitoring (`#bfd-static-route-monitoring-configuration`)

A monitored static route is installed in the RIB only while the BFD session
to the gateway is up; BFD down ⇒ route removed.

```
ip route A.B.C.D/M A.B.C.D bfd [{multi-hop|source A.B.C.D|profile BFDPROF}]
ipv6 route X:X::X:X/M [from X:X::X:X/M] X:X::X:X bfd [{multi-hop|source X:X::X:X|profile BFDPROF}]
```

Uninstalled monitored routes **do not appear** in `show ip route` / `show
ipv6 route` — use `show bfd static route [json]`, which reports per-route
status (`installed` / `uninstalled`) grouped by peer, e.g.:

```
  Route groups:
    rtg1 peer 172.16.0.1 (status: uninstalled):
        2001:db8::100/128
  Next hops:
    VRF default IPv4 Unicast:
        192.168.100.0/24 peer 172.16.0.1 (status: uninstalled)
```

Other protocols' BFD knobs (same page): IS-IS `isis bfd [profile PROF]`;
OSPF `ip ospf bfd [multiplier min-rx-int min-tx-int] [quick]` (`quick` keeps
the BFD session alive after the OSPF neighbor vanishes so re-add is
immediate); OSPF6 `ipv6 ospf6 bfd [profile PROF]`; PIM `ip pim bfd [profile
PROF]`; RIP `ip rip bfd [profile PROF]` + `bfd default-profile PROF`; and
`openfabric bfd`. All auto-create a BFD session per discovered adjacency.

### 2.6 Show / status commands (`#status`)

| Command | Output |
|---|---|
| `show bfd [vrf NAME] peers [json]` | All peers: ID, Remote ID, Active/Passive mode, Status, Downtime, (remote) diagnostics, Peer Type (`configured`), RTT min/avg/max (calculated on Linux for IPv4 echo), Profile, local timers (detect-multiplier, rx/tx interval, **tx interval actual with jitter**, detection timeout, echo rx/tx), remote timers. |
| `show bfd [vrf NAME] peer <WORD\|A.B.C.D\|X:X::X:X> [multihop\|local-address …\|interface …] [json]` | Single peer, same detail. JSON keys include: `multihop`, `peer`, `local`, `vrf`, `interface`, `authentication{enabled,configured}`, `id`, `remote-id`, `passive-mode`, `status`, `diagnostic`, `profile`, `receive-interval`, `transmit-interval`, `transmit-interval-actual`, `detection-timeout`, `echo-*-interval`, `detect-multiplier`, `remote-*`, `rtt-min/avg/max`. |
| `show bfd [vrf NAME] peers brief [json]` | Table: SessionId, LocalAddress, PeerAddress, Status, Profile; leading "Session count: N". |
| `show bfd peers counters` / `show bfd peer <addr> counters [json]` | Per-peer: control/echo packet in/out, session up/down events, zebra notifications, Rx fail packet. |
| `clear bfd peers counters` | Resets **packet** counters only (up/down/zebra counters retained — visible in the docs' before/after). |
| `show bfd static route [json]` | Monitored static routes and status (§2.5). |
| `show bfd distributed` | Data-plane connection stats: FD, capabilities bitmask, input/output bytes (+peak), messages, full/usage events. |

Sample detection math from live output: local DM 3, tx 300 ms, remote rx/tx
1000 ms ⇒ local **detection timeout 3000 ms**; `transmit-interval (actual
with jitter)` shows e.g. 970 ms / 790 ms.

### 2.7 Debugging (`#debugging`)

Global debug verbosity first: `log file /var/log/frr/frr.log debugging` /
`log syslog debugging`. Then:

| Command | Toggles |
|---|---|
| `debug bfd distributed` | Data-plane (distributed BFD) rx/tx messages, connection events. |
| `debug bfd network` | Socket failures; unexpected BFD packets not belonging to registered peers. |
| `debug bfd peer` | Peer creation/removal, peer state changes. |
| `debug bfd zebra` | Zebra messages: interfaces, local addresses, VRF, daemon peer registrations. |

### 2.8 BFD authentication (`#bfd-authentication-overview`, `#bfd-authentication-configuration`)

Key-chain based; applies directly to a peer or via a profile (the
profile-based method scales better). Two verbatim examples:

```
key chain 0
 key 0
  key-string secret123456
  cryptographic-algorithm cleartext
!
bfd
 profile 0
  authentication key-chain 0
!
bfd
 peer 10.0.1.2 interface eth-rt2
  profile 0
```

Same shape with `cryptographic-algorithm hmac-sha-1` (plus `authentication
algorithm meticulous` for meticulous mode). Warning: the `simple`/cleartext
algorithm sends the key string in the clear — visible in tcpdump captures.

### 2.9 Documented caveats checklist (BFD ↔ BGP)

1. Echo mode only between two FRR instances unless distributed BFD is used.
2. Echo mode unsupported on multihop sessions (RFC 5883 §3).
3. Demand mode on both ends without echo (or another verifier) can leave a
   failed path permanently undetected.
4. `strict` couples session bring-up to BFD: no BFD ⇒ no BGP, and
   admin-down of the BFD peer tears BGP down immediately.
5. Without `check-control-plane-failure` (C-bit), BFD-down during a peer's
   graceful restart tears down routes the GR receiver was supposed to keep
   stale — the knob exists precisely for the GR case.
6. Deleting a BFD profile silently resets its peers to defaults.
7. A session whose key-chain has no usable key stays down by design.
8. Multihop BFD needs the `multihop` keyword + `local-address` (mandatory
   for IPv6 regardless) and `minimum-ttl` hardening.

---

## 3. OPNsense forum thread — WireGuard + FRR BGP/BFD multi-site

**Thread**: "[FIXED] Wireguard multi site to site with FRR routing allowed
ips: (none)", OPNsense Forum → English Forums → Virtual private networks.
<https://forum.opnsense.org/index.php?topic=29942.0> (all posts also on
`.15`). OP **nzkiwi68**, first post **2022-08-20 10:27:32**. Fetched
2026-10-24.

**Environment (stated)**: OPNsense **22.7.2**, WireGuard (with
**wireguard-kmod**), a **10-wireguard CARP hook script** for HA failover,
FRR plugin with **BGP and BFD**. Topology: 3 sites (A/B/C), each dual-WAN
(WAN1+WAN2) behind an HA firewall pair; site-to-site WireGuard tunnels with
FRR BGP dynamic routing on top.

### What happened

- Two sites worked "great" — WAN failover cost **~2 pings**.
- Adding the third site, the WireGuard **running config** showed a peer
  with **`allowed ips: (none)`** even though the peer was configured with
  `allowed ips 0.0.0.0/0`, and routing broke. Quote: *"it seems wireguard
  doesn't tolerate more peers with allowed ips of 0.0.0.0/0 set against the
  same local listener."*
- The OP's design intent: *"I want to do all my routing using FRR, so I
  don't want to set the peer allowed IP addresses in wireguard plus control
  IP addresses in FRR BGP"* — i.e. use WG purely as transport and let BGP
  own the routing table.

### Root cause (reply by Maurice)

> "Correct. You can't assign multiple endpoints with overlapping allowed IPs
> to the same local wg interface. That's just not how WireGuard works. To
> put it simply, it uses the IP address to determine which key to use for
> encryption / decryption. For multiple 0.0.0.0/0 endpoints, you need to
> create an individual local wg interface for each endpoint."

### Resolution

OP created **multiple WG local listeners, one per endpoint**, then went
further and dropped `0.0.0.0/0` entirely: each peer now lists the specific
expected remote networks. Rationale (quoted intent): a peer had become the
preferred gateway for traffic that shouldn't go there — "probably a weird
combination of starting and stopping FRR and incorrectly me setting the
gateway priority lower on a gateway to the remote FRR BGP endpoint" — and
explicit per-peer networks are "safer that the local FRR will not inject
perhaps a route all to remote WG peer that you don't want."

**Final working state** (his summary): 3 sites, all OPNsense HA, dual WAN,
WG tunnels site-to-site and multi-WAN, **FRR with BGP and BFD** for
routing, wireguard-kmod + the CARP hook script. Measured behavior:

- Pull any WAN at any site ⇒ **max 2 pings** lost before recovery.
- Shut down any site's primary firewall ⇒ **~2 pings** lost.
- Restart the primary ⇒ failback "very seamless", **1–2 pings** lost.

A later poster (**mokaz**) necrobumped asking for an anonymized config
share and whether each distinct local WG instance listens on a **dedicated
UDP port** (his own testing suggested yes). No reply is visible in the
thread.

### Lessons for an FRR-BFD operator

1. WireGuard's crypto routing is the constraint: overlapping allowed-ips
   across peers on one listener silently break (peer shows `allowed ips:
   (none)` in the running config). One listener per 0.0.0.0/0 peer, or
   explicit per-peer network lists.
2. Keeping explicit per-peer allowed networks is defense-in-depth even when
   FRR "owns" routing — it caps what FRR can accidentally attract through
   the tunnel.
3. FRR BGP + BFD over WireGuard on OPNsense 22.7 (FRR 8.x era; exact FRR
   version not stated in-thread) demonstrably delivers sub-3-ping failover
   across WAN loss and firewall HA events — the timers/BFD stack works.
4. Watch interactions between FRR restarts and OS gateway priorities on the
   tunnel endpoints; mis-set priority let a WG peer become an unintended
   preferred gateway.

---

## 4. Resilience picture — how the layers compose

Synthesis across the three sources for site-to-site (or node-to-ToR)
resilient L3 networking:

- **BFD is the fast-detection layer; BGP hold timers are the slow fallback.
  **With `neighbor … bfd`, FRR tears the BGP session down the instant BFD
  declares the path dead (900 ms with 300 ms timers and DM 3; ~150–450 ms
  with the doc's `profile fast`), instead of waiting out a 9–180 s hold
  time. The OPNsense thread is the field proof: 2 pings lost across WAN or
  firewall-pair failure. Pitfall: BFD only helps where the forwarding path
  actually dies — a blackhole *above* the BFD-monitored hop (e.g. remote
  peer process crash without GR) needs the GR/BFD C-bit interplay below.
- **Echo mode is a homogeneous-club feature.** It works FRR↔FRR only (or
  with distributed BFD offload); between heterogeneous boxes (FRR ↔
  Cilium/goBFD/Juniper) run **async control-packet BFD** — the docs' echo
  caveat verbatim. Echo is also dead on multihop (RFC 5883 §3), which
  matters for tunneled/routed-over-fabric peers: use control packets there.
- **BFD strict mode hard-couples bring-up; use it deliberately.** `bfd
  strict` refuses BGP establishment until BFD is up and kills the session
  on admin-down — great for "never route over an unverified path", but it
  converts BFD flaps straight into BGP flaps; the optional `hold-time`
  damps exactly that. Non-strict `bfd` (default) lets BGP come up first and
  reacts to BFD events afterward — friendlier across asymmetric configs.
- **Graceful restart + `check-control-plane-failure` (C-bit) keep BFD from
  defeating GR.** BFD-down during a peer's control-plane restart would
  normally purge "stale" routes the GR helper was preserving; with the
  C-bit knob FRR marks its packets control-plane-independent and reads the
  peer's C-bit, ignoring BFD-down while the peer restarts. Both sides must
  agree on roles: **restarter** signals via BGP GR, **helper** honors it
  and needs the BFD C-bit configured. GR without the C-bit knob + BFD =
  GR neutered by fast detection.
- **ECMP turns single-path BFD events into partial, not total, loss.**
  Multipath BGP (FRR `maximum-paths`) plus per-path BFD sessions means one
  path's BFD-down just withdraws that nexthop; forwarding continues over
  the rest. Composes naturally with the multi-instance/secondary-ToR
  override pattern (`CiliumBGPNodeConfigOverride` `peerAddress` overriding
  auto-discovery) for multi-homed nodes. Pitfall: BFD sessions must track
  every ECMP member — a path with BGP but no BFD silently reverts to slow
  convergence; and Cilium's own timers (GR `restartTimeSeconds`, hold/keep)
  must be sane on **every** instance, not just the primary.
- **Cilium auto-discovery removes peer config as a failure domain** — new
  nodes/replaced nodes self-peer with the default gateway, and the FRR side
  needs only `bgp listen range <pod-cidr> peer-group` once. But it moves
  the risk into *routing-table interpretation*: whatever answers the node's
  default route becomes a BGP peer, so a mis-provisioned default route or a
  multi-homed design silently peers with the "wrong" router. Pin intent
  with `CiliumBGPNodeConfigOverride`, and keep `maximum-prefix` + inbound
  route-maps on the listen range (the Medium article's FRR snippet does
  both) so a rogue/dupe node can't flood or attract traffic.
- **Transport and routing must fail independently.** The OPNsense thread:
  WireGuard allowed-ips is crypto routing, not IP routing — letting FRR
  "own" routing via `0.0.0.0/0` collided with WG's per-peer key selection.
  Lesson: keep an explicit allowlist of remote prefixes per tunnel peer as a
  backstop (defense against FRR injecting a route-all), and one WG listener
  per full-table peer. For NixOS site meshes (WireGuard + FRR), replicate
  that: per-peer `AllowedIPs` of the remote site's subnets, FRR BFD on the
  tunnel IPs.
- **Timer coherence across layers is the hidden failure mode.** Fast
  detection is only as fast as the *slowest* participating layer: FRR
  150 ms BFD is wasted if the Cilium peer config holds holdTime 90 s; a 1–3
  s Cilium "high-performance" timer set is pointless if BFD runs 300 ms ×3
  on one side and the other side's hold time is 180 s. Set BFD ≪ BGP
  hold ≪ GR restart time, and keep `detect-multiplier` ≥ 2–3 on lossy
  WAN links to avoid false positives (the thread's "2 pings" was bought
  with BFD; flapping sessions from DM 1 would have been worse than slow
  detection).
- **Static routes can ride BFD too** (`ip route … bfd`): for stub
  attachments that don't run BGP at all, a BFD-monitored static route gives
  the same sub-second withdrawal/installation without a routing protocol —
  useful for the non-BGP ends of a site-to-site design.
- **Operational symmetry: verify both sides of every session.** `show bfd
  peers brief` (are all sessions up?), `show bfd peers counters` (is
  control traffic flowing both ways? `Rx fail` climbing?), and BGP-side
  `show bgp summary` together catch half-configured pairs — the classic
  being one side with `neighbor … bfd` and the other without, where the
  unprotected side converges slowly and asymmetrically.

---

## 5. Fetch gaps

- **Medium article**: fetched the full text directly from medium.com — no
  paywall, no archive fallback needed. Code blocks were preserved
  verbatim; some YAML lost blank-line/indent formatting in extraction
  (normalized above without changing field names or values). Author
  credentials beyond the handle (@simardeep.oberoi) and date (2025-06-27)
  are not stated on the page.
- **FRR BFD docs**: page fetched in full, complete through the final
  "Debugging" section; no truncation. Three items from the research brief
  are **not** stated on the page: (a) the term "async mode" never appears —
  periodic control-packet mode is only implied as the RFC 5880 default; (b)
  single-hop UDP port **3784** is never named (only the multihop port 4784
  is; 3784 is cited here from RFC 5881); (c) RFC 5880 "function units
  (ingress/egress)" architecture language is not mirrored in the FRR page.
- **OPNsense thread**: pages `.0` and `.15` fetched; `.15` contains the
  whole thread (OP + Maurice + OP resolution + mokaz's necropost) — no
  further pagination exists. The OP's two screenshots (running-config
  snippets) are image attachments whose text is only partly quoted in the
  posts; the quoted fragments above are the complete textual record.
  mokaz's question has no visible reply. No FRR version is stated in-thread
  (OPNsense 22.7.2 implies FRR 8.2-era os-frr; inference only).
