# Running and debugging FRR

The operational playbook: vtysh scripting, session triage, RIB-vs-kernel
forensics, debug/logging, packet dumps, and safe reloads. Commands are
from the official docs (see
[research/frr-docs.md](research/frr-docs.md) §5 for citations).

## vtysh patterns

- One-shot (the scripting idiom used throughout the FRR docs):
  `vtysh -c 'show bgp ipv4 unicast summary'` — chain multiple `-c`
  options; each runs in order.
- Read-only is default; `enable` then `configure terminal` for changes.
- Pipes: `show run | include neigh.*10\.0\.` (POSIX ERE, no quotes).
- In scripts, avoid the pager: pipe through `| include` or run
  `terminal length 0` first. Batch runs can set `VTYSH_PAGER=cat`.
- Discovery when unsure of a command: `list` (all commands in the
  mode), `find REGEX` (search all commands across all modes),
  `?`/`TAB` completion.
- `terminal monitor` streams log messages into the current session.

## First 5 minutes on a broken peering

1. `vtysh -c 'show bgp summary'` — session layer (below).
2. `vtysh -c 'show ip route'` — is the prefix in zebra's RIB? In the
   kernel (`ip route show <prefix>`)?
3. `vtysh -c 'show bgp ipv4 unicast neighbors <PEER> routes'` — does
   the peer actually send the prefix?
4. `tcpdump -ni <if> port 179` — packets flowing at all? (Firewall
   first: NixOS opens nothing by default, see [nixos.md](nixos.md).)
5. `journalctl -u frr -n 200` and
   `vtysh -c 'show logging'`-equivalent targets — config/log review.

## `show bgp summary` triage

`show bgp [afi] [safi] [all] summary [wide] [json]` (variants:
`summary established`, `summary failed`, `summary terse`).

```
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
192.168.0.2     4      65002         8        10        0    0    0 00:03:09            5 (Policy) N/A
```

| Field | Reading |
|---|---|
| `State/PfxRcd` | A **number** = established with that many received prefixes (the single most useful health field). `Idle`/`Active`/`Connect` = session not up — walk the FSM downward |
| `(Policy)` marker | `bgp ebgp-requires-policy` is discarding routes **in that direction** — attach a route-map/prefix-list or disable the knob (then `clear bgp` to re-evaluate) |
| MsgRcvd vs MsgSent | Stuck or wildly asymmetric counters = session wedged |
| InQ/OutQ | Non-zero OutQ = peer not reading (TCP backpressure) |
| Up/Down | Uptime, or downtime for non-established |

Per-neighbor detail:

- `show bgp neighbors PEER [json]` — `BGP state`, timers, per-AF
  accepted/discard counters, last reset reason. `json brief` gives a
  compact per-peer object (`lastResetDueTo`, message stats).
- Route-level views (all `[json]`):

| Command | Shows |
|---|---|
| `show bgp ... neighbors PEER routes` | received **and accepted** by inbound policy |
| `... neighbors PEER received-routes` | everything received (requires `soft-reconfiguration inbound`) |
| `... neighbors PEER advertised-routes` | what outbound policy actually permits |
| `... neighbors PEER filtered-routes` | what inbound policy dropped |
| `show bgp [afi] [safi] nexthop` | BGP nexthop cache — **first stop when routes are in the table but not forwarding** |

## Zebra — the dataplane broker

Every protocol daemon hands its best routes to `zebra`; zebra alone
talks to the kernel (netlink) and owns the FIB:

```
bgpd / staticd / ...     ← decide WHICH routes should exist
        │
      zebra              ← decides what ACTUALLY gets installed
        │
   Linux kernel FIB
```

- **What zebra owns**: installing/withdrawing kernel routes;
  arbitrating between protocols by admin distance (connected 0, static
  1, **eBGP 20**, OSPF 110, **iBGP 200**); nexthop tracking — whether a
  path's nexthop is reachable at all (`ip nht resolve-via-default` is
  zebra's knob); ECMP nexthop groups; interface/VRF state.
- bgpd never touches the kernel: sessions can be `Established` while
  the FIB stays empty if zebra can't resolve or install the routes.
  A route reflector (`bgp no-rib` / `-n`) is the only bgpd that runs
  without zebra — never on a forwarding router.
- On NixOS, zebra always runs (`services.frr` has no enable option for
  it) alongside `mgmtd`/`staticd`.
- **The debugging split**: "session/prefix/policy broken" is bgpd
  territory — start at `show bgp summary`; "prefix in BGP but not
  forwarding" is zebra/kernel territory — start here, comparing
  `show ip route` against `ip route show` (below).
- **Distance gotcha**: static (1) beats eBGP (20). A static default or
  site route silently overrides BGP-learned ones; tune deliberately
  with `distance bgp (ext) (int) (local)` per instance.
- Kernel installs use metric 20 regardless of BGP metrics, and flow
  hashing for ECMP is the kernel's `fib_multipath_hash_policy` — zebra
  has no control after install.

## RIB vs kernel — the `r` flag

`show ip route [json]` is zebra's RIB:

```
Codes: K - kernel, C - connected, S - static, B - BGP, ...
> - selected route, * - FIB route, q - queued, r - rejected, ...
```

