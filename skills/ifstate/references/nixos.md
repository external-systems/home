# NixOS integration

Primary sources: [nixpkgs module @ `3ec63636`](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/services/networking/ifstate.nix), [upstream 2.5.1 module](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/module.nix), and [activation implementation](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs).

## Module surface

- `networking.ifstate.{enable,package,settings}` controls stage 2.
- `boot.initrd.network.ifstate.{enable,package,settings,cleanupSettings,allowIfstateToDrasticlyIncreaseInitrdSize}` controls stage 1.
- The module installs `ifstatecli` and renders `/etc/ifstate/ifstate.yaml`.
- Generation is Nix attrset → JSON → YAML with `yq`, followed by build-time `check-jsonschema` against `cfg.package.passthru.jsonschema`.
- A final textual rewrite turns a Nix string such as `"!include /run/secrets/wg0"` into a real YAML `!include` tag. Schema validation happens before this rewrite.
- The initrd package defaults to `networking.ifstate.package.override { withConfigValidation = false; }`, so a package override propagates to initrd when the replacement preserves that argument.

The NixOS module asserts against NetworkManager and `networking.useDHCP`, and sets `useDHCP` false by default. It does not assert against systemd-networkd. Make ownership exclusion an explicit part of your own module or service: two reconcilers managing the same interface will continually undo each other's work. [Module assertions](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/services/networking/ifstate.nix#L156-L167)

## Pin 2.5.1 on an older nixpkgs

Check the actual package, not only the flake input revision:

```bash
nix eval .#nixosConfigurations.HOST.config.networking.ifstate.package.version
```

Current nixpkgs may still ship 2.4.x. A version-only `overrideAttrs` is insufficient because 2.5.x moved to a `src/` Python layout and the `uv_build` backend. The following pure-Python override was built and used in the VM verification for this skill. It intentionally omits the optional Rust accelerator; IfState falls back to pyroute2.

```nix
{pkgs, ...}: let
  ifstateSrc = pkgs.fetchFromCodeberg {
    owner = "routerkit";
    repo = "ifstate";
    tag = "2.5.1";
    hash = "sha256-wRIFQQYSCsEmK7epFponyVEh9BrkjJWW8t34tDz7Ofg=";
  };
  ifstate251 = pkgs.ifstate.overridePythonAttrs (old: {
    version = "2.5.1";
    src = ifstateSrc;

    build-system = [pkgs.python3Packages.uv-build];

    postPatch = ''
      substituteInPlace src/libifstate/paths.py \
        --replace-fail '/usr/share/iproute2' '${pkgs.iproute2}/share/iproute2' \
        --replace-fail "/usr/sbin/ethtool" "${pkgs.lib.getExe pkgs.ethtool}"
      substituteInPlace src/libifstate/hook/wrapper.sh \
        --replace-fail ' ip ' ' ${pkgs.lib.getExe' pkgs.iproute2 "ip"} '
    '';

    passthru = old.passthru // {
      jsonschema = "${ifstateSrc}/schema/2/ifstate.conf.schema.json";
    };
  });
in {
  networking.ifstate.package = ifstate251;
}
```

