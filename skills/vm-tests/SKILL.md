---
name: vm-tests
description: "Hermetic NixOS VM tests: hermeticity rule, structure (nixosLib.runTest modules under legacyPackages, never checks), sm/md/lg size variants, running via .#vm-test (sandboxed vs driver mode), the agent loop, and patterns/anti-patterns. Load when creating, running, or debugging a VM test."
---

# vm-tests

NixOS integration tests (QEMU VMs booted by the standard NixOS test
driver). Reference for how to create, run, and debug them. In this repo
they auto-discover from `vm-tests/*.nix` and are wired up (sm/md/lg
variants, the `.#vm-test` runner) by `flake-parts/tests.nix`.

## Hermeticity rule

**All VM tests are hermetic and sandboxed by default.** Non-negotiable
unless a test exists specifically to check network behaviour — in which
case it must be explicit in the test file and called out in the change
description:

- No network inside the test. Everything asserted must be in the Nix
  closure. Nothing is downloaded at guest startup.
- KVM is mandatory: `requiredFeatures.kvm = true` and
  `qemu.forceAccel = true` so a non-KVM builder refuses the job instead
  of silently running under TCG for an hour. There is no TCG fallback
  by design.
- No `--no-sandbox`, no `sandbox = false`, no `__noChroot`. Impurity is
  only ever in the *runner invocation* (see below), never in the
  derivation.
- Never rely on host state: no host users, sockets, kubeconfigs, or
  `/nix/store` outside the closure. Fake secrets go in as plain files.

## Structure

Expose tests under `legacyPackages.<system>.vmTests` — never `checks` —
so `nix flake check` (CI's gate) does not try to boot QEMU on KVM-less
runners. Discovery is directory-based over a fixed test dir (e.g.
`vm-tests/*.nix`): regular `.nix` files only, `_`-prefixed and
dot-prefixed files skipped (escape hatch for shared helpers). `git add`
new test files before building.

Each test file is a NixOS-test *module* — the `nixosLib.runTest` form,
not `pkgs.nixosTest`:

```nix
# vm-tests/my-service.nix
{
  name = "my-service";
  globalTimeout = 5 * 60;   # seconds; feeds the driver's global_timeout

  nodes.machine = {pkgs, ...}: {
    # full NixOS config per node
    services.my-service.enable = true;
    environment.systemPackages = with pkgs; [curl jq];
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("my-service.service")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/healthz", timeout=60)
  '';
}
```

- `testScript` is Python: `start_all()`, `machine.succeed("cmd")`
  (asserts exit 0), `machine.fail("cmd")`, `machine.wait_for_unit(...)`,
  `machine.wait_until_succeeds(cmd, timeout=N)`,
  `machine.wait_until_fails`. Assertion style is exit status of shell
  commands: `test -f`, `grep -q`, `jq -e` (bracket notation for
  hyphenated keys: `jq -e '.mcp["some-server"].type == "remote"'`).
- Keep the driver script to orchestration; push complex logic into a
  Python probe written into the guest
  (`environment.etc."probe.py".source = pkgs.writeText "probe.py" ''...''`)
  and run it with `machine.succeed("python3 /etc/probe.py")`. Plain
  `assert` + a final `print("..._OK")` marker. Good for
  protocol-level checks (JSON-RPC over stdio, HTTP bodies).
- `globalTimeout` in-test + an external watchdog in the runner =
  defense in depth against hangs.

## Size variants

Generate one sm/md/lg variant per test by varying only resource limits
(`lib.mkDefault` so tests can override per node): sm = 2 cores /
4096 MiB mem / 30 GiB disk; md = 2x; lg = 3x. Test names are
`<basename>-<sm|md|lg>`; run `-sm` for iteration, larger variants for
resource-hungry config. The variant is injected with `name = mkForce`
so the driver's internal name matches the attribute.

## CI resource caps

CI runs these on a self-hosted desktop runner that is in use
(kamrui-h1: 30 GiB RAM, Ryzen 7 6800H 8c/16t). Hard per-VM caps —
`virtualisation.memorySize` ≤ 16384 MiB, `virtualisation.cores` ≤ 8 —
enforced by `checks.vm-test-resources` (grep gate inside
`nix flake check`, so a violation fails the push gate). Undeclared
means the nixosTest defaults (1024 MiB, 1 core), always safe. The sm
variant's 2 cores / 4096 MiB sits far under the caps; md/lg (up to 6
cores / 12288 MiB) also fit. Keep node-count × memorySize well under
30 GiB. VM tests are manual-dispatch only in CI — never automatic.