- A BGP route shown without `*` (or marked `r`) sits in the zebra RIB
  but **the kernel rejected the install** — the classic "BGP has it,
  forwarding doesn't" gap (seen after source-address changes; stale
  rejections clear with `systemctl restart frr`).
- Cross-check: `ip route show <prefix>`. ECMP shows as multiple
  `nexthop via ...` lines.
- Admin distance: eBGP 20, iBGP 200 (static 1, OSPF 110). Override per
  instance with `distance bgp (ext) (int) (local)`.
- Kernel install uses metric 20 regardless of BGP metrics; kernel flow
  hashing for ECMP is the `fib_multipath_hash_policy` sysctl — FRR has
  no control after install.

## `debug bgp ...` (enable mode; `no` form turns off)

| Command | Produces |
|---|---|
| `debug bgp neighbor-events [detail]` | connect/disconnect, FSM transitions, capability negotiation |
| `debug bgp updates [in\|out] [PEER [prefix-list WORD]]` | UPDATE tx/rx; the prefix-list filter is the scalpel on busy routers |
| `debug bgp keepalives [PEER]` | KEEPALIVE tx/rx |
| `debug bgp bestpath A.B.C.D/M` | bestpath computation for one prefix |
| `debug bgp nht` | nexthop tracking (zebra resolution) |
| `debug bgp zebra` / `update-groups` / `bfd` / `aggregate` | the respective subsystem |

Heavy debug output can halt a busy router — aim it (peer + direction +
prefix-list) and turn it off after. `show debug` lists what's on.

## Logging

| Goal | Config |
|---|---|
| File | `log file /var/log/frr/bgpd.log informational` (level optional; default debugging) |
| Per-daemon file | `log daemon bgpd file PATH [LEVEL]` |
| stdout / syslog | `log stdout LEVEL` / `log syslog [LEVEL]` — under systemd, stdout auto-switches to journald structured logging |
| Filtered debug sink | `log filter-text WORD` + `log filtered-file PATH` (ephemeral — not saved to frr.conf) |
| Precision | `log timestamp precision (0-6)`, `log unique-id` (keep on for bug reports) |
| Audit | `log commands` (records everything typed, passwords included) |

On NixOS, prefer the journald path: the unit captures stdout, and
`journalctl -u frr -f` needs no config. NixOS caveat: persistent file
targets need a writable directory — `/var/log/frr` is FRR's default and
owned correctly.

## Packet and RIB dumps (tcpdump-readable)

Enable-mode, writes MRT BGP4MP files (readable with `tcpdump -r`,
bgpdump, Wireshark):

- `dump bgp all PATH [INTERVAL]` — all BGP messages
- `dump bgp updates PATH [INTERVAL]` — updates only
- `dump bgp routes-mrt PATH` — whole RIB (heavy)

`PATH` takes strftime patterns (`/var/log/frr/bgp-%Y%m%d.pcap`);
INTERVAL rotates. Turn off with `no dump bgp ...`.

## BFD checks

- `show bfd [vrf V] peers [json]` — all sessions: status, peer type,
  profile, local/remote timers, **detection timeout** (the number that
  matters — DM × max(tx, remote-rx)); JSON adds RTT min/avg/max and
  per-interval actuals with jitter.
- `show bfd [vrf V] peers brief [json]` — the one-glance table
  (SessionId, local/peer address, status, profile) with a session
  count header.
- `show bfd peer PEER [json]` — one session in detail, including
  `authentication{enabled,configured}` (a key-chain with no usable key
  holds the session down by design).
- `show bfd peers counters` / `show bfd peer PEER counters` — control
  packets in/out, up/down events, zebra notifications, **Rx fail**
  (climbing = path problems). `clear bfd peers counters` resets packet
  counters only.
- `show bfd static route [json]` — BFD-monitored statics and their
  installed/uninstalled status (uninstalled ones are invisible to
  `show ip route`).
- `debug bfd network|peer|zebra|distributed` — socket/stray-packet
  issues, peer state changes, zebra registrations, data-plane offload.
  Integration events land via `debug bgp bfd` and normal logging.
- Symmetry check: a session up on one side and down on the other, or
  `neighbor … bfd` configured on only one side, converges
  asymmetrically — compare both routers' counters side by side.

BFD down ⇒ BGP session torn down immediately — a peer whose BGP config
looks healthy but never stays up points here first.

## Safe config reloads

- Preview before applying:
  `frr-reload.py --test --confdir /etc/frr /etc/frr/frr.conf`
  (prints the exact vtysh command delta; `--input FILE` diffs against a
  file instead of the live config).
- On NixOS the `frr.service` reload path already runs
  `frr-reload.py --reload` — use `systemctl reload frr` for ad-hoc
  reloads of a hand-placed file.
- `--overwrite` writes the merged result back to frr.conf — avoid on
  NixOS (the file is a store symlink; rebuilds are the source of truth).
- Daemon-set changes are NOT applied by reload — restart (see
  [nixos.md](nixos.md)).

## Crash forensics

On crash, bgpd writes a backtrace to
`/var/tmp/frr/<daemon>[-<instance>].<pid>/crashlog` (always, regardless
of config) plus per-thread log buffers (`logbuf.<tid>`, read with
`tr '\0' '\n'`). Attach these plus `show version` output to bug reports.
