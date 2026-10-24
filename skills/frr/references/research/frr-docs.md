# FRRouting (FRR) — official-docs research note

**Scope**: FRR suite with focus on the BGP daemon (`bgpd`), for operators running FRR on NixOS hosts, fronting Cilium's BGP control plane in a site-to-site L3 mesh. Every claim is traced to the official FRR documentation at `docs.frrouting.org/en/latest/` (fetched 2026-10-24). Base URL for all citations below: `https://docs.frrouting.org/en/latest/` — anchors are relative to that base.

**Orientation (one paragraph)**: FRR is a suite of cooperating daemons, not a single program: each routing protocol runs in its own daemon, protocol daemons talk to `zebra` (the dataplane/kernel broker), and `vtysh` is a single CLI frontend that proxies commands to all daemons over Unix sockets and implements the *integrated config model* (one `/etc/frr/frr.conf` for all daemons, applied at startup with `vtysh -b` and written back with `write memory`). For a BGP-only deployment the daemons that matter are `zebra`, `bgpd`, `staticd`, `bfdd` (optional, for fast failover), `mgmtd` (mandatory backend for the new YANG management plane), and `watchfrr` (supervisor). Configuration is plain CLI text; live reload without daemon restart is done with `frr-reload.py --reload`; operational state is inspected with `vtysh -c 'show ...'` one-shots, making scripting natural. (docs.frrouting.org/en/latest/about.html#architecture, basic.html#integrated-config-file, vtysh.html)

## Docs URL map

| Topic | URL |
|---|---|
| Architecture / about | about.html (section `architecture`) |
| Daemon enablement (`/etc/frr/daemons`), services, systemd, restart/reload | setup.html (`#daemons-configuration-file`, `#systemd`, `#operations`) |
| Integrated config file, basic config commands, invocation options, profiles | basic.html (`#integrated-config-file`, `#basic-config-commands`, `#common-invocation-options`) |
| vtysh (modes, pager, permissions, integrated config, saving) | vtysh.html |
| Logging config | basic.html `#basic-config-commands` (`log …` commands); extlog.html (extended targets) |
| gRPC northbound | grpc.html |
| mgmtd (management daemon) | mgmtd.html |
| Filtering: access-lists, prefix-lists | filter.html |
| Route-maps | routemap.html |
| Affinity maps (TE; brief) | affinitymap.html |
| Kernel interface (netlink etc.) | kernel.html; zebra details in zebra.html (`#nexthop-tracking`, `#administrative-distance`, `#route-replace-semantics`, `#ecmp`, `#virtual-routing-and-forwarding`) |
| IPv6 support / router advertisements | ipv6.html |
| BGP (the big chapter) | bgp.html |
| MRT/BGP4MP binary dump format | packet-dumps.html |
| frr-reload.py | frr-reload.html |
| BFD (incl. BGP BFD config) | bfd.html (`#bgp-bfd-configuration`) |
| staticd | static.html |
| Installation/versioning | installation.html; config versioning in basic.html `#configuration-versioning-profiles-and-upgrade-behavior` |

---

## 1. Architecture and daemons

Source: about.html#architecture, setup.html#daemons-configuration-file, protocols.html (TOC), mgmtd.html.

FRR's architecture: protocol daemons (`bgpd`, `ospfd`, `isisd`, `ripd`, `ldpd`, `pimd`, `pbrd`, …) each implement one protocol and exchange routes with `zebra`, which coordinates routing decisions and talks to the dataplane (the `*NIX kernel` via netlink, or a remote dataplane). Resiliency: a crash in one protocol daemon does not affect others. `vtysh` connects to each daemon over a Unix domain socket and proxies user input, giving one CLI and one config file for all daemons. (about.html#architecture)

```
|bgpd| |ripd| |ospfd| |ldpd| |pbrd| |pimd| ...
+----v------v-------v------v------v-------v----+
|                     Zebra                      |
+------------------------------------------------+
| *NIX Kernel  |  Remote dataplane  | ...        |
```

Daemons selectable in `/etc/frr/daemons` (upstream default all `no`): `zebra, bgpd, ospfd, ospf6d, ripd, ripngd, isisd, pimd, ldpd, nhrpd, eigrpd, babeld, sharpd, staticd, pbrd, bfdd, fabricd` (+`vrrpd` in the services list). (setup.html#daemons-configuration-file)

For BGP-only use:

| Daemon | Role |
|---|---|
| `zebra` | Kernel/dataplane broker: installs routes into the Linux kernel (netlink), interface/VRF state, nexthop tracking (NHT), ECMP group installation. All protocol daemons are tightly integrated with zebra; "they are not intended to run as a standalone process without zebra." (bgp.html — Starting BGP, `-n/--no_kernel`) |
| `bgpd` | The BGP daemon. Speaks BGP to peers; selects best paths; pushes/withdraws routes to/from zebra. |
| `staticd` | Static routes (`ip route …`), which can then be redistributed into BGP. (static.html) |
| `bfdd` | BFD implementation for sub-second failure detection; bgpd subscribes per-peer with `neighbor … bfd`. (bfd.html) |
| `mgmtd` | Centralized YANG management daemon; owns candidate/running/operational datastores; mandatory piece of the new config framework (the reason per-daemon config files are deprecated). (mgmtd.html, basic.html#integrated-config-file) |
| `watchfrr` | Supervisor/monitoring program; also performs privileged config writes (`write integrated` goes through watchfrr so an unprivileged vtysh gets correct file ownership). (vtysh.html#configuration-saving-file-ownership-and-permissions) |
| `vtysh` | Not a daemon — the integrated CLI frontend (see §4). |

---

## 2. Configuration model

Sources: basic.html#integrated-config-file, basic.html#basic-config-commands, vtysh.html, setup.html.

- **One integrated file**: `/etc/frr/frr.conf` holds the config for *all* daemons. "When FRR is started using an init script or systemd, vtysh is invoked to read the config file and send the appropriate portions to only the daemons interested in them." (basic.html#integrated-config-file)
- **Per-daemon files are deprecated**: daemons still read their own file (`bgpd.conf` etc.) if present, or one can be forced with `-f/--config-file`, but "these files will not be updated when the configuration is written (e.g., with the write mem command)" — use only as a transition mechanism, then remove. mgmtd made per-daemon files unsupportable. (basic.html#integrated-config-file, bgp.html — Starting BGP)
- **frr.conf discovery**: "All daemons check for the existence of this file at startup, and if it exists will not load their individual configuration files. Instead, vtysh -b must be invoked to process frr.conf and apply its settings." **`vtysh -b` must also be executed after restarting any daemon.** (vtysh.html#integrated-configuration-file)
- **`/etc/frr/vtysh.conf`**: vtysh's own config (fixed location — it controls authentication behavior); never written by save commands; edit manually. `hostname`, `domainname`, `banner motd` live here. (vtysh.html)
- **`/etc/frr/daemons`**: enables daemons (`bgpd=yes`) and sets per-daemon options (`bgpd_options=" --daemon -A 127.0.0.1"`), `vtysh_enable=yes` (makes the init script apply config via `vtysh -b` on start), `MAX_FDS` / `MAX_BGPD_FDS` (fd limits — raise for thousands of peers), `frr_global_options` (prepended to every daemon, e.g. `-w` for netns-VRF backend), `FRR_NO_ROOT`, `watchfrr_options`, `<daemon>_wrap` (valgrind/perf). This file is part of the upstream/Debian-style service packaging shipped with FRR (the docs describe the init script and `tools/frr.service`); on NixOS the `services.frr` module generates the equivalent — do not assume the Debian path layout, but the FRR-side semantics are identical. (setup.html#daemons-configuration-file)
- **Services**: VTY ports in `/etc/services` are cosmetic (bgpd=2605/tcp). systemd unit `frr.service` ships in `tools/frr.service` of the repo (not installed by source installs). (setup.html#services, setup.html#systemd)
- **Comments**: `!` and `#` start comments only as the first character of a word. (basic.html — Sample Config File)
- **Config versioning**: files start with `frr version X` + `frr defaults traditional|datacenter`. Profiles change defaults for objects created afterwards (e.g. bgp timers 60/180 traditional vs 3/9 datacenter; `bgp log-neighbor-changes` on in datacenter). "FRRouting configuration is sticky": loaded config keeps its version's defaults; a write re-emits explicit lines for changed defaults. For generated config (Ansible/Nix), always write an explicit `frr version` statement. (basic.html#configuration-versioning-profiles-and-upgrade-behavior)

### Writing / saving config

| Action | Command | Notes |
|---|---|---|
| Show running config | `write terminal` (or `show running-config`) | (basic.html#terminal-mode-commands) |
| Persist running → startup | `write file` / `write memory` | Writes frr.conf if it exists, else per-daemon files; routed through watchfrr for correct ownership. (basic.html#terminal-mode-commands, vtysh.html#configuration-saving-file-ownership-and-permissions) |
| Force integrated write | `write integrated` | Unconditional frr.conf write via watchfrr; unavailable if watchfrr not running. (vtysh.html) |
| Scripting save | `vtysh -w` | Direct save trigger; run as root or the FRR user. (vtysh.html) |
| Control default target | `service integrated-vtysh-config` (in vtysh.conf) | Always/never write frr.conf; default = "frr.conf exists ⇒ integrated". (vtysh.html) |

**Warning**: "Daemons must be running for vtysh to be able to collect their configuration. Any configuration from non-running daemons is permanently lost after doing a configuration save." Also config added while a daemon is down is invisible to it (troublesome for shared route-maps/prefix-lists). (vtysh.html)

---

## 3. Running and reloading

Sources: setup.html#operations, frr-reload.html, vtysh.html.

- **Restart**: `systemctl restart frr` / `service frr restart` — kills and restarts all daemons; unsaved config is lost. (setup.html#operations)
- **Reload**: `systemctl reload frr` / `service frr reload` — "applies the differential between on-disk configuration and the current effective configuration of running FRR processes," including starting newly-enabled daemons. Under the hood this is `frr-reload.py`. (setup.html#operations)
- **frr-reload.py**: takes a config file path, retrieves the running config from vtysh (`show running-config`), computes the delta, and executes the required vtysh commands. Requires `--reload` (apply) or `--test` (print delta only). Useful options: `--daemon DAEMON` (per-daemon delta when not using integrated config), `--overwrite` (write resulting config back to frr.conf / DAEMON.conf), `--logfile` (default `/var/log/frr/frr-reload.log`), `--bindir`/`--confdir`/`--rundir`/`--vty_socket`, `--input` (treat a file as the running config instead of asking vtysh), `--debug`, `--stdout`. (frr-reload.html)
- **Starting a new daemon**: flip `pimd=no`→`yes` in `/etc/frr/daemons`, then reload. There is deliberately no per-daemon stop/restart — watchfrr can't distinguish a crashed from an intentionally stopped daemon; the closest is removing its config and setting `=no`, then restarting FRR. (setup.html#operations)
- **bgpd invocation options** (beyond common `-d/-f/-A/-P/-u/-N/-v/-M`): `-p/--bgp_port` (0 = don't listen), `-l/--listenon A.B.C.D` (bind specific addresses; implies `--no_kernel`), `-n/--no_kernel` (don't install into zebra/kernel — the supported way to run route reflectors/looking-glass; runtime toggle `[no] bgp no-rib`), `-S/--skip_runas`, `-e/--ecmp` (limit ECMP ≤ compiled MULTIPATH_NUM), `-x/--v6-with-v4-nexthops` (peer v6 AFI with v4-addressed interfaces), `-K/--graceful_restart`, `-I/--int_num`. `-Z/--no_zebra` is deprecated/buggy — use `-n`. (bgp.html — Starting BGP; bgp no-rib at bgp.html#route-reflector section "Miscellaneous")
- **Crash logs**: on crash, backtrace is written to `/var/tmp/frr/<daemon>[-<instance>].<pid>/crashlog` regardless of config; per-thread log buffers alongside (`logbuf.<tid>`, read with `tr '\0' '\n'`). (setup.html — Crash logs)

---

## 4. vtysh — the integrated shell

Source: vtysh.html, basic.html (VTY overview/modes).

- Combined frontend to all daemons; enabled at build time (`--disable-vtysh` removes it). Connects to daemons through Unix sockets in `/var/run/frr`; requires membership in the `frrvty` group. `-u/--user` "restrict" flag is explicitly **not** a security mechanism per the docs. (vtysh.html#permissions-and-setup-requirements)
- **Modes**: view mode (read-only) → `enable` → enable mode (read-write) → `configure terminal` → configuration mode; per-daemon sub-modes (`router bgp …`, `address-family …`, `interface …`). (basic.html#virtual-terminal-interfaces — VTY Modes)
- **One-shot commands for scripting**: `vtysh -c 'show bgp summary'` — used throughout the official docs, e.g. `# vtysh -c 'show bgp ipv4 unicast json' | jq '.tableVersion'` and `~# vtysh -c 'show run' | grep …`. (bgp.html — Displaying BGP Information; bgp.html — Community alias) Batch multiple `-c` options are standard vtysh usage; each is executed in order.
- `vtysh -b` = boot-time apply of frr.conf; `vtysh -w` = write config. (vtysh.html)
- **Live logs**: `terminal monitor [DAEMON]` streams log messages to the session (stderr, fixed at debug priority, may drop messages). (vtysh.html#live-logs)
- **Pager**: `VTYSH_PAGER` env var (falls back to `more`; `less -EFX` recommended) + `terminal paginate` (system default in vtysh.conf). Set `terminal length 0`/pipe to avoid pagination in scripts. (vtysh.html#pager-usage)
- **Idle timeout**: `exec-timeout TIMEOUT` (seconds) in vtysh.conf, `-T/--exec-timeout`, or configure mode; 0 = never. (vtysh.html#idle-timeout)
- **Diagnostic commands inside vtysh**: `ping [ip|ipv6] DEST [source …] [count 1-1000] [dontfragment]`, `traceroute …`, `mtrace …`. (vtysh.html#network-diagnostic-commands)
- **Pipes**: `… | include REGEX` (POSIX ERE, no quotes) filters output; e.g. `show run | include neigh.*[0-9]{2}\.0\.[2-4]\.[0-9]*`. (basic.html — Pipe Actions)
- **Discovery aids**: `list` (all commands), `find REGEX…` (search all commands across all modes — shows the mode in parens), `?` and TAB completion. (basic.html#terminal-mode-commands)
- `copy FILENAME running-config` — process/load an arbitrary config file as if typed into vtysh. (vtysh.html)

---

## 5. Debugging playbook

Sources: bgp.html (Displaying BGP Information, Debugging), zebra.html, bfd.html, basic.html/extlog.html (logging), packet-dumps.html.

### 5.1 The `show bgp summary` triage

`show bgp [afi] [safi] [all] summary [wide] [json]` — "Show a bgp peer summary for the specified address family." Variants: `summary established`, `summary failed`, `summary neighbor PEER`, `summary remote-as <internal|external|ASN>`, `summary terse`. (bgp.html — Displaying BGP Information)

Columns and what to look at (fields from the documented sample output):

```
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
192.168.0.2     4      65002         8        10        0    0    0 00:03:09            5 (Policy) N/A
```

- `V` = BGP version (4). `AS` = remote AS. `MsgRcvd/MsgSent` = message counters (stuck or asymmetric counters ⇒ session stuck). `InQ/OutQ` = queued messages (non-zero OutQ ⇒ peer not reading / TCP backpressure). `Up/Down` = session uptime or downtime. `State/PfxRcd` = either the FSM state (Idle/Active/Connect — session **not** established) or the number of prefixes received ⇒ **PfxRcd is the single most useful per-peer health field**; `PfxSnt` = prefixes sent. (bgp.html#require-policy-on-ebgp, bgp.html — Displaying BGP Information)
- **`(Policy)` in State/PfxRcd/PfxSnt**: means `bgp ebgp-requires-policy` (RFC 8212) is on and that direction has **no filter applied** — routes are discarded. ("Inbound/Outbound updates discarded due to missing policy" appears in `show bgp neighbor` under "For address family:".) Fix: attach a route-map/prefix-list/distribute-list, or disable the knob (requires session clear). (bgp.html#require-policy-on-ebgp)
- Header lines also report: router identifier, local AS, VRF, table version, RIB entry count. (bgp.html — Displaying BGP Information)

### 5.2 Neighbor-level state

`show [ip] bgp [<view|vrf> NAME] [<ipv4|ipv6>] neighbors [<PEER>] [graceful-restart] [json [brief [established|failed]]]` — per-neighbor detail: `BGP state = Established, up for …`, hold time / keepalive interval, counters, per-AF blocks (`accepted prefixes`, `Inbound soft reconfiguration allowed`, missing-policy discard counters). `json brief` yields a compact object per neighbor (hostname, remoteAs, localAs, lastResetDueTo, messageStats, acceptedPrefixCounter/sentPrefixCounter per AFI/SAFI). (bgp.html — BGP Show Neighbors Brief Command)

Route-level neighbor checks (all `[json]`):

| Command | Shows |
|---|---|
| `show bgp [afi] [safi] neighbors PEER routes` | routes received from peer **and accepted** by inbound policy |
| `… neighbors PEER received-routes` | all routes received **before** inbound policy (needs `soft-reconfiguration inbound`) |
| `… neighbors PEER advertised-routes` | routes permitted by outbound policy and actually advertised |
| `… neighbors PEER filtered-routes` | routes filtered out inbound |
| `show bgp [afi] [safi] neighbors PEER bestpath-routes [detail]` | routes BGP selected as best from that peer |
| `show bgp [afi] [safi] [all] <PREFIX> longer-prefixes` | prefix + more-specifics |
| `show [ip] bgp [afi] [safi] [all] detail-routes` | full detail format for the whole table |
| `show [ip] bgp [<view|vrf> V] nexthop [<ADDR>] [detail]` | BGP nexthop cache: valid/invalid, IGP metric, `#paths`, gate — **the first place to look when routes are in the BGP table but not forwarding** (nexthop resolution lives in zebra/NHT) |
| `show bgp [afi] [safi] import-check-table` | nexthop table used by `bgp network import-check` |
| `show bgp update-groups [advertise-queue|advertised-routes|packet-queue]` | update-group internals (peers grouped for outbound update batching) |

(bgp.html — Displaying Information about Peers / Displaying BGP Information / Displaying Nexthop Information)

### 5.3 RIB vs kernel — `show ip route` and the `r` flag

`show ip route [vrf VRF] [table TABLENO] [json]` shows zebra's RIB. Route codes (documented verbatim):

```
Codes: K - kernel route, C - connected, S - static, R - RIP,
O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
T - Table, v - VNC, V - VNC-Direct, A - Babel, D - SHARP,
F - PBR, f - OpenFabric,
> - selected route, * - FIB route, q - queued, r - rejected, b - backup
t - trapped, o - offload failure
```

(zebra.html#ecmp)

- `>` = zebra's selected route for the prefix; `*` = installed in the FIB (kernel). A route shown without `*` (or with **`r` = rejected**) is in the zebra RIB but **not installed into the kernel** — for BGP-learned prefixes this is the classic "BGP has it, kernel doesn't" gap (kernel rejected the install, e.g. unreachable/blackholed nexthop or unsupported attribute).
- Cross-check the kernel: `ip route show <prefix>` — ECMP appears as `nexthop via … weight 1` lines; kernel-side hash policy is `fib_multipath_hash_policy` sysctl ("Once installed into the FIB, FRR currently has little control over what nexthops are chosen"). (zebra.html#ecmp)
- Administrative distances (zebra RIB preference): System 0, Kernel 0, Connected 0, Static 1, NHRP 10, **EBGP 20**, EIGRP 90, BABEL 100, OSPF 110, ISIS/OpenFabric 115, RIP 120, Table 150, SHARP 150, **IBGP 200**, PBR 200. Distance 255 = never install into dataplane. Override per-BGP-instance with `distance bgp (ext) (int) (local)` in `router bgp`. (zebra.html#administrative-distance, bgp.html#administrative-distance-metrics)
- Kernel install detail: routes are installed with metric 20; "the kernel's metric value bears no resemblance to FRR's RIB metric or admin distance." (zebra.html#route-replace-semantics)

### 5.4 `debug bgp …` (enable mode; disable with the `no` form)

| Command | What it produces |
|---|---|
| `debug bgp neighbor-events [detail]` | peer connect/disconnect, session establishment/teardown, capability negotiation (detail adds state-transition context) |
| `debug bgp updates [detail]` | UPDATE messages tx/rx; `detail` adds full UPDATE internals (attribute length, withdraw length…) |
| `debug bgp updates <in\|out> [<PEER> [prefix-list WORD]]` | filter updates by direction, neighbor, and prefix-list — **the scalpel for busy routers** |
| `debug bgp keepalives [PEER]` | KEEPALIVE tx/rx |
| `debug bgp bestpath A.B.C.D/M` | bestpath computation for one prefix |
| `debug bgp nht` | nexthop tracking (zebra resolution) |
| `debug bgp zebra` | bgpd⇄zebra communication |
| `debug bgp update-groups` | update-group create/delete/join/prune |
| `debug bgp bfd` | BFD integration state transitions/validation |
| `debug bgp aggregate [prefix P]` | aggregation processing |
| `debug bgp conditional-advertisement` / `debug bgp upa` | conditional advertisement / UPA |
| `show debug` | list all currently enabled debugs |

(bgp.html#debugging)

Where the output goes: to all enabled logging targets (§5.5). Debug output at scale can be enormous — the docs warn heavy debugs "can bring FRR to a halt"; use `log filtered-file` + `log filter-text WORD` to cut it down (filtering is ephemeral: not saved to frr.conf). (basic.html#basic-config-commands)

### 5.5 Logging configuration

Global config commands (basic.html#basic-config-commands, extlog.html):

| Command | Effect |
|---|---|
| `log file /var/log/frr/bgpd.log informational` | log to file, optional level (emergencies…debugging; default debugging) |
| `log daemon bgpd file … [LEVEL]` | per-daemon file logging |
| `log stdout LEVEL` / `log syslog [LEVEL]` | stdout / syslog (syslog() API; for structured output prefer extended targets) |
| `log extended NAME` + `destination syslog [supports-rfc5424]` / `journald` / `file PATH` / `unix PATH` / `stdout`… | modern targets: RFC5424/3164/local-syslog/journald formats, per-target `priority`, `facility`, sub-second `timestamp precision`, structured-data key/value (extlog.html#destinations) |
| `log timestamp precision (0-6)` / `log record-priority` / `log unique-id` | ms/µs timestamps; severity in message text; `[XXXXX-XXXXX]` unique msg IDs (keep enabled for bug reports) |
| `log commands` | audit all typed commands (includes passwords!) |
| `log immediate-mode` | unbuffered output for debugging |
| `log filter-text WORD` + `log filtered-file FILE` | string-filtered debug sink; `clear log filter-text` resets |

Systemd note: "If systemd is in use and stdout is connected to systemd, FRR will automatically switch to journald extended logging for this target." Reconfiguration uses add-delete semantics — brief duplication possible. (basic.html, extlog.html#restart-and-reconfiguration-caveats)

### 5.6 Packet / table dumps (MRT BGP4MP, tcpdump-compatible)

- In-enable-mode commands: `dump bgp all PATH [INTERVAL]`, `dump bgp all-et PATH [INTERVAL]`, `dump bgp updates PATH [INTERVAL]`, `dump bgp updates-et PATH [INTERVAL]`, `dump bgp routes-mrt PATH [INTERVAL]`. `PATH` accepts strftime formatting (e.g. `/var/log/frr/bgp-%Y%m%d.pcap`); INTERVAL rotates files (also `04h20m00` syntax); `-et` variants add the extended-timestamp header. Resulting files are in the MRT BGP4MP binary format described in packet-dumps.html and are readable with tools that understand MRT dumps (e.g. `tcpdump -r`, bgpdump, wireshark). `dump bgp routes-mrt` dumps the whole RIB — "this is heavy process". (bgp.html — Dumping Messages and Routing Tables, packet-dumps.html)
- **Correction to a common assumption**: in the current docs, `packet-dumps.html` is the *BGP4MP binary-format appendix*, not a tcpdump-integration chapter; the tcpdump angle is exactly these `dump bgp …` monitor commands producing MRT/BGP4MP files.

### 5.7 BFD debugging (cheap)

`show bfd [vrf NAME] peers [json]` / `show bfd [vrf NAME] peers brief` / `show bfd peer <peer> [json]` — session state, timers, uptime. `debug bfd …` family exists in bfd; BGP-side integration events come from `debug bgp bfd`. BFD events appear in normal logging too. (bfd.html — BFDd Commands; bgp.html#debugging)

---

## 6. BGP configuration reference (exhaustive)

Source chapter: bgp.html. All commands below are exact documented syntax.

### 6.1 Instance basics

```
router bgp ASN                ! enable BGP process; ASN = number or dotted pair
bgp router-id A.B.C.D         ! REQUIRED if zebra can't provide interface addrs
```

- Router-ID default = largest interface IPv4 address (via zebra); without zebra it stays 0.0.0.0 and sessions can't establish — set it explicitly. (bgp.html#asn-and-router-id)
- Multiple ASes / VRFs: `router bgp ASN vrf VRFNAME` (VRF matched against kernel VRFs; each AS→VRF; same AS may repeat in different VRFs; even `router bgp` peering to itself is possible for RR/route-server use). (bgp.html#multiple-autonomous-systems)
- Views (route-server style, no kernel install): `router bgp AS-NUMBER view NAME`; inspect with `show [ip] bgp view NAME`. (bgp.html#views)
- `bgp no-rib` / `-n --no_kernel`: keep BGP running without installing routes (RR / looking glass). (bgp.html — Miscellaneous/Route Reflector section)
- AS4 notation: `router bgp ASN as-notation dot|dot+|plain`. (bgp.html — AS-notation support)

### 6.2 eBGP vs iBGP behavior (as documented)

- `neighbor PEER remote-as ASN|internal|external|auto` — `internal`/`external` enforce same-AS/different-AS at OPEN; `auto` learns the ASN from the OPEN message. First neighbor command must be `remote-as` (else "can't find neighbor"). (bgp.html#defining-peers)
- eBGP multi-hop: `neighbor PEER ebgp-multihop` — required when the peer isn't directly connected; "If the peer's IP address is not in the RIB and is reachable via the default route, then you have to enable ip nht resolve-via-default." (bgp.html — Configuring Peers; zebra.html#nexthop-tracking)
- Loopback single-hop eBGP: `neighbor PEER disable-connected-check` ("allow peerings between directly connected eBGP peers using loopback addresses"). (bgp.html — Configuring Peers)
- GTSM: `neighbor PEER ttl-security hops NUMBER` (RFC 5082) — **mutually exclusive with ebgp-multihop**. (bgp.html — Configuring Peers)
- Next-hop: by default bgpd passes third-party next-hops learned via eBGP through to iBGP peers; `neighbor PEER next-hop-self [force]` rewrites the announced nexthop to the local router for eBGP-learned routes (`force` also for iBGP-learned). `neighbor PEER attribute-unchanged [{as-path|next-hop|med}]` leaves attributes untouched. (bgp.html — Configuring Peers)
- `neighbor PEER sender-as-path-loop-detection` — filter sender-side AS-path loops before sending. (bgp.html — Peer Filtering)
- Loop-prevention acceptance for same-AS sites: `neighbor PEER allowas-in [<(1-10)|origin>]` (accept own AS in path N times, or only originated routes) and the route-map-scoped `neighbor PEER allowas-in route-map WORD [(1-10)|origin]`; alternative: `neighbor PEER as-override` (rewrite occurrences of the peer's AS in the path — PE/CE style). eBGP only. Note: `advertise-peer-as` does not appear in the current docs — the documented knobs for AS-loop scenarios are `allowas-in`, `allowas-in route-map`, `as-override`, and `local-as … dual-as`. (bgp.html — Configuring Peers)
- Route reflectors: `neighbor PEER route-reflector-client`, `bgp cluster-id A.B.C.D` (multi-RR cluster loop prevention). By default outbound route-map policy is **not** applied to reflected routes — `bgp route-reflector allow-outbound-policy` changes that. `neighbor PEER solo` = don't reflect a peer's routes back to it. (bgp.html#route-reflector, bgp.html — Peer Groups/Peer Filtering)

### 6.3 Address families and activation

- Default: **only IPv4 unicast** is enabled for every neighbor. Activate other AFI/SAFI per neighbor inside the AF block:
  ```
  router bgp 1
   address-family ipv6 unicast
    neighbor 2001:DB8::1 activate
    network 2001:DB8:5009::/64
   exit-address-family
  ```
  (bgp.html#ipv6-support)
- Idiom: `no bgp default ipv4-unicast` ⇒ every AF (incl. IPv4 unicast) needs explicit `neighbor X activate` — standard for dual-stack/upstream-split configs. `bgp default ipv6-unicast` makes v6 the default for new neighbors. Families: `ipv4|ipv6 unicast|multicast|vpn|flowspec|labeled-unicast`, `l2vpn evpn`. (bgp.html#ipv6-support, bgp.html — Configuring Peers "bgp default …")
- Show commands take `[afi] [safi]`: `show bgp ipv4 unicast …`, `show bgp ipv6 unicast …`; legacy `show ip bgp` = `show bgp ipv4 unicast`, bare `show bgp` = IPv6 table. (bgp.html — Displaying BGP Information)

### 6.4 Originating routes: network vs redistribute vs aggregate

| Method | Command | Notes |
|---|---|---|
| Explicit announcement | `network A.B.C.D/M` (inside AF) | bgpd "doesn't care about IGP routes when announcing its routes" — but see `bgp network import-check` (default **on** ≥7.4 for both profiles): prefix must exist in the RIB to be announced |
| Connected/static/kernel/… | `redistribute <babel\|connected\|eigrp\|isis\|kernel\|openfabric\|ospf\|ospf6\|rip\|ripng\|sharp\|static> [metric M] [route-map WORD]` | Admin distance of the source is carried into BGP best-path ("Admin distance check" is step 0 of route selection) |
| Whole kernel table | `redistribute table (1-65535)` / `table-direct (1-65535)` | table = via `ip import-table`; table-direct = straight into BGP |
| Aggregation | `aggregate-address A.B.C.D/M [as-set] [summary-only] [route-map NAME] [origin …] [matching-MED-only] [suppress-map NAME] [upa …]` | a more-specific prefix **must exist in the BGP table** (RIB alone is not enough); redistribute the components first |
| Default route | `neighbor PEER default-originate [route-map WORD]` | bgpd never announces 0.0.0.0/0 unless told; route-map can gate it |

(bgp.html#networks, bgp.html#redistribution, bgp.html#route-aggregation)

`table-map ROUTE-MAP-NAME` (per AF): apply a route-map to BGP→zebra updates; set ops limited to metric and next-hop; doesn't affect the BGP RIB. (bgp.html — Redistribution)

### 6.5 IPv6 link-local peering, BGP unnumbered, RFC 8950 (IPv4 NLRI over v6 nexthop)

The Cilium node-local-FRR pattern. Documented idioms:

- Interface-based peering: `neighbor PEER interface [v6only] [peer-group NAME]` and `neighbor PEER interface [v6only] remote-as <internal|external|auto|ASN>`. bgpd derives the session address from a /30//31 on the interface (IPv4) or falls back to the peer's **IPv6 link-local** address; `v6only` forces link-local. Point-to-point links only — on a shared segment only one such neighbor comes up. (bgp.html — Configuring Peers)
- **Extended next-hop (RFC 8950)**: `neighbor PEER capability extended-nexthop` — "If you are peering over a v6 LL address then this capability is turned on automatically. If you are peering over a v6 Global Address then turning on this command will allow BGP to install v4 routes with v6 nexthops if you do not have v4 configured on interfaces." (bgp.html — Configuring Peers)
- bgpd-level knob: `bgp ipv6-auto-ra` — bgpd asks zebra to send IPv6 RAs on interfaces for unnumbered peers / extended-nexthop (disable with `no bgp ipv6-auto-ra`). RA fast retransmission (`ipv6 nd ra-fast-retrans`, default enabled) speeds unnumbered convergence (ipv6.html#router-advertisement). Daemon option `-x/--v6-with-v4-nexthops` allows v6 AFI peering when the interface only has v4 addresses (zebra's equivalent option overrides it). (bgp.html#ipv6-support, bgp.html — Starting BGP)
- Link-local-next-hop capability: `neighbor PEER capability link-local` — send only the 16-byte link-local nexthop on unnumbered p2p links (datacenter idiom; off by default). (bgp.html — Configuring Peers)
- Nexthop selection for kernel install with both global+LL received: default = link-local; `nexthop prefer-global` (per AF) installs the global address instead (RIB keeps both). Route-map equivalent: `set ipv6 next-hop prefer-global`. (bgp.html — IPv6 Support "nexthop prefer-global", routemap.html)
- RA knobs relevant to unnumbered: `ipv6 nd suppress-ra` (must be negated to send RAs), `ipv6 nd ra-interval`, `ipv6 nd prefix …`, `ipv6 nd router-preference …` (ipv6.html).

### 6.6 Session knobs

- Description / logging: `neighbor PEER description …`; `bgp log-neighbor-changes` (on by default in datacenter profile). `bgp default show-hostname` / `show-nexthop-hostname` improve show output readability. (bgp.html — Configuring Peers; basic.html — profile table)
- Timers: `neighbor PEER timers (0-65535) (0-65535)` (keepalive, hold); `neighbor PEER timers connect (1-65535)`; `bgp minimum-holdtime`; profile defaults 60/180 (traditional) or 3/9 (datacenter). `neighbor PEER advertisement-interval (0-600)` (MRAI, default 0). (basic.html — profile table; bgp.html — Configuring Peers)
- TCP: `neighbor PEER tcp-mss (1-65535)` (needs hard reset; verified in `show bgp neighbors` as "Configured/synced tcp-mss"); `bgp tcp-keepalive (idle) (interval) (probes)`; `bgp session-dscp (0-63)`. (bgp.html#bgp-tcp-mss-support, bgp.html — Configuring Peers)
- Auth: `neighbor PEER password PASSWORD` (TCP MD5; raise `net.core.optmem_max` at scale). (bgp.html — Configuring Peers)
- Shutdown: `neighbor PEER shutdown [message MSG…] [rtt (1-65535) [count (1-255)]]` (keeps config, drops session, RFC 8203 Cease/Admin Shutdown); global `bgp shutdown [message MSG…]` / `bgp shutdown no-notify` (GR-preserving standby). (bgp.html#administrative-shutdown)
- Listen ranges (dynamic peers): `bgp listen range A.B.C.D/M peer-group PGNAME`, `bgp listen limit <1-65535>` (default 100; MD5-on-prefix needs kernel ≥4.14). (bgp.html#defining-peers)
- Capability negotiation: `strict-capability-match`, `dont-capability-negotiate` (warn: "fundamentally disables … BGP unnumbered, hostname support, AS4, Addpath, Route Refresh, ORF, Dynamic Capabilities, and graceful restart"), `override-capability`, `capability dynamic`, `capability fqdn` (on by default), `capability software-version`, `capability link-local`, `capability extended-nexthop`. (bgp.html#capability-negotiation)
- OAD peering: `neighbor PEER oad` (propagate non-transitive attributes like local-pref across eBGP inside one administrative domain). (bgp.html#defining-peers)

### 6.7 Policy: filters, route-maps, soft reconfiguration, route refresh

Per-neighbor (inside AF for directional application): (bgp.html#peer-filtering)

```
neighbor PEER distribute-list NAME [in|out]   ! access-list based
neighbor PEER prefix-list NAME [in|out]       ! ip prefix-list based
neighbor PEER filter-list NAME [in|out]       ! bgp as-path access-list based
neighbor PEER route-map NAME [in|out]         ! full policy
```

Building blocks (filter.html, routemap.html, bgp.html#as-path-access-lists, bgp.html#community-lists):

```
ip prefix-list NAME seq N (permit|deny) PREFIX [le L] [ge L]   ! exact match if no le/ge;
                                                               ! no match ⇒ implicit deny; undefined list ⇒ permit
access-list NAME [seq N] (permit|deny) A.B.C.D/M [exact-match] ! default deny on no-match
bgp as-path access-list WORD [seq N] permit|deny LINE            ! _ = AS boundary: (^|[,{}()]|$)
bgp community-list standard NAME permit|deny COMMUNITY…          ! e.g. 7675:80, no-export, blackhole
bgp large-community-list …                                       ! ASN:VAL:VAL
route-map NAME (permit|deny) ORDER                               ! last implicit entry = deny all
  match ip address prefix-list PL
  match as-path ASPL
  match community CL [exact-match]
  set local-preference 200 | set metric +10 | set community 65001:100 additive
  set as-path prepend 65001 65001
  on-match next / continue N / call OTHER-RM
```

Route-map semantics: match+permit ⇒ apply sets and exit (unless `on-match next`/`goto`); match+deny ⇒ deny; no match ⇒ next entry; end of map ⇒ **deny** (add empty `permit` last to change). Optimization (prefix-tree lookup over prefix-list matches) is on by default. (routemap.html#route-map-command)

Applying policy changes live:

- **Outbound** changes take effect on new updates; force with `clear bgp PEER [soft] out` (or `clear bgp ipv4 unicast PEER out`).
- **Inbound** without extras: if both sides support route-refresh, `clear bgp PEER [soft] in` triggers a route refresh — no stored copy needed.
- **Inbound with `neighbor PEER soft-reconfiguration inbound`**: stores the unmodified Adj-RIB-In (memory cost) so `clear bgp PEER soft in` re-evaluates *including previously-filtered* routes; also required for `maximum-prefix … force` counting. (bgp.html — Configuring Peers)
- Full reset: `clear bgp *`, `clear bgp ipv4|ipv6 [unicast] PEER`, `clear bgp ipv4|ipv6 ASNUM`; `clear bgp … message-stats`; `clear bgp … capabilities` (e.g. re-send FQDN capability without reset). (bgp.html — Other BGP Commands)

### 6.8 Traffic engineering attributes

- Local preference: `set local-preference N` (+/- variants) in route-maps — iBGP-wide preference; well-known communities example: customers set `7675:70/80/90` ⇒ provider maps to LP 70/80/90 (bgp.html — Example Configuration).
- MED: only compared between paths from the same neighboring AS by default; `bgp always-compare-med` to compare across; `bgp deterministic-med` for order-independent selection (CPU cost); `bgp bestpath med missing-as-worst`. MED is non-transitive and can oscillate in iBGP — docs recommend either always-compare-med or neutralizing MED (`set metric 0` + always-compare-med) in closed networks. `set metric igp` copies IGP cost into MED. (bgp.html#multi-exit-discriminator)
- AS-path prepend: `set as-path prepend 65001 65001` or `set as-path prepend last-as N`; scrubbing: `set as-path exclude …` / `set as-path replace …`. (routemap.html#route-map-set-command, bgp.html — Using AS Path in Route Map)
- Communities: well-known — `no-export`, `no-advertise`, `local-AS` (NO_EXPORT_SUBCONFED), `no-peer`, `blackhole` (65535:666; NO_ADVERTISE auto-added), `graceful-shutdown` (65535:0). `neighbor PEER send-community <both|all|extended|standard|large>` (default: enabled). (bgp.html#communities-attribute)
- Community alias for readable output: `bgp community alias 65001:14 name`. (bgp.html — Community alias)
- Weight (local, Cisco-style): `neighbor PEER weight W` / `set weight`. (bgp.html — Configuring Peers)

### 6.9 ECMP and multipath

- BGP: `maximum-paths (1-128)` (eBGP) / `maximum-paths ibgp (1-128) [equal-cluster-length]` — settable globally per instance or per AF; actual cap = min(command, `-e` flag, compile-time MULTIPATH_NUM). Without config, best-path only. (bgp.html#route-selection)
- Equality: by default iBGP multipath requires **identical AS_PATH**s (and eBGP paths from the same AS); `bgp bestpath as-path multipath-relax` ⇒ equal *length* suffices; `bgp bestpath peer-type multipath-relax` ⇒ eBGP+iBGP+confed paths may mix. (bgp.html#route-selection)
- zebra: "FRR supports ECMP as part of normal operations and is generally compiled with a limit of 64 way ECMP"; kernel hashing via `fib_multipath_hash_policy`; zebra builds nexthop groups and reports NHG IDs (`show ip route bgp nexthop-group summary ecmp-count eq 2`). (zebra.html#ecmp)
- Weighted ECMP (UCMP) via link-bandwidth: originate with `set extcommunity bandwidth <bw|num-multipaths>` in an outbound route-map; receivers translate bandwidth to kernel nexthop weights automatically; `bgp bestpath bandwidth <ignore|skip-missing|default-weight-for-missing>` controls treatment of paths missing the community; stop propagation outside a domain by suppressing extended communities (`send-community`) or aggregating. (bgp.html#weighted-ecmp-using-bgp-link-bandwidth)
- Fast convergence: `bgp fast-convergence` (per instance) tears down iBGP *and* multihop eBGP sessions immediately when the peer address becomes unreachable (default: only single-hop eBGP); `bgp fast-external-failover` (default on) for eBGP link-down. (bgp.html — Configuring Peers, bgp.html#bgp-fast-convergence-support)
- Convergence shaping: `bgp update-delay MAX-DELAY [ESTABLISH-WAIT]` (global) / `update-delay …` (per-instance) = read-only mode until EoRR from all peers; `bgp advertisement-delay (1-3600)` (global) / `advertisement-delay …` (per-instance) = program FIB immediately but hold *advertisements*; global and per-VRF forms are mutually exclusive. (bgp.html — Redistribution "update-delay")

### 6.10 BFD integration

```
router bgp 65001
 neighbor 10.0.0.2 remote-as 65002
 neighbor 10.0.0.2 bfd                          ! BFD down ⇒ tear down BGP session immediately; up ⇒ reconnect
 neighbor 10.0.0.2 bfd strict [hold-time S]     ! don't even establish BGP until BFD is up
 neighbor 10.0.0.2 bfd check-control-plane-failure
 neighbor 10.0.0.2 bfd profile FAST
!
bfd
 profile FAST
  detect-multiplier 3
  receive-interval 300
  transmit-interval 300
```

(bfd.html#bgp-bfd-configuration; bfd.html — Peer/Profile Configuration)

BFD defaults: detect-multiplier 3, rx/tx interval 300 ms; `echo-mode` off (works peer-FRR-only unless distributed BFD); `show bfd peers [json]`, `show bfd peer PEER [json]`, `show bfd peers brief`. `debug bgp bfd` for integration events. (bfd.html)

### 6.11 Graceful restart and graceful shutdown

- GR (RFC 4724) global knobs: `bgp graceful-restart`, `bgp graceful-restart restart-time (0-4095)` (default 120), `stalepath-time (1-4095)`, `select-defer-time (0-3600)`, `rib-stale-time (1-3600)`, `preserve-fw-state`, `notification` (N-bit; default on since 8.3 — without it, CEASE/HOLDTIME-expiry notifications don't activate GR). Per-peer: `neighbor PEER graceful-restart[-helper|-disable]`; default global mode = helper. `show bgp … neighbors PEER graceful-restart [json]`. Long-lived GR: `bgp long-lived-graceful-restart stale-time (1-16777215)` (restarter mode only; off by default). Restart-side daemon flag `-K/--graceful_restart` marks a planned restart. (bgp.html#graceful-restart)
- Graceful shutdown (RFC 8326): `bgp graceful-shutdown` (config or router-bgp mode, mutually exclusive between the two) re-announces routes with GRACEFUL_SHUTDOWN community + LOCAL_PREF 0 to iBGP; `neighbor PEER graceful-shutdown` for one peer; persists across restarts if saved — explicitly disable after maintenance. (bgp.html — Other BGP Commands)

### 6.12 Inter-site filtering (route leaking between sites)

The bella.network-style "control which networks may talk" pattern, assembled from documented pieces:

1. **Require policy**: `bgp ebgp-requires-policy` (default on for traditional profile ≥7.4, off for datacenter) guarantees no unfiltered eBGP acceptance/announcement; the `(Policy)` marker in `show bgp summary` exposes missing filters. (bgp.html#require-policy-on-ebgp)
2. **Allow-lists**: per-peer inbound `prefix-list`/`route-map` permitting only the remote site's CIDRs; outbound prefix-list of what the site may advertise (see the documented upstream example: `neighbor upstream prefix-list pl-allowed-adv out` with `seq 5 permit … / seq 10 deny any`). (bgp.html — Miscellaneous Configuration Examples)
3. **Attribute-based control**: community-list matched in route-maps to accept/deny per-service prefixes and set LP/MED (documented customer-policy example with `call` chains); `set community additive no-export` to contain routes within a site; SoO (`neighbor PEER soo EXTCOMMUNITY`) prevents re-advertising routes back to their origin site — "especially needed when using as-override or allowas-in to prevent routing loops". (bgp.html — Community Example, bgp.html — VRF Route Leaking)
4. **Blackholes**: `blackhole` community (65535:666) signals drop upstream; UPA (`aggregate-address … upa [drop]`, `neighbor … upa`) signals unreachable prefixes with a D-bit for remote blackholing. (bgp.html#communities-attribute, bgp.html#unreachable-prefix-announcement-upa)

### 6.13 VRF awareness (brief)

- `router bgp ASN vrf VRFNAME` ties an instance to a kernel VRF (matched by name); `show bgp vrfs [json]` lists instances (router-id, peer counts, EVPN info). (bgp.html#multiple-autonomous-systems, bgp.html — Displaying BGP Information)
- VRF route leaking: within BGP via `import vrf VRFNAME` (auto RD/RT; route-map attach `import vrf route-map NAME`) or explicitly via the VPN RIB (`rd vpn export`, `rt vpn import|export|both`, `import vpn` / `export vpn`, `route-map vpn import|export`, label/SID commands). `bgp bestpath use-imported-attributes` changes leaked-path bestpath comparison to imported attributes. (bgp.html#vrf-route-leaking)
- zebra side: VRF backend = Linux VRF-lite by default, or netns mapping with daemon flag `-w/--vrfwnetns` (must be identical on all daemons; settable via `frr_global_options` in the daemons file); `-o/--vrfdefaultname` renames the default VRF label. (basic.html#common-invocation-options, zebra.html#virtual-routing-and-forwarding)

### 6.14 Martian / reserved-range knobs

- `allow-reserved-ranges` (global config): permit config of reserved ranges like 127.0.0.0/8, 0.0.0.0/8 — "necessary in case of multiple FRR instances … peering via loopback interfaces running on the same router" (240.0.0.0/4 allowed by default). Default off. This is the FRR 9.x knob labs needed for loopback peering on 127.0.0.0/8. (basic.html#basic-config-commands)
- `bgp allow-martian-nexthop` (router-bgp): accept martian nexthops in NLRI instead of resetting the session (replaces deprecated `debug bgp allow-martian`). (bgp.html — Debugging/Route Reflector sections)

---

## 7. Version notes

- These docs are the `latest` (development) branch, built 2026-01; examples reference FRR 9.0/9.1-dev and features up to FRR 10.x-era output (dates through 2026). Always confirm against your installed version with `show version`. (installation.html, examples throughout bgp.html)
- Version-dependent defaults documented (basic.html — Settings affected by the version):
  - `bgp enforce-first-as`: off < 9.1, **on ≥ 9.1** (traditional profile) — breaks route-server peerings unless `no bgp enforce-first-as` / `no neighbor PEER enforce-first-as`.
  - `bgp hard-administrative-reset` and `bgp graceful-restart notification`: off < 8.3, on ≥ 8.3.
  - `bgp suppress-duplicates`: off < 7.6, on ≥ 7.6.
  - `bgp ebgp-requires-policy` / `bgp network import-check`: on ≥ 7.4 (traditional; datacenter: ebgp-requires-policy off, import-check on).
- Per-daemon config files stopped being *written* once mgmtd landed (per-daemon reads still work as a transition aid) — don't build new tooling around `bgpd.conf`. (basic.html#integrated-config-file)
- Deprecated/moved commands noticed: `debug bgp allow-martian` → `bgp allow-martian-nexthop`; `-Z/--no_zebra` → `-n/--no_kernel` / `bgp no-rib`; `log trap`, `log monitor` deprecated; `show ip bgp` legacy form "may be removed in the future"; numbered community lists (1-99/100-500) vs named lists. (bgp.html, basic.html)
- FRR 8→9→10 CLI differences observed: `neighbor … upa` / `aggregate-address … upa` (UPA), `bgp advertisement-delay`, `bgp fast-convergence`, `neighbor PEER oad`, `path-attribute discard/treat-as-withdraw`, AS-notation and `show … json brief` families are new-era commands; treat them as unavailable on 8.x. Where exact availability matters, check the docs for your release (versioned URLs: `https://docs.frrouting.org/en/frr-<X>/…`).

---

## 8. Gaps and caveats

- **`protocols.html` and `basics.html` are TOC stubs** in the current docs; real content is in `zebra.html`/`basic.html`/`setup.html` etc. (no content was lost, just renamed pages).
- **`packet-dumps.html` is the BGP4MP binary-format appendix**, not the tcpdump-integration page the task anticipated; tcpdump usage is via the `dump bgp …` MRT-file commands (§5.6).
- **VTYSH invocation flags**: the docs demonstrate `vtysh -c '…'`, `-b`, `-w` in examples/text but do not provide a full `vtysh --help` reference page; flag inventory beyond those (e.g. multiple `-c`, `-d` daemon filtering) is not officially documented on these pages.
- **Sections read at lower depth** (out of scope for Cilium fronting, noted for completeness): EVPN deep-dive (bgp.html#ethernet-virtual-network-evpn), RPKI/ASPA, Flowspec, BGP Link-State, route-server chapter detail (bgp.html#configuring-frr-as-a-route-server), UPA internals, SNMP, scripting/Lua, nexthop-groups, BMP/VNC. The route-server section was skimmed; the filtering/communities machinery it relies on is covered exhaustively above.
- **eBGP TTL defaults** (TTL=1 for eBGP) are *not* stated in the FRR docs pages read; only the operational knobs (`ebgp-multihop`, `ttl-security hops`, `disable-connected-check`) are documented. Do not assert TTL defaults from these docs.
- NixOS module specifics (`services.frr.*` options, config file generation, systemd unit naming) are outside the FRR docs and intentionally not covered here.
