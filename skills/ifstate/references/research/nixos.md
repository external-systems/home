# IfState on NixOS / nixpkgs — integration research (pinned to upstream IfState 2.5.1)

Date of research: 2026-10-27. All claims cite primary source with commit-pinned URLs.
Local evidence copies live under `/tmp/ifstate-research/` and `/tmp/ifstate-nixpkgs/`
(workdir only; no repo was modified).

## 0. Sources and pins

| What | Commit / tag | Pin |
|---|---|---|
| nixpkgs `nixos-unstable` branch HEAD | `3ec636362e1816bc2f0888fa0fa2c69f1bc9e504` (commit date 2026-10-23, fetched 2026-10-27) | <https://github.com/NixOS/nixpkgs/tree/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504> |
| nixpkgs `nixpkgs-unstable` pin from the home repo flake.lock | `2c423e03bbafcff28bfadc6781a4a8257f205cb5` | matches `nodes.nixpkgs-unstable.locked.rev` in `/home/netsa/external-systems/home/flake.lock` |
| Upstream IfState | tag `2.5.1` = commit `9ac7caaedb55e853347c701197eccb7a245d4c07` (released 2026-10-11) | <https://codeberg.org/routerkit/ifstate/src/tag/2.5.1> |
| Upstream libifstate-rs | tag `0.4.2` (bumped in nixpkgs PR #574062) | <https://codeberg.org/routerkit/libifstate-rs> |
| Legacy Perl switch implementation (for behavior comparison) | branch `nixos-25.05` | <https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/system/activation/switch-to-configuration.pl> |

Upstream moved from `codeberg.org/liske/ifstate` to `codeberg.org/routerkit/ifstate`;
nixpkgs fetcher already uses `routerkit` (older in-tree strings still say `liske`).

## 1. TL;DR

- nixpkgs ships IfState as `pkgs.ifstate` (**version 2.4.2** on current `nixos-unstable`,
  2.4.1 on the home repo's `nixpkgs-unstable` pin). Upstream is at **2.5.1**; the nixpkgs
  bump is **draft PR [#574062] (open since 2026-10-14)** — so today you must override to get 2.5.1 (§7).
- The NixOS module is `networking.ifstate` (+ `boot.initrd.network.ifstate`), vendored at
  `nixos/modules/services/networking/ifstate.nix`, maintained by `marcel`.
- Config is Nix attrset → JSON → YAML via a custom `settingsFormat.generate`, **validated
  at build time** against the package's vendored JSON schema (`check-jsonschema`), then a
  `sed` pass rewrites quoted `'!include …'` scalars into real YAML tags (§3).
- `nixos-rebuild switch` / `test` **do re-apply** stage-2 ifstate config **without a reboot**
  (oneshot service, re-run via the `multi-user.target` start transaction — see §5). A reboot
  **is** needed for initrd ifstate changes, `boot.initrd.availableKernelModules` changes, and
  for `bonding/dummy/ifb` module-parameter changes to bite on already-loaded modules.
- Known sharp edges: hard conflicts asserted only with NetworkManager and
  `networking.useDHCP` (NOT systemd-networkd); a self-described "terribly broken"
  `udevadm settle` wait; initrd size blow-up ack option; physical interfaces are not
  auto-loaded in initrd (§8).

## 2. Package situation in nixpkgs

Package definition: [`pkgs/by-name/if/ifstate/package.nix` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/if/ifstate/package.nix)

- `version = "2.4.2"` (line 17), fetched via `fetchFromCodeberg { owner = "routerkit"; repo = "ifstate"; tag = version; }` (lines 18–23), `hash = "sha256-CcqIVdqyPdTVdhyCpKpbmjYeutidpnYCVtDoZkuq4c4="`.
- Python application (`buildPythonApplication`, `pyproject = true`, lines 57–61), build-system `setuptools` (lines 75–77). Runtime deps (lines 79–89): `pyroute2`, `pyyaml`, `setproctitle`, plus `jsonschema` only when `withConfigValidation ? true` (line 86; removed via `pythonRemoveDeps` when disabled, line 89); `pygments` behind `withShellColor ? false`; `libbpf` behind `withBpf ? false` (with `libbpf.so.1` path substitution, lines 70–73).
- `postPatch` (lines 63–69) rewrites `/usr/share/iproute2` → `${iproute2}/share/iproute2` in `libifstate/routing/__init__.py` and `/usr/sbin/ethtool` → nix ethtool in `libifstate/link/base.py` (2.4.x layout; 2.5.x moved these files under `src/`, see §7).
- `doCheck = false` with comment "has no unit tests" (lines 91–92). (2.5.1 upstream now *has* pytest-based functional tests — its own package.nix runs them; PR #574062 enables `pytestCheckHook`.)
- `passthru` (lines 99–111): `tests = nixosTests.ifstate` (line 100), `features.{withBpf,withConfigValidation,withShellColor}` (lines 101–107), **`jsonschema = "${self}/${python.sitePackages}/libifstate/schema/2/ifstate.conf.schema.json"`** (line 109) — this is the schema the NixOS module feeds to `check-jsonschema`, and `docs` (line 110).
- `meta.mainProgram = "ifstatecli"` (line 120); `meta.maintainers = [ marcel ]` (line 119).

Version history (git log of `pkgs/by-name/if/ifstate/package.nix` on `nixos-unstable`):

| Commit | Date | Change |
|---|---|---|
| `fdc62f1f56` | 2026-08-29 | ifstate 2.4.1 → 2.4.2 (current unstable) |
| `7af92ba226` | 2026-06-23 | patch ethtool path |
| `cce0ea2329` | 2026-06-10 | 2.3.0 → 2.4.1 |
| `3562403503` | 2026-01-31 | treewide fetchFromGitea → fetchFromCodeberg |

Upstream releases: 2.5.0 (2026-10-08), **2.5.1 (2026-10-11)** — see upstream
[`CHANGELOG.md`](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/CHANGELOG.md).
2.5.x highlights: build backend switched setuptools → **uv_build**; `requires-python >= 3.11`;
`jsonschema` became a **mandatory** runtime dep; new optional `libifstate-rs` Rust accelerator
(routes/neighbours/fdb/netns; pure-pyroute2 fallback kept — see below); `!flatten` YAML tag;
shell completions; altname/flags support; schema additions (gre/geneve/sit/vti/macvlan/macvtap, `br_stp_state`, `sysctl_conf`).

Upstream pins `libifstate-rs` at **0.4.1** in its own
[`package.nix` @2.5.1 line 20](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/package.nix),
but the runtime feature gate at 2.5.1 is `LIBIFSTATE_RS_VERSION_0_4 = "0.4.2"`
([`src/libifstate/rust/__init__.py` @2.5.1 line 13](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/rust/__init__.py))
— with 0.4.1 the 0.4-gated accelerators silently stay disabled. The rust module import is
optional (`try: from libifstate_rs import … / HAS_LIBIFSTATE_RS = False` on
`ModuleNotFoundError`, lines 1–8), and consumers check `is_available()` before use
(e.g. `src/libifstate/fdb/__init__.py:65`, `neighbour/__init__.py:20`,
`routing/__init__.py:577`). nixpkgs PR #574062 correctly packages **libifstate-rs 0.4.2**.

**nixpkgs PR [#574062] “ifstate: 2.4.2 -> 2.5.1”** — draft, opened 2026-10-14 by MarcelCoding,
+76/−15 in 1 file (`package.nix` only). It adds the `libifstate-rs` derivation (0.4.2,
maturin build, vendored cargo deps), switches `build-system` to `uv-build`, adds
`nativeCheckInputs = [ pytestCheckHook pytest-timeout pytest-cov-stub pytest-asyncio ]`,
and drops `doCheck = false`. Local copy of the diff: `/tmp/ifstate-research/pr-574062.diff`.
Key hashes from the PR: ifstate 2.5.1 `sha256-wRIFQQYSCsEmK7epFponyVEh9BrkjJWW8t34tDz7Ofg=`;
libifstate-rs 0.4.2 src `sha256-PrF6Kxvd76DIyaoGg5kJyaAZN+3tgeyjOYT17xQ9wQY=`,
cargoVendor `sha256-s8gWx7+dV3NX0dmeohhpq4X5RbT3KV/LoML9oRu3Drc=`.

`uv-build` is available in current nixpkgs as `python3Packages.uv-build` (0.12.5).

## 3. The `networking.ifstate` module

Vendored module: [`nixos/modules/services/networking/ifstate.nix` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/services/networking/ifstate.nix)
(imported from [`nixos/modules/module-list.nix:1291`](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/module-list.nix#L1291)).
Local copy: `/tmp/ifstate-research/nixpkgs-latest/nixos/modules/services/networking/ifstate.nix`.

### 3.1 Options

- `networking.ifstate.enable` (line 102), `networking.ifstate.package` (line 104,
  `mkPackageOption pkgs "ifstate"` — trivially overridable, §7), `networking.ifstate.settings`
  (lines 106–110; type = `pkgs.formats.yaml {}` freeform, i.e. any Nix value convertible to YAML;
  description points to <https://ifstate.net/2.2/schema/>).
- `boot.initrd.network.ifstate.enable` (line 114);
  `allowIfstateToDrasticlyIncreaseInitrdSize` (lines 116–120, default `false`, enforced by
  assertion at lines 205–208); `package` (lines 122–129) defaulting to
  `cfg.package.override { withConfigValidation = false; }` — i.e. **the initrd package derives
  from `networking.ifstate.package`**, so a package override propagates to initrd automatically;
  `settings` (lines 131–135); `cleanupSettings` (lines 137–142, default `{ interfaces = {}; }`
  because the JSON schema requires the key). Cleanup config is applied by `ExecStop` in stage 1
  “before systemd switches to stage two … to deconfigurate the whole network … before the
  firewall is configured” (description, lines 141–142).

### 3.2 Generated YAML + build-time schema validation

`settingsFormat` overrides the `pkgs.formats.yaml` generator (lines 11–34):

1. `builtins.toJSON value` → `yq --yaml-output .` renders JSON to YAML. Comment lines 12–14:
   yq (not remarshal) is used “because it matches yaml datatype handling with IfState”.
2. `check-jsonschema --schemafile "${cfg.package.passthru.jsonschema}" $out` (line 29) —
   every build of the config validates against the schema vendored **inside the ifstate
   package** (`libifstate/schema/2/ifstate.conf.schema.json`). Eval-time typos in
   `settings` therefore fail the nix build, not the boot.
3. `sed -i $'s|\'!include |!include \'|' $out` (line 30) — the `!include` rewrite, §3.3.

The generator runs with `__structuredAttrs = true` and `strictDeps = true` (lines 23, 25;
nixpkgs switched from upstream's `passAsFile` to structuredAttrs in commit `15baf066fd`,
2026-09-14). Stage-2 config lands at `environment.etc."ifstate/ifstate.yaml".source`
(line 173) — the default `--config` path of `ifstatecli` (comment line 172); initrd configs
at `environment.etc."ifstate/ifstate.initrd.yaml"` and `ifstate.initrd-cleanup.yaml`
(lines 215–222). `cfg.package` is installed to `environment.systemPackages` “…there are
other useful subcommands like check or show” (comment lines 170–171).

### 3.3 `!include` rewriting

Upstream parser: [`src/libifstate/parser/yaml.py` @2.5.1](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/parser/yaml.py).
The loader subclasses `yaml.SafeLoader` and registers `add_constructor("!include", self.include)`
(line 25) plus `!flatten` (line 26, new in 2.5.0). `include()` (lines 40–51) constructs the
scalar (the file path), resolves **relative paths against the directory of the including file**
(`self._basedir`, lines 16–22), loads the target recursively with the same loader, and raises
`ParserIncludeError`/`ParserParseError` on missing/unparseable files. Docs:
<https://ifstate.net> config chapter — “The tag will be replaced by the file's content which
can be a literal value or any other YAML structure”, canonical use = WireGuard private keys
in separate files ([`docs/docs/index.md` @2.5.1 lines 81–97](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/index.md)).

Why the sed: in Nix you write the include as a plain string value
(`wireguard.private_key = "!include ${keyfile}"`, see the nixpkgs wireguard test,
§6). As YAML that is a *string starting with* `!include`, which PyYAML would never route to
the custom constructor — the tag must be a real YAML tag on a scalar:
`private_key: !include '/nix/store/…'`. yq quotes such a value as
`private_key: '!include /nix/store/…'`, and the sed moves the opening quote after the tag
(textually: `'!include X` → `!include 'X`). Ordering matters: **schema validation runs before
the sed**, i.e. against the string form (which is what the schema understands as a string
property). Consequences/gotchas:

- Included files must be Nix store paths (or absolute paths) referenced from `settings` so
  they enter the closure — the initrd builder copies “the whole config closure, because it
  can reference other files using !include” (module comment line 241 + `closureInfo` at
  lines 236–245). Relative `!include` works too, resolved against `/nix/store/…-ifstate.yaml`'s
  directory.
- The sed is a textual rewrite of the *serialized* YAML; it fires for any quoted scalar
  starting with `!include ` (also map keys, though upstream documents includes as values).
- At runtime, a missing include file surfaces as `ParserIncludeError` from `ifstatecli`.

### 3.4 systemd unit (stage 2)

`systemd.services.ifstate` (lines 176–201), sharing `commonServiceConfig` (lines 71–95,
modeled on upstream `systemd-networkd.service.in`, comment line 70):

- Ordering: `After=network-pre.target systemd-sysusers.service systemd-sysctl.service`;
  `Before=network.target multi-user.target shutdown.target initrd-switch-root.target`;
  `Conflicts=shutdown.target initrd-switch-root.target`; `Wants=network.target`;
  `DefaultDependencies=no` — explicitly so ifstate can start in initrd **before LUKS unlock**
  (comment lines 91–94).
- `Type=oneshot` (line 187), `ExecStart=<ifstatecli> --config <store path> apply`
  (lines 188–190), `TimeoutStartSec=2min` (comment lines 198–199: oneshots have no default
  timeout).
- `ExecStartPre=-udevadm settle --timeout=180` (line 196) with the maintainer's own caveat
  (lines 192–195): “We wait for the udev events queue to empty in the *hope* that the devices
  needed here become available. This is terribly broken and essentially no better than a
  random sleep(). … FIXME: use .device units dependencies instead.” The leading `-` means
  settle failures don't fail the unit.
- `path = [ "/run/wrappers" ]` (lines 183–184, only for `mount` used by hooks).
- **No `RemainAfterExit`** — the unit goes inactive after each run (this drives the
  activation semantics in §5). No `ExecStop` in stage 2.

### 3.5 initrd ifstate

`boot.initrd.network.ifstate` config block (lines 203–299):

- Assertions: the initrd-size ack (lines 205–208) and “If IfState is used in initrd, it
  should also be used for the stage 2 system … as initrd IfState does not clean up the
  network stack like it was before after execution” (lines 209–212).
- Kernel modules: `availableKernelModules` is derived from the interface kinds in
  `initrdCfg.settings.interfaces` via the static `interfaceKernelModules` map
  (lines 39–69: e.g. `vlan → 8021q`, `bridge → bridge`, `wireguard → wireguard`,
  `gre/gretap → ip_gre`, `xfrm → xfrm_interface`; `"physical"` deliberately unmapped,
  line 53). Physical NIC modules are **not** auto-detected — the nixpkgs initrd test adds
  `kernelModules = [ "virtio_net" ]` itself with the comment “otherwise the interfaces do
  not get created”.
- `boot.initrd.systemd.storePaths` includes a `closureInfo`-derived store closure of
  `initrdCfg.package` **plus both generated config files** (lines 234–254) so `!include`
  targets exist in stage 1.
- Pulls in upstream units `network-online/pre.target, network.target, nss-lookup.target,
  nss-user-lookup.target, remote-fs-pre.target, remote-fs.target`
  (lines 256–265; same list as `systemd-networkd` initrd integration).
- Service `ifstate-initrd` (lines 267–296): same ordering profile, `wantedBy initrd.target`,
  `Type=oneshot`, **`RemainAfterExit=true`** with the explanatory comment (lines 282–284):
  “Otherwise systemd starts ifstate again, after the encryption password was entered by the
  user and we are able to implement the cleanup using ExecStop rather than a separate unit.”
  `ExecStart = ifstatecli --config …initrd.yaml apply`;
  `ExecStop = ifstatecli --config …initrd-cleanup.yaml apply` (i.e. network teardown before
  switch-root, default config removes everything managed);
  `ExecStartPre=-udevadm settle --timeout=180` (line 294, same FIXME as stage 2).
  initrd package is the schema-less build (§3.1), so no `check-jsonschema`/`jsonschema` in
  stage 1.

### 3.6 Kernel module handling (stage 2)

For `cfg.enable || initrdCfg.enable` the module pins
`boot.extraModprobeConfig = "options bonding max_bonds=0\noptions dummy numdummies=0\noptions
ifb numifbs=0"` (lines 147–154, comment “sane defaults to not let IfState work against the
kernel”): the kernel's default `numdummies=2`/`numifbs=2`/`max_bonds=…` would pre-create
devices IfState wants to own. Caveat: these are **load-time** parameters — they only bite
when the module is (re)loaded; a machine that already has `dummy` loaded keeps the old
count until module reload/reboot. Commit `c321cd5771` (2025-11-29) extended this to
initrd-only installations.

## 4. Conflicts (NetworkManager / useDHCP / networkd)

Module assertions (lines 156–165):

- `!config.networking.networkmanager.enable` — “IfState and NetworkManager cannot be used at
  the same time, as both configure the network in a conflicting manner.” (lines 157–160).
- `!config.networking.useDHCP` — “…Please look into IfState hooks to integrate DHCP:
  https://codeberg.org/liske/ifstate/issues/111” (lines 161–164; the module then sets
  `networking.useDHCP = lib.mkDefault false`, line 167, so the assertion only trips if some
  other module forces it `true`). DHCP clients are a documented hook use case upstream
  ([`docs/docs/hooks.md` @2.5.1 line 5](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/hooks.md);
  example hooks in [`ex/hooks/`](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/ex/hooks/)).

**systemd-networkd: no assertion exists.** Nothing in the module prevents running
`systemd.network.enable = true` alongside IfState; both would fight over the same
interfaces. The only networkd interaction is the copied ordering profile/`additionalUpstreamUnits`
(§3.4–3.5). Treat networkd (or `networking.useNetworkd` + per-interface `.network` files) as
an unmanaged conflict by policy.

Other related behavior: `environment.etc` file (§3.2); the upstream module additionally
forces `boot.initrd.network.udhcpc.enable = lib.mkDefault false` and asserts
`boot.initrd.systemd.enable`, but nixpkgs **dropped both** on 2026-10-18 (commits
`2a11322e49` “Remove redundant udhcpc setting”, `6f103ef266` “Drop systemd stage 1 assertion”)
— see divergence note §8.4.

## 5. Activation semantics: what `nixos-rebuild` does to `ifstate.service`

Current implementation is `switch-to-configuration-ng` (Rust), the *only* implementation on
unstable — [`nixos/modules/system/activation/switchable-system.nix` @3ec63636 lines 10–14](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/system/activation/switchable-system.nix)
(“now the only switch-to-configuration implementation”); source
[`pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs)
(local copy `/tmp/ifstate-research/nixpkgs-latest/.../main.rs`). Official narrative docs:
[`what-happens-during-a-system-switch.chapter.md` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/doc/manual/development/what-happens-during-a-system-switch.chapter.md)
and [`unit-handling.section.md` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/doc/manual/development/unit-handling.section.md).

Actions (manual lines 16–20; `main.rs:1843–1861`):

- `switch`/`boot`: install bootloader first (`main.rs:1843–1846`); `boot` then exits
  **before any activation** (`main.rs:1859–1861`) → with `nixos-rebuild boot`, ifstate config
  changes only take effect after reboot.
- `switch`/`test`: compute the diff against the *running* system and activate live. `test`
  differs only in not touching the bootloader. An `init-interface-version` mismatch aborts
  with “won't take effect until you reboot” + exit 100 (`main.rs:1871–1879`).

Unit migration algorithm (the part that matters for a oneshot):

1. `get_active_units()` only returns units whose `ActiveState != "inactive"` (and which
   don't follow another unit) — `main.rs:292–345`, filter at line 320.
2. `collect_unit_changes` iterates **only that active set** (`main.rs:1165`); a changed unit
   is considered only if it exists in the old config *and* is active/activating
   (`main.rs:1237–1239`). Changed active services are then stop+start'ed
   (`X-StopIfChanged` default true, `main.rs:746–835`) or reloaded
   (`X-ReloadIfChanged`, `main.rs:728–737`) or skipped (`X-RestartIfChanged=false` /
   `RefuseManualStop` / `X-OnlyManualStart`, `main.rs:738–742`). Oneshots are *not* special-cased
   anywhere.
3. Active **targets** are unconditionally added to the start set (`main.rs:1247–1274`,
   insert at 1268; filtered from display at 1270–1273), and the final phase runs
   `systemctl start` over that set (`main.rs:2551–2566`) with the comment “Start all active
   targets, as well as changed units we stopped above.”
4. Legacy Perl behaved identically (`switch-to-configuration.pl` @nixos-25.05: loop over
   active units line 594, gate lines 612, targets lines 620–638, “Start all active targets”
   lines 965–975) — so this is long-standing NixOS semantics, not an ng regression.

Putting it together for `ifstate.service` (`Type=oneshot`, **no** `RemainAfterExit`):

- At boot it runs once and goes **inactive** (§3.4).
- On `nixos-rebuild switch`/`test`: the changed unit file is *not* in the active set, so it is
  **not** in the “restarting the following units” list. However `multi-user.target` (active,
  and `ifstate.service` is `WantedBy` it) is always started in the final phase, and systemd's
  start transaction pulls in inactive wanted units — **so `ifstatecli … apply` re-runs with
  the new config** (`ExecStart` embeds the new store path). This transaction-driven re-run is
  exactly the behavior the module authors document for initrd (“Otherwise systemd starts
  ifstate again…”, §3.5), and the ng/Perl test suites only use
  `RemainAfterExit=true` oneshots as restart-detection sentinels
  ([`nixos/tests/switch-test.nix` @3ec63636 lines 150–160 and passim](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/tests/switch-test.nix#L150))
  — restart-on-change detection only *sees* oneshots that stay active.
  Consequence: `switch`/`test` re-apply ifstate **on every rebuild** (even unchanged), which
  is harmless — `apply` is a full reconcile — and is how manual changes get reverted.
- Caveats:
  - The re-run is implicit (target transaction). It appears in the final
    “the following new units were started” report at most, not in “restarting…”; use
    `nixos-rebuild dry-activate` plus §9 commands to confirm.
  - If the unit is *active* when you switch (apply still running), it is handled by the
    normal changed-active path: stop (no `ExecStop` → the oneshot's processes are
    terminated) + start. A **failed** unit passes `get_active_units`' `!= "inactive"` filter
    but fails the `active || activating` gate (`main.rs:1237–1239`), so it is not touched by
    the changed-unit path; it may still be re-pulled by the target transaction below
    (systemd permits start jobs on failed units — `systemctl reset-failed` runs before the
    start phase at `main.rs:2353–2356`).
  - The stage-2 unit has no `ExecStop`, so a switch never “undoes” anything; only the initrd
    unit has stop-time cleanup.

**Is a reboot needed?**

| Change | Reboot? |
|---|---|
| `networking.ifstate.settings` (stage 2) | **No** — re-applied live by `switch`/`test` (see above). `boot` defers to next reboot by design. |
| `networking.ifstate.package` (e.g. 2.4.2→2.5.1) | **No** for the tool itself (new store path is referenced by the regenerated unit/config). Only reboot if the running kernel modules must change. |
| `boot.initrd.network.ifstate.*` (stage 1 configs, initrd package) | **Yes** — initrd is rebuilt; a switch never re-executes stage 1. |
| `boot.initrd.availableKernelModules` (derived from initrd settings) | **Yes** — same reason. |
| `boot.extraModprobeConfig` (`max_bonds/numdummies/numifbs=0`) | Only for the module to *load* with new params — reload the module or reboot; params don't apply retroactively to loaded modules. |

## 6. NixOS tests

Wired in [`nixos/tests/all-tests.nix:879` @3ec63636](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/tests/all-tests.nix#L879):
`ifstate = import ./ifstate { inherit runTest; };`, exposed as `nixosTests.ifstate.*`
(and attached to the package via `passthru.tests`, §2). Six tests under
[`nixos/tests/ifstate/` @3ec63636](https://github.com/NixOS/nixpkgs/tree/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/tests/ifstate)
(local copies in `/tmp/ifstate-research/nixpkgs-latest/nixos/tests/ifstate/`):

- `ping.nix` — two nodes, static v6 on `eth1` (kind `physical`); asserts ping both ways.
- `wireguard.nix` — netns + WireGuard tunnel; uses `private_key = "!include ${pkgs.writeText …}"`
  — the only in-tree exercise of the `!include` sed rewrite (§3.3).
- `partial-broken-config.nix` — one good, one nonexistent interface; asserts ifstate still
  applies the good part and boot completes (a failed oneshot would not block boot anyway —
  it's `WantedBy`, not `RequiredBy`).
- `initrd.nix` — initrd ifstate with `allowIfstateToDrasticlyIncreaseInitrdSize = true`,
  manual `kernelModules = [ "virtio_net" ]`, `boot.initrd.systemd.network.enable = false`,
  plus a `boot-blocker` oneshot to prove initrd networking comes up independently; stage-2
  ifstate enabled (enforced by the module assertion).
- `initrd-wireguard.nix`, `initrd-partial-broken-config.nix` — initrd variants of the above.

Run them from a nixpkgs checkout/pin:
`nix build -L github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504#nixosTests.ifstate.ping`
(etc.; x86_64-linux only — the package is `meta.platforms = lib.platforms.linux`).

## 7. Getting IfState 2.5.1 while nixpkgs ships 2.4.2

`networking.ifstate.package` is a plain package option (`mkPackageOption`, module line 104),
and `boot.initrd.network.ifstate.package` defaults to
`cfg.package.override { withConfigValidation = false; }` (lines 122–129), so overriding the
main package is enough — provided the replacement keeps accepting the
`withConfigValidation` flag (the PR recipe below does).

A minimal `overrideAttrs` on the *2.4.2* derivation is **not** sufficient for 2.5.1:

- build backend changed setuptools → `uv_build` ([`pyproject.toml` @2.5.1](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/pyproject.toml));
- source layout moved `libifstate/…` → `src/libifstate/…`, so the 2.4.2 `postPatch` paths no
  longer exist (upstream now patches `src/libifstate/paths.py` and
  `src/libifstate/hook/wrapper.sh`, [`package.nix` @2.5.1 lines 89–100](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/package.nix));
- upstream vendors version detection via `builtins.readFile ./src/libifstate/__init__.py`
  (upstream package.nix lines 43–45) — only works in a source tree; use a fixed `version` in nixpkgs style.

Recommended recipe — replicate draft PR #574062 (full diff: `/tmp/ifstate-research/pr-574062.diff`;
raw: <https://github.com/NixOS/nixpkgs/pull/574062.diff>) in an overlay:

```nix
# overlay (excerpt — mirrors PR #574062)
final: prev: {
  ifstate = prev.callPackage ./ifstate-2.5.1.nix { };
}
```

`ifstate-2.5.1.nix` = the PR's `package.nix` (essentially the 2.4.2 file with):

- `version = "2.5.1"`; `hash = "sha256-wRIFQQYSCsEmK7epFponyVEh9BrkjJWW8t34tDz7Ofg="`;
- an added `libifstate-rs` derivation (0.4.2, `buildPythonApplication`, maturin hook,
  `cargoDeps = rustPlatform.fetchCargoVendor { … hash = "sha256-s8gWx7+dV3NX0dmeohhpq4X5RbT3KV/LoML9oRu3Drc="; }`,
  src hash `sha256-PrF6Kxvd76DIyaoGg5kJyaAZN+3tgeyjOYT17xQ9wQY=`);
- `build-system = [ python3Packages.uv-build ]`;
- `libifstate-rs` added to `dependencies` (pure-pyroute2 fallback exists if you drop it —
  §2 — but PR parity is one line);
- `nativeCheckInputs = [ pytestCheckHook pytest-timeout pytest-cov-stub pytest-asyncio ]`
  replacing `doCheck = false`.

Usage:

```nix
{
  networking.ifstate = {
    enable = true;
    package = pkgs.ifstate;      # overlayed 2.5.1
    settings = …;
  };
}
```

Notes:

- `pyproject.toml` at 2.5.1 requires `pyroute2 != 0.9.3` — check your nixpkgs' pyroute2
  version before building (current unstable is fine).
- Alternative: consume **upstream's own flake**
  ([`flake.nix` @2.5.1](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/flake.nix)):
  `nixosModules.default` applies its overlay + `disabledModules = [ "services/networking/ifstate.nix" ]`
  ([`module.nix` @2.5.1 line 101](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/module.nix)).
  Not recommended over the nixpkgs module today — the vendored nixpkgs module is *newer* in
  several respects (§8.4), and upstream pins `nixos-26.05` + libifstate-rs 0.4.1.
- Track PR #574062; once merged and in `nixpkgs-unstable`, drop the overlay. Bump cadence
  for reference: 2.4.1→2.4.2 took ~2 months to land upstream→unstable.

## 8. Known limitations & gotchas

1. **udev race**: `ExecStartPre=-udevadm settle --timeout=180` is, per the maintainer,
   “terribly broken and essentially no better than a random sleep()” (module lines 192–195,
   FIXME use `.device` units). Interfaces not yet enumerated at apply time can make apply
   fail or misidentify; combine with `identify`-based configs and re-run `systemctl start ifstate`.
2. **Assertion coverage**: conflicts asserted only with NetworkManager and
   `networking.useDHCP` (§4). systemd-networkd is unchecked; DHCP must be wired via IfState
   hooks (upstream issue #111; [`ex/hooks/`](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/ex/hooks/)).
3. **Schema/option-description drift**: option descriptions link
   <https://ifstate.net/2.2/schema/> while the *enforced* schema is the one vendored in the
   package (`libifstate/schema/2/…`, package.nix line 109) — the description URL is
   informational only; build-time `check-jsonschema` is the real gate. Upstream documents
   schema-per-release at <https://ifstate.net/schema/2/ifstate.conf.schema.json> and the
   JSON Schema Store (`ifstate.yaml`).
4. **Vendored module vs upstream module divergence** (both maintained by `marcel`; the
   vendored copy is *not* a straight copy of upstream 2.5.1's `module.nix`). nixpkgs-only:
   `__structuredAttrs` generator, `udevadm settle` instead of `After=systemd-udev-settle.service`
   (dropped treewide in `1e4eb2df3f`, 2026-04-08), modprobe options also for initrd-only
   (`c321cd5771`), dropped udhcpc/systemd-stage-1 assertions (`2a11322e49`/`6f103ef266`,
   2026-10-18). Upstream-only: `disabledModules` (irrelevant in-tree), the
   `boot.initrd.systemd.enable` assertion, `network.udhcpc.enable = mkDefault false`, a
   `<25.11pre` `mkdir /var/run` workaround, and schema URLs `2.0` vs `2.2`. Functionally
   equivalent for current nixos-unstable; just don't diff against upstream expecting equality.
5. **initrd**: size blow-up requires explicit ack (assertion, lines 116–120/205–208); stage-2
   ifstate is mandatory when initrd ifstate is used (lines 209–212); initrd does not restore
   the pre-boot network config (cleanup config defaults to tearing down everything managed);
   physical interface modules aren't auto-loaded (§3.5).
6. **Module failure modes**: apply failures don't block boot (`WantedBy` soft dependency);
   `TimeoutStartSec=2min` caps long applies; `check` first on live systems (§9). Generated
   YAML includes store paths — included secrets (e.g. WireGuard keys) land in the world-readable
   store unless you use `--show-secrets`-aware handling; prefer agenix/sops secrets with
   appropriate permissions referenced via `!include`.
7. **2.5.1-specific**: upstream's own `package.nix` pins libifstate-rs 0.4.1 while the code
   gates 0.4 features on ≥0.4.2 (§2) — use 0.4.2 (PR #574062 does). The Rust accelerator is
   optional at runtime; missing it only means pyroute2 fallbacks.
8. `settings` is freeform YAML — anything goes at the Nix level; only the build-time schema
   check catches typos (which is why `withConfigValidation=false` is reserved for initrd).

## 9. Maintenance / debug commands (safe)

Inspection (non-mutating):

- `ifstatecli check` — parse + dry-run of `apply` against the current config (module installs
  the package to `environment.systemPackages`, comment lines 170–171).
- `ifstatecli validate` — schema-validate the config only (added in 2.4.1).
- `ifstatecli show` / `ifstatecli showall` — dump the *running* network as an ifstate config
  (diff fodder; note `-S/--show-secrets` exists for dumps).
- `ifstatecli identify` — print per-interface identification attributes (perm_address, PCI
  paths) to build robust `identify:` blocks.
- `systemctl status ifstate`, `journalctl -u ifstate -b`, `systemctl cat ifstate` — unit is a
  oneshot, so `status` shows `inactive (dead)` after a successful run; the journal is the
  source of truth.
- `nixos-rebuild dry-activate` — prints what a `switch`/`test` would stop/start/reload.
- Inspect generated configs: `nix build` your config, then
  `$(nix-build -A config.environment.etc.\"ifstate/ifstate.yaml\".source 2>/dev/null || …)` /
  read the store path directly; re-validate manually with
  `check-jsonschema --schemafile $(nix-build -A config.networking.ifstate.package)/lib/python*/site-packages/libifstate/schema/2/ifstate.conf.schema.json <yaml>`.
- Initrd: `lsinitrd /boot/initrd… | grep ifstate` (or boot with `boot.debug1`/stage-1 shell);
  `journalctl -b -u ifstate-initrd` doesn't survive switch-root — check from the
  `rd.systemd.journal=...`/kmsg side or add `boot.initrd.systemd.services` debug units.

Mutation (deliberate):

- `sudo systemctl start ifstate` — re-apply the current generation's config on demand
  (equivalent to what `switch` triggers; safe to re-run, applies are reconciling).
- `sudo ifstatecli apply [-c /path]` — apply a specific config.
- After changing only `settings`, no reboot is needed (§5). After changing initrd settings or
  kernel modules, `nixos-rebuild boot` + reboot.

## 10. Source index (local evidence)

- `/tmp/ifstate-research/nixpkgs-latest/` — nixpkgs @3ec63636 (module, package.nix, tests, ng main.rs)
- `/tmp/ifstate-research/nixpkgs-pinned/` — nixpkgs @2c423e03 (= home flake `nixpkgs-unstable` pin; package.nix at 2.4.1)
- `/tmp/ifstate-research/ifstate-upstream/` — upstream git repo, **checked out at tag 2.5.1 (9ac7caa)**
- `/tmp/ifstate-research/pr-574062.diff` — the open 2.4.2→2.5.1 nixpkgs bump
- `/tmp/ifstate-research/switch-test.nix`, `switch-to-configuration.pl` (@nixos-25.05),
  `what-happens-during-a-system-switch.md`, `unit-handling.section.md` — activation-semantics evidence
- `/tmp/ifstate-nixpkgs/` — reserved scratch dir

[#574062]: https://github.com/NixOS/nixpkgs/pull/574062