Use `overridePythonAttrs`, not just `overrideAttrs`: the Python build helper must recompute its build inputs after `build-system` changes. If you need the optional Rust accelerator, mirror the complete 2.5.1 nixpkgs package update and use `libifstate-rs` 0.4.2; the pure-Python path above needs no Rust dependency. [2.5.1 package definition](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/package.nix) · [nixpkgs 2.5.1 update PR #574062](https://github.com/NixOS/nixpkgs/pull/574062)

Remove the override only after your pinned nixpkgs actually contains 2.5.1 or newer. At the upstream 2.5.1 tag, `ifstatecli --version` prints 2.5.0; use package metadata to verify this override. [Version-string source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/__init__.py#L77)

## Live activation versus reboot

The stage-2 unit is a `Type=oneshot` without `RemainAfterExit`. It runs `ifstatecli --config <generated-yaml> apply` before `network.target`, with a two-minute start timeout and a best-effort `udevadm settle` beforehand. [Unit source](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/services/networking/ifstate.nix#L176-L201)

For `nixos-rebuild switch` and `test`, NixOS starts active targets as part of activation. The `multi-user.target` transaction pulls the inactive wanted `ifstate.service` back in, so the current generation is applied live. This also means an unchanged rebuild can reconcile away manual drift. `nixos-rebuild boot` does not activate the configuration until reboot. [Activation unit handling](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs#L1247-L1274)

| Change | Live `switch`/`test` sufficient? |
|---|---|
| Stage-2 `networking.ifstate.settings` | Yes |
| Stage-2 IfState package | Yes, apart from kernel-module requirements |
| Initrd settings or initrd interface kernel modules | No; rebuild and reboot |
| `bonding max_bonds=0`, `dummy numdummies=0`, or `ifb numifbs=0` on an already-loaded module | Reload the module or reboot; load-time parameters are not retroactive |

A live apply is not disruption-free. Link attribute changes can set an interface down temporarily, kind changes can recreate it, and cleanup can remove remote access. Preview and use out-of-band access where loss of the management path is possible.

## Initrd

Initrd IfState is for early-boot networking such as remote unlock. It requires stage-2 IfState and an explicit acknowledgement of the larger initrd. The unit stays active so `ExecStop` can apply `cleanupSettings` before switch-root; stage 2 does not restore the pre-boot network state. [Initrd module source](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/modules/services/networking/ifstate.nix#L203-L299)

The module maps configured virtual interface kinds to initrd kernel modules, but does not infer physical NIC drivers. Add the physical driver explicitly, as the nixpkgs initrd tests do for `virtio_net`. Include targets referenced by the generated config enter its Nix closure; runtime secret paths still need to exist in stage 1. [nixpkgs IfState tests](https://github.com/NixOS/nixpkgs/tree/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/nixos/tests/ifstate)

## Secrets and `!include`

`!include` inserts the target file's YAML value in place of the node. Relative paths resolve relative to the including file. Keep private keys out of the Nix store:

```nix
{config, ...}: {
  sops.secrets.wg0-private = {};

  networking.ifstate.settings.interfaces.wg0 = {
    addresses = ["10.200.0.1/24"];
    link = {
      kind = "wireguard";
      state = "up";
    };
    wireguard = {
      private_key = "!include ${config.sops.secrets.wg0-private.path}";
      listen_port = 51820;
      peers."PEER_BASE64_PUBLIC_KEY" = {
        endpoint = "192.0.2.2:51820";
        allowedips = ["10.200.0.0/24"];
      };
    };
  };
}
```

IfState runs as root and can read the deployed secret. Ensure the secret service is ordered before IfState in early boot if the key is needed at that stage. `ifstatecli show` hides WireGuard private and preshared keys unless `-S/--show-secrets` is supplied; avoid sharing output produced with that flag. [Parser source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/parser/yaml.py) · [WireGuard secret filtering](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/wireguard/__init__.py)

## clan-core and clanService pattern

Keep the IfState skill independent of any particular fleet schema. When a clanService renders `networking.ifstate.settings`, a robust split is:

- Inventory role settings hold JSON-serializable topology and policy: segment, VLAN/VNI, address pools, MTU, gateways, route tables, and per-machine allocations.
- Per-machine settings hold hardware identity: PCI/bus or permanent-MAC `identify` values and port assignments.
- Clan vars hold WireGuard private keys; only public keys and non-secret endpoint facts enter settings or exports. Reference deployed key paths through `!include`.
- `perInstance` renders the IfState settings and semantic NixOS assertions. Namespace global resources and generator names by `instanceName` where multiple instances can coexist.
- `perMachine` checks cross-instance invariants: unique interface ownership, intentional default routes, non-overlapping address pools, and no second network manager.
- Exports carry discovery facts such as endpoints and MTU, not private keys or arbitrary runtime state.

Treat the fleet interface as the stable contract and IfState as one renderer. Assert topology errors at evaluation time instead of relying on netlink to reject them on every host. Preserve the source/evidence boundary: these are design recommendations derived from clan's module model, not behavior built into IfState. [clanService authoring guide](https://clan.lol/docs/26.05/guides/services/community) · [vars guide](https://clan.lol/docs/26.05/guides/vars/intro-to-vars)
