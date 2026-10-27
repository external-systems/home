# IfState upstream research (for a NixOS skill)

Primary-source investigation of [IfState](https://ifstate.net/) at the pinned release.
Every factual claim cites the source in the local checkout and/or a stable Codeberg URL.

## Provenance

| Item | Value |
|---|---|
| Upstream repo | `https://codeberg.org/routerkit/ifstate.git` |
| Pinned tag | `2.5.1` |
| Commit | `9ac7caaedb55e853347c701197eccb7a245d4c07` (2026-10-11, "ifstate: release 2.5.1") |
| License | GPL-3.0-or-later (`pyproject.toml`) |
| Language | Python ≥3.11 (`pyproject.toml` `requires-python = ">=3.11"`; 2.5.0 dropped older) |

Commit recorded via `git rev-parse 2.5.1^{commit}`; local checkout is a detached HEAD at that commit.

**Citation convention used below:**

- `[src:PATH:LINE]` — file `PATH` in the checkout at commit `9ac7caa`.
- `[CB:PATH#Ln]` — canonical browsable URL `https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/PATH#Ln` (pin the tag; for permanent links substitute `src/tag/2.5.1` with `src/commit/9ac7caaedb55e853347c701197eccb7a245d4c07`).

### Known wart: embedded version string

At tag 2.5.1 the embedded version still reads `__version__ = "2.5.0"` in `src/libifstate/__init__.py:77` `[src:src/libifstate/__init__.py:77]` (verified with `git show 2.5.1:…`). It was fixed post-release by commit `344b3b8` ("misc: fix hardcoded version string") on `main`, after the 2.5.1 tag. Consequences:

- `ifstatecli --version` and the debug banner report `2.5.0` for a build made exactly at tag 2.5.1 `[src:src/ifstate/ifstate.py:153-156]` `[src:src/libifstate/__init__.py:82]`.
- The Nix build derives its package version by regexing this exact string `[src:package.nix:43-44]`, so `packages.ifstate` built from the tag reports version `2.5.0` while `pyproject.toml` says `2.5.1` `[src:pyproject.toml]`.
- Schema selection uses only the **major** component (`__version__.split(".")[0]` → `"2"`), so validation is unaffected `[src:src/libifstate/__init__.py:121-127]`.

## 1. Architecture and apply algorithm

IfState is a Python library (`libifstate`) + CLI (`ifstatecli`, entry point `ifstatecli = "ifstate.ifstate:main"` `[src:pyproject.toml]`). It models the whole network stack as one desired-state config, then converges the live kernel state to it via pyroute2 netlink calls. "As a result unspecified interfaces or ip addresses are automatically shutdown or removed… IfState reaches the desired network configuration from any previous state" `[src:docs/docs/index.md:1-4]`.

### Feature probe

On startup `IfState.__init__` probes optional features and records them in `self.features`: `altnames`, `brport`, `devicetree` (readable `/sys/firmware/devicetree`), `iw`, `link`, `sysctl`, `ethtool` (binary found), `rust` (libifstate-rs importable), `schema` (jsonschema importable), `tc`, `wireguard`, `bpf` (libbpf), `xdp` `[src:src/libifstate/__init__.py:88-104]`. WireGuard/BPF/XDP import failures are tolerated (missing kernel module or plugin) `[src:src/libifstate/__init__.py:49-67]`. Using a config section whose feature is missing raises `FeatureMissingError` (exit 5) `[src:src/libifstate/__init__.py:430-432,446-448]` `[src:src/libifstate/exception.py:57-62]`.

### `update()` — config → object model

`IfState.update(ifstates, soft_schema)` `[src:src/libifstate/__init__.py:118-215]`:

1. JSON-schema validation (see §3); errors raise `ParserValidationError` unless `-s/--soft-schema`, which only logs `[src:src/libifstate/__init__.py:156-164]`.
2. `parameters.machine_id` overrides the machine-id; otherwise read from `/etc/machine-id`, `/var/lib/dbus/machine-id`, or `/sys/class/dmi/id/product_uuid` (first non-empty value with >4 distinct chars) `[src:src/libifstate/netns/__init__.py:60-80]` `[src:src/libifstate/paths.py:21-25]`.
3. `parameters.defaults` → `self.defaults`; `parameters.ignore` merged into `self.ignore`; `ignore.ipaddr` compiled into `AddressIgnore` objects; `ignore.fdb` compiled into one regex `[src:src/libifstate/__init__.py:175-186]`.
4. Hooks, cshaper profiles, `link_address_default` stored `[src:src/libifstate/__init__.py:188-197]`.
5. A `LinkRegistry` is built by inventorying **all** links in the root netns and every existing named netns `[src:src/libifstate/netns/__init__.py:309-362]`.
6. `_update(root_netns, …)` then `_update()` per configured namespace; a configured namespace absent from `pyroute2.netns.listnetns()` is added to `self.new_namespaces` `[src:src/libifstate/__init__.py:204-215]`.

Per interface `_update()` `[src:src/libifstate/__init__.py:217-470]` merges defaults (first matching `match:` regex wins, see §6), builds a `Link` subclass instance via kind dispatch (see §7), and attaches `Addresses`, `FDB`, `Neighbours`, per-iface `sysctl`, `tc`, `wireguard`, `xdp`, `vrrp` tables, plus cshaper-generated `ifb` links `[src:src/libifstate/__init__.py:300-453]`. WireGuard `allowedips` can inject routes (`table` option) `[src:src/libifstate/wireguard/__init__.py:60-78]`. Per-netns `routing.routes`/`routing.rules` become `Tables`/`Rules` `[src:src/libifstate/__init__.py:455-469]`.

### `apply()` / `check()` — one code path

`apply()` and `check()` are thin wrappers over `_apply(do_apply, …)` with `do_apply=True/False` respectively `[src:src/libifstate/__init__.py:471-475]`. **Check is a true dry run of the same algorithm** — every code path gates kernel mutations on `do_apply`.

`_apply()` order `[src:src/libifstate/__init__.py:589-768]`:

1. **VRRP mode** — if called as `vrrp`/`vrrp-worker` with (type, name, state), only VRRP-marked objects are considered (§10) `[src:src/libifstate/__init__.py:590-601]`.
2. **Namespaces** — `prepare_netns()` creates configured namespaces and deletes orphan ones (honoring `ignore.netns`), warning if pids still run in a doomed namespace `[src:src/libifstate/netns/__init__.py:240-272]` `[src:src/libifstate/__init__.py:603-611]`. Skipped entirely in VRRP mode.
3. **Dependency staging** — `_stages()` topologically sorts `LinkDependency(ifname, netns)` from each link's `depends()`: `link`, `master`, `gre_link`, `ip6gre_link`, `vxlan_link`, `xfrm_link` (+`*_netns` variants) and bridge-port master deps `[src:src/libifstate/link/base.py:207-217,1400-1411]` `[src:src/libifstate/__init__.py:524-587]`. Circular dependencies: **apply logs the cycle, drops the unresolved deps and continues; check raises `LinkCircularLinked`** because `_stages(do_apply)` passes `continue_on_circular=do_apply` `[src:src/libifstate/__init__.py:531-560,614]`.
4. **Orphan cleanup** — every registry item with no config link (`item.link is None`) that matches neither `ignore.ifname` nor `ignore.netns` regexes is freed: virtual links are set down + deleted; **physical links are only set down** and tagged `orphan` (never deleted) `[src:src/libifstate/__init__.py:616-649]` `[src:src/libifstate/__init__.py:477-522]`. If the config has **no `namespaces` section**, links inside foreign netns are skipped entirely `[src:src/libifstate/__init__.py:634-635]`.
5. **BPF** programs, then **sysctl** (`all`/`default` ifaces, then globals) `[src:src/libifstate/__init__.py:655-670,770-793]`.
6. **Links** in dependency-stage order; each `_apply_iface()` runs `link.apply()` then xdp, addresses, fdb, neighbours, wireguard, hooks `[src:src/libifstate/__init__.py:672-711,805-880]`.
7. **Sysctl retry** for globals whose keys appeared only after kernel modules loaded lazily `[src:src/libifstate/__init__.py:713-720,795-803]` (added 2.5.0).
8. **TC** for interfaces that have it `[src:src/libifstate/__init__.py:722-734]`.
9. **Routing** (tables then rules) per netns `[src:src/libifstate/__init__.py:736-750]`.
10. **WireGuard endpoints** last, after routing exists `[src:src/libifstate/__init__.py:752-768]`.

`apply` (not `check`) ignores SIGHUP/SIGPIPE/SIGTERM so an ssh drop cannot interrupt a half-applied config `[src:src/ifstate/ifstate.py:331-334]`, and afterwards signals any `vrrp-fifo` daemons to reload `[src:src/ifstate/ifstate.py:121-146,337-338]`.

### Per-link create/update/recreate

`Link.apply()` `[src:src/libifstate/link/base.py:666-837]`:

1. Resolves index-referencing attrs (`link`, `master`, …) to ifindexes, looking cross-netns via `get_netnsid()` when `<attr>_netns` differs `[src:src/libifstate/link/base.py:670-733]`.
2. Applies a default L2 address when none configured (§8), skipping bond slaves `[src:src/libifstate/link/base.py:738-759]`.
3. If a `bind_netns` (tunnel outside) differs from the recorded state, the link is **recreated** (deleted + re-added) `[src:src/libifstate/link/base.py:761-771,600-649]`.
4. If the found registry item lives in another netns, the link is moved (`update_netns`, renaming on collision) `[src:src/libifstate/link/base.py:773-788]` `[src:src/libifstate/netns/__init__.py:443-482]`.
5. On ifname collision with a *different* index, the other link is set down and renamed to `"<name>!"` `[src:src/libifstate/link/base.py:796-814]`.
6. Kind mismatch (e.g. dummy vs vlan at same name) → `recreate()`; otherwise per-setting `update()` diff `[src:src/libifstate/link/base.py:816-834]`. If `update()` reports uncorrectable set failures on a creatable link, ifstate falls back to recreate `[src:src/libifstate/link/base.py:823-832]`.
7. `create()` sets master/state last (after sysctl/flags/token/altnames/brport/brvlan), then ethtool `[src:src/libifstate/link/base.py:839-1018]`.

`update()` compares each configured setting against live netlink attrs (with special handling for flag structs and "empty string unsets" attrs like `ifalias`), shuts the link down before changing, applies sysctl + ethtool first, then `ip link set`, then re-sets state `[src:src/libifstate/link/base.py:1037-1398]`.

**Convergence property**: because unspecified settings are cleared by the builtin defaults (§6) and orphans are removed (§5), repeated `apply` is idempotent; `check` after a successful `apply` reports everything `ok`.

## 2. CLI

`ifstatecli [global opts] <action> [action args]` `[src:src/ifstate/ifstate.py:149-245]` `[src:docs/docs/cli.md:1-29]`.

Global options:

| Flag | Meaning |
|---|---|
| `-v` / `--verbose` | DEBUG; twice = very verbose (also raises global logging) `[src:src/ifstate/ifstate.py:157-163,251-256,267]` |
| `-q` / `--quiet` | only warnings/errors `[src:src/ifstate/ifstate.py:164-169]` |
| `-s` / `--soft-schema` | log schema-validation errors instead of aborting `[src:src/ifstate/ifstate.py:170-175]` |
| `-S` / `--show-secrets` | reveal secrets in `show` output (WireGuard keys) `[src:src/ifstate/ifstate.py:176-181]` `[src:src/libifstate/wireguard/__init__.py:382-393]` |
| `-c` / `--config` | YAML config path, default `/etc/ifstate/ifstate.yaml` `[src:src/ifstate/ifstate.py:182-188]` |

Actions (`Actions` class) `[src:src/ifstate/ifstate.py:31-55]`:

- `apply` — converge live network to config.
- `check` — dry-run of `apply` (same `_apply` with `do_apply=False`).
- `validate` — parse + JSON-schema validation only (added in 2.4.1) `[src:src/ifstate/ifstate.py:319-321]` `[src:CHANGELOG.md:75-81]`.
- `show` / `showall` — dump a config for the **running** system (reverse of apply), including netns instances; `showall` additionally prints builtin defaults/ignore values `[src:src/ifstate/ifstate.py:269-288]` `[src:src/libifstate/__init__.py:959-1192]` `[src:docs/docs/cli.md:98-150]`. No config file needed.
- `identify` — print per-physical-interface `identify:` snippets with all detectable attributes; no config needed `[src:src/libifstate/__init__.py:905-957]` `[src:docs/docs/cli.md:59-73]`.
- `shell` — interactive pyroute2 REPL (`ipr` symbol) `[src:src/ifstate/ifstate.py:110-118]`.
- `vrrp <group|instance> <name> <state>` — one-shot keepalived notify script; states validated against `KEEPALIVED_STATES` `[src:src/ifstate/ifstate.py:202-216]`.
- `vrrp-fifo <fifo>` — persistent keepalived `vrrp_notify_fifo_script` (recommended over `vrrp`) `[src:src/ifstate/ifstate.py:219-221]` `[src:src/ifstate/vrrp.py:150-196]`.
- `vrrp-worker <group|instance> <name>` — internal worker spawned by `vrrp-fifo` `[src:src/ifstate/ifstate.py:224-229]` `[src:src/ifstate/vrrp.py:199-209]`.

Must be run from the **root netns**: constructor compares `/proc/1/ns/net` to its own and aborts with `NetNSNotRoot` (exit 6) `[src:src/ifstate/ifstate.py:63-72]`.

Shell completion is generated via optional `shtab` (`ifstatecli --print-completion bash`; config arg completes `*.yml`/`*.yaml` with shtab ≥1.10) — new in 2.5.0 (#220) `[src:src/ifstate/ifstate.py:234-244]` `[src:CHANGELOG.md:27-31]`.

### Exit codes

From `src/libifstate/exception.py` `[src:src/libifstate/exception.py:57-122]`, wired in `main()` `[src:src/ifstate/ifstate.py:298-346]`:

| Exit | Condition |
|---|---|
| 1 | `ParserOpenError` — config file unreadable |
| 2 | `ParserParseError` — YAML syntax error |
| 3 | `ParserIncludeError` — `!include` target unreadable/invalid |
| 4 | `ParserValidationError` — JSON-schema validation failed |
| 5 | `FeatureMissingError` (config uses unavailable feature) or `LinkCircularLinked` |
| 6 | `NetNSNotRoot` |

Note `check` exits 5 on circular link deps while `apply` logs and continues (§1).

## 3. Config YAML schema and Nix attribute mapping

- The config is a single YAML document validated against a bundled JSON Schema. Top-level properties: `parameters`, `bpf`, `interfaces`, `mac_seed`, `routing`, `sysctl`, `sysctl_conf`, `namespaces`; only `interfaces` is required `[src:schema/2/ifstate.conf.schema.json]` (inspected; 5593 lines at 2.5.1).
- `parameters` properties: `cshaper`, `defaults`, `defaults_builtin`, `hooks`, `ignore`, `machine_id`, `link_address_default`.
- The schema is selected by **major** version from `src/libifstate/schema/<major>/ifstate.conf.schema.json` via `pkgutil.get_data` `[src:src/libifstate/__init__.py:121-129]`; repo copy `schema/2/ifstate.conf.schema.json`, packaged copy `src/libifstate/schema/2/ifstate.conf.schema.json`.
- Editor integration: `# yaml-language-server: $schema=https://ifstate.net/schema/2/ifstate.conf.schema.json`; also published to JSON Schema Store as `ifstate.yaml` `[src:docs/docs/index.md:69-79]`.
- Examples directory maps YAML 1:1 to NixOS `networking.ifstate.settings` — **Nix attr names equal YAML keys verbatim** (e.g. YAML `vlan_protocol` ↔ Nix `vlan_protocol`), because the upstream NixOS module serializes the settings attrset with `builtins.toJSON` → `yq --yaml-output` `[src:module.nix:11-33]` `[src:docs/examples/vrf.md]` `[src:docs/examples/wireguard.md]`. So the skill can document: *Nix attrset = YAML tree, with string values for scalars, lists for sequences; `!include` stays a string that the generator re-quotes* (see below).
- `module.nix` `settingsFormat.generate` (upstream NixOS module): `builtins.toJSON` → `yq --yaml-output .` → `check-jsonschema --schemafile <pkg.jsonschema>` → `sed` restoring `!include` tag quoting that yq mangled `[src:module.nix:11-33]`. This validates the rendered YAML at **Nix build time**; the sed handles the `!include /path` pattern (yq quotes it as a string otherwise).
- Type note from generated docs: settings option type is "YAML 1.1 value" `[src:docs/docs/nixos-options.md:140-154]`.

## 4. Parser: `!include`, `!flatten`, secrets

`YamlParser` uses a custom `yaml.SafeLoader` subclass `[src:src/libifstate/parser/yaml.py:14-66]`:

- **`!include <file>`** — loads another YAML file *inline in place of the node*; relative paths resolve against the **including file's directory** (`_basedir` from `stream.name`) `[src:src/libifstate/parser/yaml.py:15-24,40-51]`. OSError → `ParserIncludeError` (exit 3); YAML parse error → `ParserParseError` (exit 2). Documented use: keep WireGuard private keys in separate key files `[src:docs/docs/index.md:81-94]`.
- **`!flatten`** — new in 2.5.0 (#200); merges nested sequences into one flat list `[src:src/libifstate/parser/yaml.py:28-38]` `[src:CHANGELOG.md:32]`.
- The dumped config (`dump`) is what `vrrp-fifo` writes to its runtime cfg file for workers `[src:src/ifstate/ifstate.py:101-107]` `[src:src/ifstate/vrrp.py:164,199-208]`.

`Parser.config()` (base class) merges the parsed tree over `Parser._default_ifstates` (builtin defaults/ignore, §5–§6), injects the default `lo` interface into root **and every namespace**, auto-registers executable hooks found in `/etc/ifstate/hooks`, appends `defaults_builtin` after user `defaults`, and merges every `ignore.<x>_builtin` list into `ignore.<x>` `[src:src/libifstate/parser/base.py:138-214]` `[src:src/libifstate/parser/base.py:33-131]`.

**Secrets**: only WireGuard `private_key` and `preshared_key` are treated as secrets (`SECRET_SETTINGS`) — hidden as `# VALUE IS HIDDEN - USE --show-secrets TO REVEAL` in `show` output unless `-S` is given (all-zero preshared key always hidden) `[src:src/libifstate/wireguard/__init__.py:14-15,382-393]`. There is no other secret mechanism; sops-nix integration is done at the Nix level by pointing `!include` at sops secret paths `[src:docs/examples/wireguard.md]`.

## 5. Orphan cleanup, ignore, defaults, parameters

### Ignore lists

`parameters.ignore` keys: `ipaddr`, `ipaddr_dynamic`, `ifname`, `fdb`, `routes`, `rules`, `netns` `[src:docs/docs/ignore.md:1-11]`. Builtins (auto-merged, viewable via `showall`) `[src:src/libifstate/parser/base.py:62-129]`:

- `ifname_builtin` regexes: `^br-[\da-f]{12}`, `^docker\d+`, `^ppp\d+$`, `^veth`, `^virbr\d+`, `^vrrp\d*\.\d+$`.
- `ipaddr_builtin`: `{"proto": 3}` (kernel_ll) **plus a hack**: `{"prefix": "__MATCH_MOD_EU64_LLA__"}` regex-matching modified-EUI-64 link-locals because the kernel doesn't always tag LLAs with `kernel_ll` `[src:src/libifstate/parser/base.py:63-70]` `[src:src/libifstate/address/__init__.py:15-17,49-52]`.
- `ipaddr_dynamic: True` — dynamic (SLAAC) addresses are left alone by default `[src:src/libifstate/parser/base.py:71]`.
- `fdb_builtin`: `^33:33:`, `^01:00:5e:`, `^01:80:c2:` (multicast).
- `routes_builtin` / `rules_builtin`: protos 1,2,8–16,18,42,186–189,192; routes additionally `to ff00::/8`.

Usage: orphan-link cleanup and `show`/`identify` honor `ignore.ifname`; orphan cleanup also honors `ignore.netns` `[src:src/libifstate/__init__.py:616-642]` `[src:src/libifstate/__init__.py:924-932]`. Route/rule/address/fdb application takes the corresponding ignore list `[src:src/libifstate/__init__.py:864-875,882-903]`.

### Defaults

User `parameters.defaults` is a list of `{match: [{ifname: regex, kind: regex, …}], …}` objects; **`get_defaults()` returns the *first* match only** `[src:src/libifstate/__init__.py:1194-1208]` `[src:docs/docs/defaults.md:1-18]`. Supported effects per default: `link`, `ethtool`, and the `clear_*` switches: `clear_addresses`, `clear_altnames` (added 2.5.1, #233), `clear_fdb`, `clear_neighbours`, `clear_tc` — when an interface omits that block, the block is emptied instead of ignored `[src:src/libifstate/__init__.py:269-317,423-428]` `[src:CHANGELOG.md:19-23]`.

`defaults_builtin` (always appended last, so it applies only where nothing else matched) `[src:src/libifstate/parser/base.py:51-61]`:

```yaml
- match: [{ifname: ''}]
  clear_addresses: true
  clear_altnames: true
  clear_fdb: true
  clear_neighbours: true
  clear_tc: true
  link: {state: down, master: null}
```

This is the "cleanup by default" breaking change of 2.0 (vs 1.x which ignored unspecified settings) `[src:docs/docs/defaults.md:20-42]` `[src:docs/docs/upgrades.md:18-37]`: any interface not in the config gets its addresses/altnames/fdb/neighbours/tc cleared and is set down + removed from its master — but it is **not deleted if physical** (§1).

### Other parameters

- `machine_id` — custom machine-id bytes for reproducible MACs (§8) `[src:src/libifstate/netns/__init__.py:50-58]`.
- `link_address_default` — `{macsec, physical, vlan} ∈ {generated, inherited, permanent}` `[src:src/libifstate/util.py:367-383]` `[src:docs/docs/macaddr.md:23-38]`.
- `cshaper` — cake-shaper profiles; per-interface `cshaper` auto-creates an `ifb` device and redirects ingress to it `[src:src/libifstate/__init__.py:334-421]`.
- `hooks` — global hook definitions (§9).
- top-level `mac_seed` — per-netns override of the MAC seed; `null` disables reproducible MACs for that netns `[src:src/libifstate/__init__.py:217-222]` `[src:src/libifstate/netns/__init__.py:210-220]`.

## 6. Interface identify and physical NIC renaming

Physical interfaces "cannot be created or destroyed", so they must be found by stable attributes `[src:docs/docs/interfaces.md:24-34]`. Identify attributes (`IDENTIFY_LOOKUPS`) `[src:src/libifstate/util.py:48-60]`: `perm_address` (=`ethtool -P`), `parent_dev_name` (PCI/USB bus addr), `parent_dev_bus_name`, `phys_port_id`, `phys_port_name`, `phys_switch_id`, `of_node` (devicetree path, requires readable `/sys/firmware/devicetree`). Only links with netlink kind `None` (plain Ethernet) or `dsa` are identifiable (`kind_has_identify`) `[src:src/libifstate/util.py:180-185]`.

Registry matching is tried **in order** and first hit wins `[src:src/libifstate/link/base.py:226-265,324-337]`:

1. all `identify:` attrs + kind (+ implicit netns),
2. `address` + kind `physical` + netns (only when `link.address` set),
3. `ifname` + kind + netns,
4. `physical` + ifname with `orphan: True` (a previously-orphaned physical that was shut down).

Renaming happens inside `update()` when live ifname ≠ configured ifname: log `ifname` change, `prevent_altname_conflict()` removes a clashing altname (Linux 5.5+) from any link holding the target name, then `ip link set ifname=…` `[src:src/libifstate/link/base.py:1246-1280,1413-1459]`. Cross-netns moves use `update_netns()` (wireless phys are moved with nl80211 `set_wiphy_netns`, else `net_ns_fd`) `[src:src/libifstate/netns/__init__.py:443-482]`.

## 7. Links (bond/bridge/VLAN/veth/netns/WireGuard/VXLAN/GENEVE/VRF …)

- Kind dispatch: `Link.__new__` instantiates a subclass named `<Kind>Link` (`PhysicalLink`, `VlanLink`, `VethLink`, `TunLink`, `MacsecLink`, `DsaLink`), falling back to `GenericLink` for everything else (bridge, bond, dummy, vrf, vxlan, geneve, gre, gretap, ip6gre, ip6gretap, sit, ipip, ip6tnl, vti, vti6, wireguard, xfrm, ifb, macvlan, macvtap, ipvlan, team, tun handled specially, vcan/vxcan, …) `[src:src/libifstate/link/base.py:155-164]` `[src:src/libifstate/link/__init__.py]`. GenericLink supports every netlink attribute generically via NLA name mapping (`name2nla`), with string↔int enum maps for bond/bridge/vlan/vxlan/tun attributes and `rt_tables`-style lookups for `group`/`vrf_table` `[src:src/libifstate/link/base.py:41-121,1461-1473]`.
- Creatable vs not: `cap_create=False` for physical (`create()` only warns) `[src:src/libifstate/link/physical.py:38-46]`; veth without `peer` cannot be created (external/LXC veth) — `cap_create=False` and `peer_netns` maps to `bind_netns` `[src:src/libifstate/link/veth.py:14-52]`.
- Index-referencing attrs: `link`, `master`, `gre_link`, `ip6gre_link`, `vxlan_link`, `xfrm_link`; each accepts a `<attr>_netns` sibling (`null` = root netns) for cross-netns wiring `[src:src/libifstate/link/base.py:210-217,670-733]` `[src:docs/docs/namespaces.md:56-60]`.
- Tunnels with a "bind" side (`attr_bind_kinds`: ip6tnl, tun, veth, vti, vti6, vxlan, ipip, gre, gretap, ip6gre, ip6gretap, geneve, sit, wireguard, xfrm) default `bind_netns` to their own netns; a changed bind target triggers recreate. State files under `/run/libifstate/bind` record the mount ns `[src:src/libifstate/link/base.py:122-138,299-318,600-649]`.
- VLANs: `vlan_id`, `vlan_protocol` (802.1q/802.1ad), `vlan_flags` (reorder_hdr/gvrp/loose_binding/mvrp/bridge_binding bitmask; reorder_hdr defaults on) `[src:src/libifstate/link/vlan.py]`.
- Bridge: per-port `brport` settings and `brvlan` (bridge VLAN filtering) modules; bridge link option `br_stp_state` added to schema in 2.5.0 (#192) `[src:src/libifstate/brport/__init__.py]` `[src:src/libifstate/brvlan/__init__.py]` `[src:CHANGELOG.md:42]`.
- Device flags (2.5.0, #206): per-interface `flags: {allmulti, multicast, noarp, promisc}` applied via netlink `flags/mask` `[src:src/libifstate/link/base.py:146-153,339-360,1043-1071]`.
- Alt-names (2.5.0, #46/#224): `alt-names` list, diffed against `IFLA_PROP_LIST`; unconfigured altnames are removed unless the matched default sets `clear_altnames: false` `[src:src/libifstate/altnames/__init__.py]` `[src:src/libifstate/__init__.py:269-274]`.
- ethtool: arbitrary `ethtool:` settings executed as `ethtool --set-<setting>`/etc.; prior state cached in `/run/libifstate/ethtool/<businfo|permaddr|id>__<setting>.state` for diffing; runs inside the netns `[src:src/libifstate/link/base.py:444-583]`.
- TC: full qdisc/filter config per interface; `cshaper` is a simplified cake-based profile layer `[src:src/libifstate/tc/__init__.py]` `[src:src/libifstate/__init__.py:334-428]`.
- XDP/BPF: optional, need libbpf; `xdp` attaches programs, `bpf` pins objects `[src:src/libifstate/xdp/__init__.py]` `[src:src/libifstate/bpf/__init__.py]`.

Kernel-module mapping for initrd (upstream NixOS module) `[src:module.nix:38-68]`: bond→bonding, bridge→bridge, vlan→8021q, vrf→vrf, vxlan→vxlan, geneve→geneve, wireguard→wireguard, gre/gretap→ip_gre, ip6gre/ip6gretap→ip6_gre, vti→ip_vti, vti6→ip6_vti, sit→sit, ipip→ipip, dummy→dummy, ifb→ifb, tun→tun, team→team, dsa→dsa_core, macvlan/macvtap/ipvlan→same, xfrm→xfrm_interface, ipoib→ib_ipoib, vxcan→vxcan.

## 8. Reproducible MAC addresses (2.4.0+)

If `link.address` is absent, ifstate sets a default L2 address `[src:docs/docs/macaddr.md:1-2]`:

- **Virtual interfaces**: SHAKE256 over `mac_seed || ifname` (6-byte digest, locally-administered bit forced) `[src:src/libifstate/netns/__init__.py:222-237]`.
- `mac_seed`: root netns = `"link\0" + machine_id + "\0\0"`; named netns appends the netns name; per-netns `mac_seed:` config replaces it (`"link\0\0" + seed + "\0"`); `null` disables generation for that netns `[src:src/libifstate/netns/__init__.py:192-220]`. Documented with digest examples `[src:docs/docs/macaddr.md:5-22]`.
- machine-id sources and the `len(set(id)) > 4` validity filter: §1; DMI `product_uuid` added as fallback in 2.5.0. If no machine-id exists, no reproducible MACs are enforced (2.5.0 fix #225) and a warning tells you to set `parameters.machine_id` `[src:src/libifstate/netns/__init__.py:77-80]`.
- **Physical interfaces**: default = permanent address (`perm_address`), unless `link_address_default.physical: generated` `[src:src/libifstate/link/physical.py:48-62]`.
- Modes per kind configurable via `parameters.link_address_default` for macsec/physical/vlan: `generated` (reproducible), `inherited` (parent iface), `permanent` `[src:src/libifstate/util.py:367-383]`.
- No default MAC for non-Ethernet kinds (gre, ip6gre, ip6tnl, ipip, ipvlan, sit, vti, vti6, wireguard, xfrm) `[src:src/libifstate/link/base.py:415-433]` — in 2.4.0 the schema dropped `link.address` for exactly those kinds (breaking change) `[src:CHANGELOG.md:96-124]`. Bond slaves are skipped `[src:src/libifstate/link/base.py:741-747]`. NOARP interfaces get no default MAC (2.4.2 #190); layer-3 TUN interfaces fixed in 2.5.1 (#231) `[src:CHANGELOG.md:10-17,71-74]`.
- IPv6 tokenized interface identifiers (`token:` per interface, draft-chown-6man-tokenised-ipv6-identifiers) since 2.4.0 (#151/#187); skipped for NOARP, only set when changed (2.4.2 #191; apply-only, 2.4.1) `[src:src/libifstate/link/base.py:929-971,1111-1136,1201-1235]`.

## 9. Addresses, routes, rules, sysctl

### Addresses

`Addresses.apply()` `[src:src/libifstate/address/__init__.py:100-237]`: permanent addresses are compared attribute-by-attribute (proto/scope/label/local via `IFA_*` attrs; `proto: 0` means unspec); mismatches and missing addresses are (re)added with `ip addr add`, extra non-ignored addresses removed with `ip addr del`. DAD-failed addresses are renewed. Dynamic addresses survive unless `ignore.ipaddr_dynamic: false` and the address is not permanent `[src:src/libifstate/address/__init__.py:188-192]`. 2.5.1 fixed renewal of dynamic addresses being kept (#235, regression) `[src:CHANGELOG.md:10-13]`. Implicit `proto` is `0` (unspec) except on `lo` `[src:src/libifstate/address/__init__.py:106]`.

### Routes

`parse_route()` maps config → netlink: `to`→dst, `via` (cross-AF nexthop becomes `RTA_VIA`), `dev`→oif, `src`→prefsrc, `onlink`→flags, `preference`→metric (defaults: IPv6 priority 1024, IPv4 0), `table`/`scope`/`proto`/`realm` resolved through `/etc/iproute2` lookups (defaults table 254, scope 0, proto 3, realm 0), `type` (default unicast), `multipath` (≥2 nexthops with `hops` weights; a single-path multipath silently degrades), `vrrp` tagging `[src:src/libifstate/routing/__init__.py:232-321,537-551]`. Apply = `route replace` for changed/new, `route del` for orphans not matched by `ignore.routes`; local table 255 invisible; cloned routes ignored `[src:src/libifstate/routing/__init__.py:653-821]`. Multipath and cross-family-via documented `[src:docs/docs/routing.md:28-55]`. Optional Rust acceleration for route/neighbour lookups since 2.5.0 (#197), requires libifstate-rs ≥0.4.2 at 2.5.1 `[src:src/libifstate/rust/__init__.py]` `[src:CHANGELOG.md:33,22]`.

### Rules (PBR)

`parse_rule()` keys: `table` (default 254), `proto`, `tos`, `action` (to_tbl/unicast/blackhole/unreachable/prohibit/nat), `fwmark`, `ipproto` (name or number), `to`, `from` (`all` = 0.0.0.0/0), `iif`, `oif`, `priority`, `family`, `vrrp` `[src:src/libifstate/routing/__init__.py:324-402]`. Apply diffs against both AF_INET and AF_INET6 kernel rule lists: missing ones added, unmatched leftovers deleted unless ignored `[src:src/libifstate/routing/__init__.py:824-1029]`. VRF example shows `vrf_table` link option + per-table routes `[src:docs/examples/vrf.md]`.

### Sysctl

Three scopes `[src:docs/docs/sysctl.md]` `[src:src/libifstate/sysctl/__init__.py]`:

- top-level (and per-netns) `sysctl:` with `all`/`default` (→ `/proc/sys/net/conf/{all,default}/…`) and global families `mpls`/`mptcp` (→ `/proc/sys/net/<family>/…`); other keys are per-interface `conf/<iface>/…`.
- `sysctl_conf` (2.5.0, #222): free-form `sysctl.conf`-style lines, children of `net`, comments/empties allowed, `!include`-able `[src:docs/docs/sysctl.md:56-69]`.
- Implementation writes `/proc/sys/net/...` files directly; reads are netns-aware via pushns/popns; `stable_secret` read failures tolerated; keys sorted so `stable_secret` comes first; globals that fail with FileNotFoundError on first pass are queued in `globals_retry` and retried after interfaces are created (2.5.0 lazy-module support) `[src:src/libifstate/sysctl/__init__.py:53-198]`. Default `Sysctl()` seeds `all.ipv6.optimistic_dad: 1` `[src:src/libifstate/sysctl/__init__.py:21]`.

## 10. Hooks and DHCP

Hooks glue userspace daemons (DHCP clients, PPP, RA) to interface state `[src:docs/docs/hooks.md:1-8]` `[src:src/libifstate/hook/__init__.py]`:

- Global definitions in `parameters.hooks.<name>: {script, provides, after}` or bare names resolved as executables in `/etc/ifstate/hooks` (also auto-registered from that dir) `[src:src/libifstate/hook/__init__.py:167-174]` `[src:src/libifstate/parser/base.py:11-21]`. Per-interface `hooks: [{name, args, timeout}]` (default timeout 3 s).
- Invocation: generated `wrapper.sh` runs the script **inside the interface's netns** (`ip netns exec`) and **VRF** (`ip vrf exec`) with env `IFS_SCRIPT/IFS_RUNDIR/IFS_IFNAME/IFS_INDEX/IFS_NETNS/IFS_VRF/IFS_ARG_*` and one argument `start|stop|check-start|check-stop` (check variants in dry-run) `[src:src/libifstate/hook/wrapper.sh]` `[src:src/libifstate/hook/__init__.py:47-121]` `[src:docs/docs/hooks.md:13-34]`.
- Return codes: 0 ok / 1 error / 2 started|stopped / 3 changed (env `IFS_RC_*`) `[src:docs/docs/hooks.md:36-46]` `[src:src/libifstate/hook/__init__.py:23-28]`.
- Hook state per (netns, ifindex) is persisted in `/run/libifstate/hooks/.../state`; hooks whose config disappeared or changed are stopped; rundirs removed on stop `[src:src/libifstate/hook/__init__.py:176-257]`. 2.5.0 fixed incomplete quoting of ifname/netns (#59 in changelog Fixes) `[src:CHANGELOG.md:57-63]`.
- Reference DHCP hook: `ex/hooks/start-stop-daemon/udhcpc` manages a udhcpc pidfile, config checksum restart, start/stop/check actions `[src:ex/hooks/start-stop-daemon/udhcpc]`. The upstream NixOS module asserts `networking.useDHCP` is off and points users to hooks (issue #111) `[src:module.nix:153-160]`.

## 11. WireGuard specifics

`WireGuard` (pyroute2 WireGuard netlink device API) `[src:src/libifstate/wireguard/__init__.py]`:

- Interface keys: `private_key`, `listen_port`, `fwmark`; peers are a **dict keyed by base64 public key** (2.0 breaking change from a list) with `preshared_key`, `allowedips` (normalized to `ip_network` sets), `endpoint`, `persistent_keepalive_interval` `[src:src/libifstate/wireguard/__init__.py:34-57]` `[src:docs/docs/upgrades.md:160-200]`.
- `table:` on the wireguard block auto-adds one route per allowed-ip into that table (`get_routes()` feeds `Tables.add`) `[src:src/libifstate/wireguard/__init__.py:60-78]`.
- `apply()` replaces base settings and diffs peers: new peers added, changed peers updated (`replace_allowed_ips`), configured-away peers **removed** `[src:src/libifstate/wireguard/__init__.py:122-232]`.
- Endpoints are applied **after routing** (§1) so DNS/LLA resolution works post-config; `parse_endpoint()` handles bare IPs (default port **51820**), `[v6%scope]:port`, hostnames; broken lookups are skipped with a warning (2.5.0/2.3.1 fixes for LLA scope + portless IPv6, #208/#209) `[src:src/libifstate/wireguard/__init__.py:234-341]` `[src:CHANGELOG.md:60-63]`.
- WireGuard kind is in `attr_bind_kinds` and has no default MAC / no `link.address` in schema `[src:src/libifstate/link/base.py:122-138,415-433]`.
- Show hides keys unless `-S` (§4); a netns-scoped example (bind/link across netns) exists `[src:docs/examples/wireguard-netns.md]`.

## 12. VRRP (keepalived integration)

Config: `vrrp: {name, type: group|instance, states: [...]}` attachable to interfaces and to routes/rules (YAML anchors make sharing DRY) `[src:docs/docs/vrrp.md:1-44]`. States map to keepalived notify strings; `backup_priority`→`backup`, `master_priority`→`master`; `master_rx_lower_pri` ignored `[src:src/ifstate/vrrp.py:17-31]`.

Semantics in `_apply_iface`/`_apply_routing` `[src:src/libifstate/__init__.py:824-852]`:

- Normal `apply`: links/routes/rules marked `vrrp` are **skipped** entirely.
- `vrrp`/`vrrp-worker` apply: only objects whose (type,name) match are handled; matching objects whose state is **not** in `states` are forced `state: down` (routes/rules use `VRRP_MATCH_DISABLE` to leave kernel entries alone).
- `vrrp-fifo` spawns one `vrrp-worker` per group/instance, feeds state lines over stdin, reloads config on SIGHUP (this is what a plain `apply` triggers via `sighup_vrrp_fifo`), cleans pid/cfg files on SIGTERM/exit `[src:src/ifstate/vrrp.py:39-196]`.

Keepalived side: `vrrp_notify_fifo /run/vrrp-ifstate.fifo` + `vrrp_notify_fifo_script "/usr/bin/ifstatecli vrrp-fifo"` `[src:docs/docs/vrrp.md:45-75]`.

## 13. Network namespaces

- Must run from root netns (§2). With no `namespaces:` section, all foreign-netns links are ignored (§1, §5) `[src:docs/docs/namespaces.md:1-2]`.
- `prepare_netns()` creates missing/configured namespaces, deletes orphans (after checking `ignore.netns` and warning about resident pids) `[src:src/libifstate/netns/__init__.py:240-272]`.
- Inside a namespace: `bpf`, `interfaces`, `routing`, `sysctl` `[src:docs/docs/namespaces.md:49-55]`.
- Cross-netns references: `bind_netns` (tunnel outside), `link_netns`/`master_netns`/… (upper/lower or master in another ns, `null`=root); resolution via `get_netnsid()` with automatic nsid allocation `[src:docs/docs/namespaces.md:56-61]` `[src:src/libifstate/netns/__init__.py:161-190]`.
- Non-root namespaces get a private pyroute2 `NetNS` handle plus a **read-only sysfs tmpfs** mounted at `/run/libifstate/sysfs/<ns>` (needed for ethtool/identify lookups) `[src:src/libifstate/util.py:236-302]`.

## 14. Idempotence and live changes

- `check` is the dry-run of `apply`; both share `_apply` and produce identical logs except no netlink mutations happen when `do_apply=False` `[src:src/libifstate/__init__.py:471-475,589]`.
- Design goal: converge from any previous state to the config in one run, and repeated applies are no-ops ("reaches the desired network configuration from any previous state") `[src:docs/docs/index.md:3-4]`.
- Live-change behaviors worth remembering: interfaces are set down before attribute changes and restored after `[src:src/libifstate/link/base.py:1182-1199,1334-1343]`; IPv6 tokens only touched when changed `[src:src/libifstate/link/base.py:1201-1203]`; routes use atomic `replace`; sysctl globals retried after module autoload `[src:src/libifstate/__init__.py:795-803]`.
- Functional tests assert idempotence-style invariants (e.g. `test_check` runs `check` and verifies no links appear) `[src:tests/test_check.py]`.

## 15. Logging and debugging

- Logger `ifstate`, non-propagating; `IfStateLogging` installs a QueueHandler→QueueListener fan-out to stderr and, when `/dev/log` is a socket and not running under systemd (`INVOCATION_ID` absent), a syslog handler with ident `ifstate[-action][pid]` `[src:src/libifstate/log.py:10-31,80-163]`. 2.5.0: "avoid duplicate logging in systemd, refactor/simplify socket detection" `[src:CHANGELOG.md:38-41]`.
- Levels: default INFO; `-v` DEBUG (and `sys.tracebacklimit` restored so tracebacks print); `-q` WARNING. Very verbose (`-vv`) sets global logging `[src:src/ifstate/ifstate.py:251-267]` `[src:src/libifstate/log.py:111-119]`.
- Output style: per-line `iface`/`option` columns, ANSI colors on TTY (green ok / yellow change+del / red error) via `STYLE_OK/CHG/DEL` `[src:src/libifstate/log.py:31-100]`. Helpers `log_ok/log_change/log_del/log_err` produce the `ok/change/del` tokens seen in docs `[src:src/libifstate/log.py:12-29]`.
- Debug extras: `-v` dumps dependency/stage lists, per-setting diffs, exact `ip link add/set`, `ip addr add/del`, `ip route replace`, `ip rule add`, ethtool command lines (all `logger.debug` calls cited above); `showall` reveals builtin defaults/ignores; `shell` gives a live pyroute2 REPL.

## 16. Failure modes (observed in code)

| Failure | Behavior |
|---|---|
| Config unreadable / YAML error / include error / schema fail | exit 1 / 2 / 3 / 4 with formatted detail `[src:src/ifstate/ifstate.py:77-99,298-309]` |
| Feature missing (bpf/xdp/wireguard/rust…) | exit 5 before apply `[src:src/libifstate/__init__.py:236-238,446-450]` |
| Not root netns | exit 6 `[src:src/ifstate/ifstate.py:63-72]` |
| Circular link deps | apply: log cycle, drop unresolved, continue; check: exit 5 `[src:src/libifstate/__init__.py:547-560]` |
| Physical NIC not identified | registry search finds nothing → `create()` warns "unable to create physical link"; interface stays unmanaged (and may be shut down as orphan unless ignored) `[src:src/libifstate/link/physical.py:42-46]` |
| WireGuard socket open fails (no kmod) | warning logged, peers skipped `[src:src/libifstate/__init__.py:434-444]` |
| Netlink errors on link set | collected in `ExceptionCollector`; creatable links fall back to recreate; uncorrectable settings logged per-attr `[src:src/libifstate/link/base.py:1285-1328]` |
| Cross-netns reference to unknown ns | `NetnsUnknown` warning; link state forced down `[src:src/libifstate/link/base.py:679-685,714-729]` `[src:src/libifstate/exception.py:128-130]` |
| Hook error/timeout/nonzero rc | `! hook` log + RC_ERROR; timeout kills after 3 s default `[src:src/libifstate/hook/__init__.py:108-121,233-248]` |
| vrrp-fifo unparsable fifo line | warning, loop continues `[src:src/ifstate/vrrp.py:189-194]` |
| pyroute2 0.9.3 | excluded by `pyroute2!=0.9.3` — known upstream regression crash (svinota/pyroute2#1380) `[src:pyproject.toml]` `[src:CHANGELOG.md:329-332]` |

## 17. NixOS packaging facts (upstream)

- Upstream ships `module.nix` (NixOS module) + `flake.nix` exposing `packages.ifstate` (via `package.nix`) and `nixosModules.ifstate/default` `[src:flake.nix]`.
- The module **disables the downstream nixpkgs module** `services/networking/ifstate.nix` to avoid duplicate options `[src:module.nix:100-102]`.
- Options: `networking.ifstate.{enable,package,settings}`; initrd: `boot.initrd.network.ifstate.{enable,package,settings,cleanupSettings,allowIfstateToDrasticlyIncreaseInitrdSize}` `[src:module.nix:103-147]` `[src:docs/docs/nixos-options.md]`.
- Assertions: not together with NetworkManager; `networking.useDHCP` off (use hooks instead); initrd requires systemd stage-1 and stage-2 ifstate `[src:module.nix:151-160,198-212]`.
- `boot.extraModprobeConfig`: `options bonding max_bonds=0`, `options dummy numdummies=0`, `options ifb numifbs=0` — so ifstate alone creates these devices `[src:module.nix:164-169]`.
- Stage-2 systemd unit `ifstate.service`: oneshot, `DefaultDependencies=no`, after udev-settle/sysusers/sysctl, before `network.target`, `ExecStart=ifstatecli --config <store path> apply`, 2 min timeout `[src:module.nix:69-95,178-196]`.
- Initrd: config + cleanup config baked into the initrd closure (`!include` targets included via closure of the config file), `ifstate-initrd.service` applies config on start and **cleanup config on stop** (ExecStop) before switching root `[src:module.nix:214-300]`.
- Initrd kernel modules auto-enabled from configured interface kinds via `interfaceKernelModules` `[src:module.nix:34-36,226-233]`.
- Dependencies for the package: jsonschema, pyroute2 (!=0.9.3), pyyaml, setproctitle; optional extras `shell` (pygments), `rust` (libifstate-rs) `[src:pyproject.toml]`.

## 18. 2.5.1 vs 2.4.x change summary

From `CHANGELOG.md` (all `[src:CHANGELOG.md]`):

**2.5.0 (2026-10-08) features**: shell completion (#220); link flags (#206); altnames (#46/#224); `!flatten` yaml tag (#200); optional Rust acceleration for routes/neighbours (#197); configurable default MACs for macsec/physical/vlan (#213/#216); DMI product_uuid as `mac_seed` fallback; route lookup caching; schema additions (`br_stp_state` #192, macvlan/macvtap #218, most ip6gre/gre #199/#218, vti/vti6 #218, geneve #218, sit #218, `ifalias` max length = IFALIASZ); sysctl global retry for lazy module loading; `sysctl_conf` free-form (#222); pre-commit + pytest functional test harness (#193/#217); SBOM artifact; pyproject/uv migration.

**2.5.0 breaking changes**: Python <3.11 dropped.

**2.5.0 fixes**: hook quoting; veth peer crash; no machine-id → no enforced reproducible MACs (#225); WireGuard LLA-scope endpoints + portless IPv6 parsing (#208/#209).

**2.5.1 (2026-10-11)**: fixes — keep renewed dynamic addresses (#235); altnames removal crash (#232); no default MAC on layer-3 TUN (#231); crash on missing link with inherited vlan/macsec address (#237); boolean ethtool options crash (#230); permanent-neighbour lookup without libifstate-rs (#234). Changes — `clear_altnames` in `parameters.defaults` (#233); require libifstate-rs ≥0.4.2; more functional/unit tests (#236).

**2.4.2 (2026-08-29)**: IPv6 token set only when changed (#191); no default MAC for NOARP (#190).

**2.4.1 (2026-06-10)**: `validate` action; ethtool CLI feature-name aliases (#188); IPv6 token not set for NOARP / not in check mode / netlink-EINVAL handling; netns machine-id exception fix (#189).

**2.4.0 (2026-06-08) breaking**: reproducible MAC addresses always applied (physical → permanent, virtual → SHAKE256-derived) — interfaces without explicit `link.address` get new stable MACs on upgrade (#185); IPv6 tokenized interface identifiers (#151/#187); schema dropped `link.address` for gre/ip6gre/ip6tnl/ipip/ipvlan/sit/vti/vti6/wireguard/xfrm; ethtool feature names migrated to kernel names (aliases only for unambiguous CLI names); OpenRC reload/checkconfig.

Notable for a skill pin: the 2.4.0 MAC change is the biggest operational surprise when moving a config from 2.3.x; the 2.5.x additions (flags/altnames/`!flatten`/`sysctl_conf`/Rust) are pure additive except the py3.11 floor and the 2.5.1 bug fixes.

## 19. Behaviors worth proving in a NixOS VM

High-value, cheap-to-verify assertions for a NixOS VM test of the skill/module (each maps to a code fact above):

1. **Convergence/idempotence**: run the systemd unit (or `ifstatecli apply`) twice; second run logs everything `ok` and `check` exits clean. (§1, §14)
2. **Orphan cleanup vs ignore**: create a dummy iface + address not in config → after apply it is gone; add `parameters.ignore.ifname: ["^keep"]` → it survives set-down only if physical, untouched if it matches ignore. (§1, §5)
3. **Physical identify + rename**: use `identify` output from `ifstatecli identify` (e.g. `parent_dev_name`) to pin a NIC to a new name; verify rename and that a wrong `identify` leaves the NIC unmanaged (and shut down as orphan). (§6, §16)
4. **Reproducible MAC stability**: two applies yield the same MAC; deleting and recreating a dummy/vlan yields the same MAC; `mac_seed: null` yields kernel-default MACs. (§8)
5. **Defaults clear semantics**: an interface omitted from `interfaces:` gets addresses cleared and is set down (builtin default); a matching `parameters.defaults` entry with `clear_addresses: false` preserves addresses. (§5)
6. **WireGuard round-trip**: configure wg0 with peers + `table:` auto-routes; verify `ip route show table <t>`; `show` hides private_key unless `-S`; `!include` of a key file works (sops-style path). (§4, §11)
7. **VLAN/bridge/VRF basics**: vlan subinterface with `vlan_id`/`vlan_protocol`; bridge with `brport`; VRF master + per-table default route + `ip rule`/PBR rule. (§7, §9)
8. **netns lifecycle**: declare a namespace with a veth pair across root/netns (`peer_netns`/`link_netns: null`); verify creation, apply, and orphan removal after deleting the section. (§7, §13)
9. **sysctl incl. `sysctl_conf` and lazy retry**: `mpls.platform_labels` (needs module load) applied via retry; free-form `sysctl_conf` lines land in /proc. (§9)
10. **Hooks/DHCP**: a test hook writing `$IFS_IFNAME/$IFS_ARG_*` to a file on start/stop, plus check-mode (`check-start/check-stop`) invocation without side effects; timeout path. (§9/§10)
11. **VRRP gating**: config with `vrrp:`-marked interface/route is inert under plain apply and applied under `ifstatecli vrrp instance VRRP0 master`; non-matching state forces link down. (§12)
12. **Failure exits**: invalid YAML → exit 2; schema violation → exit 4; circular link deps → check exit 5 vs apply continue. (§2, §16)
13. **NixOS module integration**: `networking.ifstate.settings` builds (check-jsonschema at build time), `ifstate.service` is oneshot before network.target, and `boot.initrd.network.ifstate` cleanup config applies at ExecStop. (§17)

## Appendix: quick source map

| Area | File |
|---|---|
| CLI | `src/ifstate/ifstate.py` |
| Core algorithm | `src/libifstate/__init__.py` |
| Link base (apply/identify/rename/MAC) | `src/libifstate/link/base.py`, `src/libifstate/link/physical.py` |
| netns + MAC seed + registry | `src/libifstate/netns/__init__.py` |
| Parser/defaults/ignore builtins | `src/libifstate/parser/base.py`, `src/libifstate/parser/yaml.py` |
| Addresses / routing / sysctl | `src/libifstate/address/__init__.py`, `src/libifstate/routing/__init__.py`, `src/libifstate/sysctl/__init__.py` |
| Hooks | `src/libifstate/hook/__init__.py`, `src/libifstate/hook/wrapper.sh`, `ex/hooks/start-stop-daemon/` |
| WireGuard / VRRP | `src/libifstate/wireguard/__init__.py`, `src/ifstate/vrrp.py` |
| Logging / exceptions / paths | `src/libifstate/log.py`, `src/libifstate/exception.py`, `src/libifstate/paths.py` |
| JSON schema | `schema/2/ifstate.conf.schema.json` (packaged: `src/libifstate/schema/2/…`) |
| NixOS module | `module.nix`, `flake.nix`, `package.nix` |
| Functional tests | `tests/` (runner `tests/data/_run.sh`, uses `unshare --map-root-user --net`) |