## Running

`nix run .#vm-test` (or a repo equivalent) drives everything:

```
nix run .#vm-test -- --list              # list variants
nix run .#vm-test -- my-service-sm       # sandboxed build (CI-style)
                                         # exit code = result; log = build log
```

- Sandboxed mode builds
  `legacyPackages.<system>.vmTests.<name>` as a derivation — the
  default and what CI would run. Needs KVM on the local machine or a
  remote builder:
  `nix run .#vm-test -- my-service-sm <builder>` offloads via
  `--store ssh-ng://<builder>`.
- Driver mode for artifacts and iteration:
  `nix run .#vm-test -- my-service-sm --driver` → `master.log`,
  `junit.xml`, `out/` in `/tmp/<repo>-vm-tests/<name>` (or the repo's
  chosen path). Add `-K` (`--keep-state`) to keep/resume VM state for
  fast restarts, `--interactive` for the ptpython REPL against a live
  VM.
- The runner may use `nix build --impure --expr
  "(builtins.getFlake (toString $REPO_ROOT)).legacyPackages..."` —
  that impurity is the runner reading the possibly-dirty local tree,
  not the test. Do not copy the idiom into derivations or CI steps
  that build real outputs.

## Agent loop for creating/fixing a test

1. Write the test file following the structure above; mirror an
   existing test's conventions before inventing new ones.
2. `git add vm-tests/<name>.nix` — untracked files are invisible to
   Nix.
3. Run the smallest variant: `nix run .#vm-test -- <name>-sm`.
4. On failure: read the tail of the log (driver mode: `master.log`,
   look for the first failing `machine.succeed` and the service journal
   lines around it). Fix the *config under test* first; only change the
   test when the test itself is wrong.
5. Iterate under `--driver -K` to keep VM state between runs (much
   faster than cold boot); clean state before the final verification
   run.
6. Only claim pass on exit 0 of the sandboxed variant. Report the
   command, the variant used, and note any resource override you
   needed (then also run the next size up to confirm the headroom
   claim).
7. New machine configs also need `nix flake check` to stay green — the
   test dir is outside `checks` on purpose; do not "fix" that.

## Patterns and anti-patterns

Patterns:

- `wait_for_unit` / `wait_until_succeeds(..., timeout=N)` — never
  assume ordering; give every wait an explicit generous timeout.
- `linger = true` for test users running systemd user units, and start
  user units deterministically (`systemctl --user daemon-reload` then
  `start` with `XDG_RUNTIME_DIR=/run/user/<uid>` exported) — do not
  race home-manager activation against the user manager.
- Fake secrets as plain `/etc` files in the guest
  (`environment.etc."x".text`, option pointed at the path) — tests
  have no real key material and must not need any. If a
  secret-provisioning module needs a key, derive it from the VM's SSH
  host key (e.g. sops-nix with `services.openssh.enable`) rather than
  embedding one.
- JSON assertions with `jq -e`; file existence with
  `test -f`/`test -x`.

Anti-patterns:

- Any network/model download at guest startup (e.g. an embedding model
  fetched from Hugging Face on first run) — hermeticity dies silently.
  Feature-flag it off in the test config.
- Bare `sleep` instead of a proper wait; asserting on timing rather
  than readiness.
- Reaching into host state, or "fixing" a failure by loosening the
  sandbox.
- Giant single-node configs asserting ten unrelated things — split
  into focused tests; each variant boots 1-3 nodes, so multi-node
  tests multiply resource needs (raise the variant or split instead).
