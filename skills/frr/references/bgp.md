# BGP configuration reference

Exact documented syntax from the
[BGP chapter](https://docs.frrouting.org/en/latest/bgp.html) of the FRR
docs (fetched 2026-10-24). Where availability matters, check the
versioned docs for your release — see §Version-dependent defaults.

## Instance basics

```
router bgp ASN                  ! ASN as number or dotted pair
 bgp router-id A.B.C.D          ! REQUIRED (see below)
```

- Router-ID defaults to the largest interface IPv4 address via zebra;
  without one it stays 0.0.0.0 and sessions never establish. Set it
  explicitly in generated configs.
- VRFs: `router bgp ASN vrf VRFNAME` ties an instance to a kernel VRF
  (same AS may repeat across VRFs). Views (route-server/looking-glass,
  no kernel install): `router bgp ASN view NAME`. A BGP speaker without
  kernel install: `bgp no-rib` (or daemon flag `-n`).

## Peering: eBGP and iBGP

```
neighbor PEER remote-as ASN|internal|external|auto
```

`internal`/`external` enforce same/different AS at OPEN; `auto` learns
the ASN from OPEN. First neighbor command must be `remote-as`.

| Situation | Knob |
|---|---|
| Peer not directly connected | `neighbor PEER ebgp-multihop` (and if the peer IP resolves only via the default route: `ip nht resolve-via-default` — a **global** command) |
| Single-hop eBGP over loopbacks | `neighbor PEER disable-connected-check` |
| GTSM (TTL security) | `neighbor PEER ttl-security hops N` — **mutually exclusive with ebgp-multihop** |
| Rewrite next-hop to self | `neighbor PEER next-hop-self [force]` (force: also iBGP-learned) |
| Leave attributes untouched | `neighbor PEER attribute-unchanged [{as-path\|next-hop\|med}]` |
| Accept own AS in path (N times / origin-only) | `neighbor PEER allowas-in [(1-10)\|origin]` — eBGP only; alternative PE/CE style: `neighbor PEER as-override` |
| Route reflector | `neighbor PEER route-reflector-client`, `bgp cluster-id A.B.C.D` |

- Dynamic listeners (Cilium `DefaultGateway` auto-discovery pairs with
  this): `bgp listen range A.B.C.D/M peer-group PGNAME` + `bgp listen
  limit N` (default 100).
- `neighbor PEER description …` and `bgp log-neighbor-changes` (on in
  the datacenter profile) pay for themselves in forensics.

## Address families

- Default: **IPv4 unicast is on for every neighbor**; other families
  need explicit activation inside the AF block:
  ```
  address-family ipv6 unicast
   neighbor 2001:DB8::1 activate
   network 2001:DB8:5009::/64
  exit-address-family
  ```
- The standard dual-stack idiom: `no bgp default ipv4-unicast` at the
  top, then explicit `neighbor X activate` per family.
- Show commands take `[afi] [safi]` (`show bgp ipv6 unicast ...`);
  legacy `show ip bgp` = `show bgp ipv4 unicast`; a **bare `show bgp`
  is the IPv6 table** — a classic surprise.

## Originating routes

| Method | Command | Caveats |
|---|---|---|
| Announce a prefix | `network A.B.C.D/M` (inside the AF) | `bgp network import-check` (default on ≥ 7.4) requires the prefix to exist in the local RIB first |
| Connected / static / kernel | `redistribute connected\|static\|kernel [route-map RM]` | carries the source's admin distance into best-path |
| Whole kernel table | `redistribute table N` / `table-direct N` | — |
| Aggregate | `aggregate-address A.B.C.D/M [as-set] [summary-only]` | a more-specific must already exist **in the BGP table** (RIB alone is not enough) |
| Default to one peer | `neighbor PEER default-originate [route-map RM]` | bgpd never announces 0.0.0.0/0 unless told |

## BGP unnumbered and RFC 8950 (IPv4 NLRI over IPv6 next-hops)

The node-local-FRR/Cilium pattern (see [cilium.md](cilium.md)).

- Interface peering: `neighbor IFACE interface [v6only] remote-as
  <internal|external|auto|ASN>` — bgpd uses the interface address (IPv4
  /30,/31) or the peer's IPv6 link-local. Point-to-point links only.
- `neighbor PEER capability extended-nexthop` — advertised v4 routes
  get an IPv6 next-hop. **Auto-enabled when peering over a v6
  link-local address**; explicit when peering over v6 global addresses.
- `bgp ipv6-auto-ra` (default on) has bgpd ask zebra to send IPv6 RAs
  for unnumbered discovery.
- Next-hop preference when both global and link-local received: default
  installs link-local; `nexthop prefer-global` (per AF, or
  `set ipv6 next-hop prefer-global` in a route-map) installs the global.

## Session knobs

- Timers: `neighbor PEER timers KEEPALIVE HOLD` (datacenter profile
  default 3/9; traditional 60/180). `neighbor PEER timers connect N`.
- Auth: `neighbor PEER password PASSWORD` (TCP MD5; raise
  `net.core.optmem_max` at scale).
- Maintenance: `neighbor PEER shutdown [message ...]` (RFC 8203
  graceful Cease; keeps config), global `bgp shutdown`.
- Don't casually use `dont-capability-negotiate` — it disables
  unnumbered, hostname, AS4, addpath, route refresh, ORF, and graceful
  restart negotiation all at once.

## Policy: filters, route-maps, applying changes

Per-neighbor application (inside the AF for directional effect):

```
neighbor PEER prefix-list NAME [in|out]
neighbor PEER filter-list NAME [in|out]     ! as-path access-list
neighbor PEER route-map NAME [in|out]
```

Building blocks:

```
ip prefix-list NAME seq N permit|deny PREFIX [le L] [ge G]  ! no le/ge = exact
bgp as-path access-list WORD permit|deny LINE               ! _ = AS boundary
bgp community-list standard NAME permit|deny COMMUNITY…     ! e.g. 65001:100, no-export
route-map NAME permit|deny ORDER
 match ip address prefix-list PL
 set local-preference 200
 set community 65001:100 additive
 on-match next / continue N / call OTHER
```

Route-map semantics that bite: match+permit applies sets and exits (add
`on-match next` to fall through); end of the map is an **implicit deny**
(add a trailing empty `permit` to change that); an undefined prefix-list
matches nothing, an undefined access-list-style reference matches
everything.

Applying changes to a live session:

- **Outbound** policy: takes effect on new updates; force with
  `clear bgp PEER [soft] out`.
- **Inbound**, peer supports route-refresh: `clear bgp PEER [soft] in`
  re-evaluates everything, including previously filtered routes — no
  stored copy needed.
- **Inbound**, need history: `neighbor PEER soft-reconfiguration
  inbound` stores the unmodified Adj-RIB-In (memory cost), then
  `clear bgp PEER soft in`.
- Hard reset: `clear bgp PEER|*|ASN` (drops the session; combine with
  graceful restart to survive).

## Traffic engineering attributes

- `set local-preference N` — iBGP-wide preference.
- MED: only compared between paths from the same neighboring AS;
  `bgp always-compare-med` to compare across; `bgp deterministic-med`
  for order-independent selection. In closed networks the docs suggest
  either always-compare-med or neutralizing MED (`set metric 0`) —
  MED oscillates in iBGP.
- `set as-path prepend 65001 65001` (or `prepend last-as N`) to
  deprioritize an exit; `set as-path exclude/replace` to scrub.
- Well-known communities: `no-export`, `no-advertise`, `local-AS`,
  `no-peer`, `blackhole` (65535:666), `graceful-shutdown` (65535:0).
  `neighbor PEER send-community <both|all|standard|extended|large>`
  (enabled by default).

## ECMP and convergence

- `maximum-paths N` (eBGP) / `maximum-paths ibgp N` — per instance or
  per AF; effective cap = min(command, daemon `-e`, compiled
  multipath). NixOS build compiles 64-way.
- Multipath equality: default requires identical AS_PATH;
  `bgp bestpath as-path multipath-relax` (equal *length* suffices) is
  the standard fabric knob; `bgp bestpath peer-type multipath-relax`
  mixes eBGP+iBGP paths.
- Kernel hashing: `fib_multipath_hash_policy` sysctl controls flow
  distribution once zebra installs the nexthop group.
- Weighted ECMP: originate `set extcommunity bandwidth ...`, receivers
  translate to kernel nexthop weights; keep the community inside your
  domain.
- Fast detection without BFD: `bgp fast-external-failover` (default on,
  single-hop eBGP link-down) and `bgp fast-convergence` (also tears
  down iBGP/multihop when the peer address becomes unreachable).

## BFD

BFD (RFC 5880, `bfdd` daemon) is the fast-detection layer: with
`neighbor … bfd`, bgpd tears the session down the instant BFD declares
the path dead instead of waiting out the hold time. Cilium's BGP
control plane has **no BFD** — BFD runs on fabric- or tunnel-facing FRR
peers; Cilium relies on short BGP timers instead.

Protocol model (from
[bfd.html](https://docs.frrouting.org/en/latest/bfd.html)):

- The default is periodic **control-packet** mode. **Echo mode works
  only between two FRR instances** (or with distributed BFD offload) —
  to heterogeneous peers (Cilium, other vendors) run control packets.
  Echo is also unsupported on multihop sessions (RFC 5883 §3).
- **Demand mode without echo can deadlock detection**: nothing fires
  Poll Sequences on its own, so a failed path goes undetected. Pair it
  with echo or don't use it.
- Ports: single-hop UDP **3784**, multihop UDP **4784** (`multihop`
  keyword + `local-address`, mandatory for IPv6 peers).
- The **C-bit** (`check-control-plane-failure`) marks BFD as
  control-plane-independent so a peer's graceful restart isn't defeated
  by BFD-down — see graceful restart below.

Config — peers and profiles (defaults: detect-multiplier 3, rx/tx
300 ms ⇒ ~900 ms detection; `profile fast` at 150 ms ⇒ ~450 ms):

```
bfd
 profile fast
  detect-multiplier 3
  receive-interval 150
  transmit-interval 150
 exit
 peer 192.168.0.6
  profile fast
  no shutdown
 !
```

- Peer grammar: `peer A.B.C.D|X:X::X:X [multihop] [local-address A]
  [interface IF] [vrf NAME]`.
- Per-peer parameters override the profile. Updating a profile applies
  live **without session reset**; **deleting a profile silently resets
  its peers to defaults**.
- Auth: `authentication key-chain NAME` (cleartext or hmac-sha1 only);
  a key-chain with no usable key keeps the session down by design.

BGP integration (inside `router bgp`):

| Command | Behavior |
|---|---|
| `neighbor X bfd [profile P]` | BFD down ⇒ BGP session shut immediately; up ⇒ reconnect |
| `neighbor X bfd strict [hold-time S]` | BGP cannot establish until BFD is up; admin-down also kills BGP. `hold-time` defers the BFD-down notification until it expires — damps transient BFD flaps |
| `neighbor X bfd check-control-plane-failure` | Write/read the C-bit: ignore BFD-down while the peer is in graceful restart. Off by default |

Static routes can ride BFD too — installed only while the session is
up: `ip route A.B.C.D/M NEXTHOP bfd [multi-hop|source A|profile P]`
(inspect with `show bfd static route`, since uninstalled routes vanish
from `show ip route`). Useful for stub attachments that don't run BGP.

Verify with `show bfd peers` (see [operations.md](operations.md)).

## Graceful restart and graceful shutdown

- `bgp graceful-restart [restart-time S] [stalepath-time S]` — global
  restarter config; per-peer `neighbor PEER graceful-restart[-helper|-disable]`.
  Default mode is helper-only. The GR notification capability is on
  since 8.3 (without it, Cease/hold-time-expiry notifications don't
  activate GR).
- **BFD defeats GR unless you set the C-bit**: a BFD-down during the
  peer's restart purges the "stale" routes the helper was preserving.
  Restarter signals GR via BGP; the helper honors it and needs
  `neighbor PEER bfd check-control-plane-failure`. GR + BFD without
  that knob = fast detection neutering your restart survival.
- **Graceful shutdown** (RFC 8326): `bgp graceful-shutdown` re-announces
  with the GRACEFUL_SHUTDOWN community + local-pref 0 to steer traffic
  away before maintenance. It **persists across restarts if saved** —
  explicitly disable it afterwards.
- For planned daemon restarts, `systemctl restart frr` after enabling
  GR on peers keeps routes usable during the blip.

## Inter-site filtering (controlling which networks may talk)

The bella.network WireGuard-mesh recipe, assembled from documented
pieces:

1. Require policy: keep `bgp ebgp-requires-policy` on (traditional
   default) so unfiltered directions discard routes — the `(Policy)`
   marker in `show bgp summary` exposes a missing filter. (Datacenter
   profile turns it off; `no bgp ebgp-requires-policy` when you really
   want open peering.)
2. Allow-lists per direction: inbound prefix-list permitting only the
   remote site's CIDRs; outbound prefix-list/route-map of what this
   site may announce. Use `ge 9`/`ge 13`/`ge 17` bounds on RFC1918
   aggregates so a leaked `10.0.0.0/8` summary is dropped while real
   site prefixes pass.
3. Attribute control: `set community additive no-export` to contain
   routes within a site; SoO (`neighbor PEER soo EXTCOMMUNITY`) prevents
   re-advertising a route back to its origin site — especially needed
   with `allowas-in`/`as-override`.
4. Blackholing: the `blackhole` community (65535:666) signals drop
   upstream.

## Martian / reserved-range knobs

- `allow-reserved-ranges` — **global** config command permitting
  reserved ranges like 127.0.0.0/8 and 0.0.0.0/8 (needed for loopback
  peering on 127.0.0.0/8 / ::1, and for ULA pod/VIP prefixes FRR
  otherwise refuses). Default off; exists since FRR 8.4 — looking for
  it under `router bgp` returns "% Unknown command".
- `bgp allow-martian-nexthop` — router-bgp mode; accept martian
  next-hops in NLRI instead of resetting the session (replaces the
  deprecated `debug bgp allow-martian`). Required when a peer (e.g.
  Cilium over `::1`) advertises a loopback next-hop.

## Version-dependent defaults

| Knob | Behavior |
|---|---|
| `bgp enforce-first-as` | **on ≥ 9.1** (traditional profile) — breaks route-server peerings unless disabled per peer/instance |
| `bgp graceful-restart notification` | on ≥ 8.3 |
| `bgp hard-administrative-reset` | on ≥ 8.3 |
| `bgp ebgp-requires-policy` | on ≥ 7.4 (traditional; off in datacenter profile) |
| `bgp network import-check` | on ≥ 7.4 (both profiles) |
| `allow-reserved-ranges` | exists ≥ 8.4 |
