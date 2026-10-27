# Operations and debugging

Separate read-only inspection from deliberate mutation. On a remote router, an apparently small apply can remove the management path because reconciliation also cleans up undeclared state.

## Read-only inspection

```bash
# Config and parser
ifstatecli validate
ifstatecli -v check
ifstatecli show
ifstatecli showall
ifstatecli identify

# NixOS unit and generated config
systemctl cat ifstate.service
systemctl show ifstate.service -p Result -p ExecStart
systemctl status ifstate.service --no-pager
journalctl -u ifstate.service -b --no-pager
readlink -f /etc/ifstate/ifstate.yaml

# Kernel state
ip -d link show
ip address show
ip route show table all
ip -6 route show table all
ip rule show
ip netns list
bridge link show
bridge fdb show
wg show
```

`check` is a dry run of the apply algorithm, not merely a schema check. Inspect its proposed changes; its exit status reports execution/parser failures, not a machine-readable “zero diffs” assertion. `validate` checks parsing/schema without comparing live state. `show` reverse-engineers running state; `showall` also exposes built-in defaults and ignores. [CLI source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/ifstate/ifstate.py)

Do not use `-S/--show-secrets` in logs or shared output. It reveals WireGuard private and preshared keys.

A successful `ifstate.service` is normally inactive after it finishes. Check `Result=success` and the journal instead of waiting for an active daemon:

```bash
systemctl show ifstate.service -p Result --value
journalctl -u ifstate.service -b --no-pager
```

## Deliberate apply and rollback

```bash
# Preview the exact alternate config first
ifstatecli -c /path/to/candidate.yaml validate
ifstatecli -v -c /path/to/candidate.yaml check

# Apply only after reviewing every deletion and link-state change
sudo ifstatecli -c /path/to/candidate.yaml apply

# Reapply the active NixOS generation
sudo systemctl start ifstate.service
```

Apply ignores SIGHUP, SIGPIPE, and SIGTERM so a dropped SSH session does not leave an intentional half-apply. That also means disconnecting is not a safe cancellation mechanism. Use a maintenance window and out-of-band console for changes affecting the management path. [CLI apply handling](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/ifstate/ifstate.py)

IfState has no whole-network transaction rollback. Recovery is:

1. Use console/out-of-band access if the management path is gone.
2. Restore the last known-good NixOS generation or known-good YAML.
3. Reapply it with `systemctl start ifstate.service` or `ifstatecli -c <known-good> apply`.
4. Inspect for objects created by other writers after the failed apply; IfState cannot roll those back for you.

`nixos-rebuild dry-activate` previews NixOS unit actions, not IfState's netlink diff. Use both dry-activate and `ifstatecli check` when the activation impact matters.

## A debugging sequence that localizes the fault

1. **Is the config valid?** Run `validate`; inspect the generated YAML rather than only the Nix expression. NixOS already schema-validates at build time, so a runtime schema error can indicate package/config drift or a manually edited file.
2. **Did the unit finish?** Check `Result`, journal, and the two-minute timeout. A missing NIC, unavailable include, failed hook, or netlink error can leave partial state.
3. **Did IfState find the intended device?** Compare `ifstatecli identify`, `ip -d link`, permanent MAC, and PCI/bus identity. A physical interface cannot be created to satisfy a bad identify block.
4. **Is another writer fighting it?** Look for NetworkManager, systemd-networkd, DHCP clients, Cilium, libvirt, keepalived, FRR staticd, or hand-written `ip` commands. Re-run `check` after a few seconds; recurring diffs are a writer-ownership symptom.
5. **Which kernel layer is wrong?** Inspect link, address, route, rule, neighbour/FDB, and sysctl separately. Then inspect namespace-specific state with `ip netns exec NAME ...`.
6. **Is the dynamic routing control plane healthy?** Use `vtysh` for FRR RIB and sessions, then compare with the kernel FIB. Do not add an IfState route to compensate for a BGP session that is down.
7. **Does a second apply converge?** Reapply only after understanding the first failure. Repeated identical errors are evidence; repeated blind applies can repeat disruption.

Use `-v` for dependency stages, exact object diffs, and netlink-equivalent operations. `-vv` increases logging further. Start with `-v check` so the detailed trace is non-mutating.

## Common failures

| Symptom | Likely cause and next check |
|---|---|
| `inactive (dead)` immediately after boot | Normal oneshot completion; check `Result=success` and journal |
| Exit 1 / 2 / 3 / 4 | Config open / YAML parse / include / schema error respectively |
| Exit 5 | Missing feature or circular link dependency; run `-v check` |
| Exit 6 | Not running in the root network namespace |
| Physical NIC stays unconfigured | Identify mismatch or device not enumerated; compare `identify` and udev timing |
| Interface disappears on rebuild | It was an undeclared virtual orphan; declare or ignore it |
| Physical NIC loses addresses and goes down | It was undeclared; cleanup does not delete physical links but does shut them down |
| VM taps disappear on rebuild | Add `^vnet`/`^tap` ownership ignores |
| Cilium links disappear on rebuild | Add `^cilium_`/`^lxc` ignores and verify Cilium ownership |
| FRR static route disappears | Protocol 196 is not built-in ignored; declare it or ignore protocol 196 |
| WireGuard peer has `allowed ips: (none)` | Another peer's overlapping AllowedIPs shadows it |
| WireGuard interface exists but no traffic | Check handshake, endpoint route, AllowedIPs, UDP firewall, and both peers |
| BGP route visible in vtysh but not kernel | Inspect zebra and kernel rejection; do not create a duplicate IfState route |
| `check` repeatedly shows the same diff | Another writer or an uncorrectable setting; inspect `-v` output |
| `ifstatecli --version` says 2.5.0 on the 2.5.1 package | Known upstream 2.5.1 tag version-string bug |

[Exception definitions](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/exception.py) · [Failure handling research](research/upstream.md#16-failure-modes-observed-in-code)

## FRR and EVPN triage

```bash
vtysh -c 'show bgp summary' -c 'show ip route'
journalctl -u frr -n 200 --no-pager
ip -4 route show proto 3
ip -4 route show proto bgp
ip -4 route show proto 196

vtysh -c 'show bgp l2vpn evpn summary' -c 'show evpn vni'
vtysh -c 'show evpn mac vni 100' -c 'show evpn arp-cache vni 100'
ip -d link show vxlan100
bridge fdb show dev vxlan100
```

The RIB/FIB split matters: bgpd decides routes, zebra installs them, and IfState owns only its declared static state. An IfState apply must not become an undocumented third routing-policy mechanism.

## Maintenance and upgrades

- Pin the package and schema together. The NixOS module validates against `cfg.package.passthru.jsonschema`; mixing a new config with an old package fails early, which is desirable.
- Before upgrading, read the changelog and run `check` with the new package in a VM or staging host. Pay particular attention to cleanup defaults, reproducible MAC behavior, and schema changes.
- Stage-2 changes normally need no reboot; initrd and loaded-module parameter changes do. Live application can still disrupt traffic.
- Keep a VM smoke test for your own renderer: schema generation, second-apply convergence, orphan/ignore behavior, WireGuard connectivity, and FRR route preservation are high-value assertions.
- On fleets, test one representative of each hardware/topology role before broad deployment. Physical identify data and driver timing are machine-specific even when inventory settings are uniform.

[2.5.1 changelog](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/CHANGELOG.md) · [VM verification for this skill](research/vm-verification.md)
