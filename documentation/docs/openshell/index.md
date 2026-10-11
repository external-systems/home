# OpenShell

NVIDIA [OpenShell](https://docs.nvidia.com/openshell/) — the sandboxed runtime
for AI agents — on this fleet: architecture, how to consume the gateway
NixOS module and the sandbox OCI image from this flake, day-to-day usage
(including AI coding agents and remote development), and the lessons that
shaped the design.

**One-paragraph model:** a gateway daemon on a NixOS machine owns sandboxes,
credential providers, and per-sandbox security policies. A CLI talks to it
over mTLS. A VM driver runs every sandbox as its own libkrun microVM from
an OCI image built by this flake. All sandbox egress is deny-by-default
(transparent 443 interception + supervisor-injected TLS CA env vars).
`devenv` on this repo is for humans only; the sandbox image is a
separate, purpose-built artifact.

> **Day-to-day usage** (build/load the image, create a sandbox, run the
> agents, refresh after changes): see the
> [Code-Agent Image user guide](code-agent-image.md). The short version:
> the dev shell's `code-sandbox` script builds the image, loads it into
> docker under a content-hash tag, and creates/replaces a sandbox
> (`code-sandbox`, `code-sandbox connect <name>`). This page is the
> architecture reference and design log.

## Architecture

```
┌─────────────────────────────── NixOS machine ───────────────────────────────┐
│                                                                             │
│  openshell-gateway.service (user: openshell, loopback + mTLS :17670)        │
│    └── openshell-driver-vm (spawned, gRPC over compute-driver.sock)         │
│          └── per sandbox: libkrun microVM (OCI rootfs + rw overlay)         │
│                └── supervisor: built-in ssh server, policy proxy, seccomp │
│                      └── YOUR WORKLOAD (bash -l, pi, claude, ...)           │
│                                                                             │
│  /etc/openshell/  system CLI registry (gateway "local" + mTLS bundle)       │
│  docker store     image lookup #1 for the VM driver (openshell ∈ docker grp)│
└─────────────────────────────────────────────────────────────────────────────┘
        ▲ mTLS                                    │ OCI image (code-agent)
   openshell CLI (per-user ~/.config/openshell)   │ nix run .#load-code-agent-image
```

Flake outputs that make this work:

| Output | What it is |
|---|---|
| `nixosModules.openshell-gateway` | Gateway systemd service + VM driver + secrets + CLI seeding (section 1) |
| `packages.code-agent-image` + `apps.load-code-agent-image` | The sandbox OCI image, built with nix2container (section 2) |
| `packages.openshell`, `openshell-gateway`, `openshell-driver-vm` | CLI (built from the pinned input), gateway/driver release binaries |
| `openshell/policies/code-agent.yaml` | The sandbox security contract (filesystem + network) |
| `openshell/profiles/*.yaml` | Provider profiles (kimi-for-coding, claude-subscription, claude-code, github-agent) |
| `openshell/providers/*.yaml` | Provider catalog definitions (github, openrouter) — no secrets; import with `openshell provider import --file` |

## 1. Consuming the gateway NixOS module

The module is exported as `flake.nixosModules.openshell-gateway`. Enable it
per machine (this fleet wires it through clan tags):

```nix
# machines/<name>/configuration.nix (or the equivalent hostSpec tag)
hostSpec.services.openshell.gateway.enable = true;
```

Options (all have sane defaults):

| Option | Default | Notes |
|---|---|---|
| `name` | `"local"` | Gateway name; also the seeded system CLI registration |
| `port` / `healthPort` | `17670` / `17671` | Listener and loopback health endpoint |
| `bindAddress` | `127.0.0.1` | `0.0.0.0` + firewall scoping is the multi-host future |
| `computeDriver` | `"vm"` | `"docker"` also supported; VM is never auto-detected |
| `logLevel` | `"info"` | |
| `provisionSecrets` | `true` | Clan vars generators (below); `false` + the `*File` options accepts external PKI |

With `provisionSecrets = true`, enable then generate:

```bash
clan vars generate <machine>   # mints:
                               #   openshell-local-ca        (shared CA; ca.key never deployed)
                               #   openshell-local-gateway-tls, openshell-local-client-tls
                               #   openshell-local-jwt       (Ed25519 launch-auth signing)
```

What gets deployed: the gateway + managed driver systemd services, an
`openshell` user (member of the `docker` group — the VM driver resolves
sandbox images from the host container store first), the machine-wide mTLS
client identity at `/etc/openshell`, and a system CLI registration named
`local`. Home-manager users get the registration mirrored into
`~/.config/openshell` automatically via
`homeSpec.programs.openshell.enable = true` (the CLI reads the mTLS bundle
only from per-user config; without home-manager, symlink
`/etc/openshell` into `~/.config/openshell`).

Sanity-check after deploying:

```bash
openshell status     # Connected + Authenticated (inspect both lines)
openshell whoami
```

## 2. Building and loading the sandbox OCI image

`flake-parts/ociImages/code-agent.nix` is the **single place** sandbox
images come from. It builds `packages.code-agent-image` with nix2container
and ships `apps.load-code-agent-image` to copy it into the host docker
store (where the VM driver looks first; an OCI registry pull is the
fallback):

```bash
nix run .#load-code-agent-image
```

What the image bakes in (all nixpkgs/`llm-agents`-pinned, no secrets):

- **Toolset on every PATH the supervisor hands out**: bash, coreutils,
  git, gh, curl, jq, ripgrep, openssh, tmux, nix in `/bin` + `/usr/bin`
  + `/usr/local/bin` — running as user `agent` (UID 1000).
- **nix** with flakes and a pre-initialized store db; runtime package adds
  via `nix profile install nixpkgs#<pkg>` (substitution-only — see
  "no /dev/kvm" below).
- **Three AI coding agents** from the `llm-agents` flake input, each
  pre-wired so no interactive login is ever needed: `pi` (baked
  `models.json` reads `$KIMI_API_KEY`, plus an `anthropic` provider
  entry that rides `$ANTHROPIC_AUTH_TOKEN` when the claude-code
  platform provider is attached), `kimi-code` (baked
  `~/.kimi-code/config.toml`: `type = "anthropic"` against the
  headroom proxy — the same Kimi for Coding subscription pi speaks,
  `api_key_env = "KIMI_API_KEY"`, default model k3 at high effort,
  Never Ask permission mode), and `claude`
  (baked onboarding skip, default model claude-opus-5-5,
  `permissions.defaultMode = "bypassPermissions"`; subscription OAuth
  token as
  `$CLAUDE_CODE_OAUTH_TOKEN` from the attached claude-subscription
  provider, or a Console platform key as `$ANTHROPIC_AUTH_TOKEN` from
  claude-code — attach ONE, never both). All agent user configs are
  home-manager-generated (the image's standalone HM evaluation renders
  `homeSpec.agents.*` into the agents' config files), and ALL
  inference routes through a baked, lazy-started headroom proxy pair
  (`:8787` → api.anthropic.com for claude, `:8788` →
  api.kimi.com/coding for pi+kimi) for context compression — see the
  [image guide](code-agent-image.md).
- **Repo skills baked at `/opt/skills`** — the same merged skill tree
  `inputs.agents.lib.mkSkills` builds for the NixOS hosts (the home
  repo's `skills/` tree + external flake-input skill sources), wired
  into all three CLIs — pi via `~/.pi/agent/settings.json`
  (`skills: ["/opt/skills"]`), kimi-code via `~/.kimi-code/skills`,
  claude via `~/.claude/skills`, plus the `~/.agents/skills` standard
  location — at both `$HOME` roots (`/sandbox` under the supervisor,
  `/home/agent` in plain docker).
- **Nix language tooling**: `nixd`, `alejandra`, `statix`, `deadnix`.
- **Sandbox-friendly agent defaults**: folders under `/sandbox` are
  pre-trusted for kimi-code and claude-code by their launcher wrappers
  (both persist trust per absolute path with no wildcard — kimi via
  `~/.kimi-code/workspace-trust/` JSON records, claude via
  `~/.claude.json` `projects[]`), pi auto-grants project trust
  (`defaultProjectTrust = "always"`), and claude's cross-session
  messaging gets a per-session `--messaging-socket-path` in a shared
  private `/tmp` dir (its auto socket-dir walk refuses `/` — owned by
  the VM host's overflow ids). `XDG_RUNTIME_DIR` defaults to a private
  `/tmp/xdg-runtime-<uid>` dir.
- **Non-API agent traffic disabled in env** (kimi models.dev catalog
  refresh + telemetry; claude updater/telemetry/error-reporting) so the
  deny-by-default egress log shows only real API denials.
- **VSCodium Remote-SSH server pre-baked** (vscodium-reh, node patchelf'd to
  the image glibc) at `/sandbox/.vscodium-server/bin/<commit>` — connects
  instantly, offline. Bump `vscodiumVersion`/`vscodiumCommit` in the module
  when nixpkgs' vscodium moves.
- **Foreign-binary support**: the nix-ld shim at
  `/lib64/ld-linux-x86-64.so.2` (reads `NIX_LD` / `NIX_LD_LIBRARY_PATH`
  from the env) runs downloaded glibc ELFs, and `/usr/lib/wheel-deps` on
  `LD_LIBRARY_PATH` (scoped to libstdc++/libgcc_s/libz) lets python
  manylinux wheel extensions resolve their system libs.

After loading, create a sandbox (§3) and attach providers (§4).

## 3. Sandboxes, policies, providers

Day-to-day, don't type the create command — the dev shell ships
`code-sandbox`, which builds the image, loads it as
`code-agent:<imghash>` (content-hash tag, never mutable `latest`), and
creates a sandbox named `<name>-<imghash>` (default `code`) with this
policy and the kimi/github providers, prompting to delete-and-replace
when the name already exists (an existing name always means an older
image, thanks to the hash suffix; `-y` skips the prompt). Manual
equivalent:

```bash
openshell sandbox create --name code --from code-agent:latest \
  --policy openshell/policies/code-agent.yaml \
  --provider kimi-for-coding --provider claude-subscription --provider github-agent \
  --detach -- bash -l

openshell sandbox connect code                    # attach; Ctrl-P Ctrl-Q detaches
openshell sandbox exec -n code -- nix --version   # sibling process, sandbox keeps running
openshell logs code --tail --source sandbox       # DENIED lines show what policy blocked
```

(Sizing — vCPUs, memory, writable overlay disk — is driver-wide gateway
config, not per-sandbox: the VM driver accepts but ignores `--cpu` and
`--memory`, and there is no disk flag. Defaults live in
`hostSpec.services.openshell.gateway.vm.*` of the openshell-gateway
NixOS module: 4 vCPU / 8 GiB RAM / 32 GiB sparse overlay.)

(For scripting against the CLI: `openshell ... | grep -q` panics the CLI
on EPIPE — see §5; `code-sandbox` redirects to a file for this reason.
To (re)write the Remote-SSH config for every active sandbox at once —
e.g. after manual `sandbox create`s — run `code-sandbox ssh-config`.)

- **Policy** (`openshell/policies/code-agent.yaml`): filesystem contract
  (read-only `/nix/store` world + baked `/opt` material, read-write
  `/sandbox` `/nix` `/tmp` `/home`, `/dev/ptmx`+`/dev/pts` for nix/builders)
  plus `network_policies` admitting
  exactly: nix substitution (cache.nixos.org, FlakeHub caches,
  clan-core's niks3 cache cache.geninf.io/cache.clan.lol — baked into
  the image NIX_CONFIG with its keys, any
  `*.cachix.org` cache — the cache still must be named in `NIX_CONFIG`
  with its public key for nix to use it), public GitHub
  (git/curl), read-write git to the fleet's gitea (git.clan.lol — clan
  flake inputs, agent pushes), the kimi + claude agent endpoints (claude
  includes
  platform.claude.com for the startup preflight and `claude auth login`
  token polling), and the VSCodium bootstrap
  fallback. FS/Landlock changes need a recreated sandbox; network rules
  hot-reload (`openshell policy set <name> --policy file.yaml --wait`).
- **Providers** attach credentials to a sandbox; profiles
  (`openshell/profiles/`) declare which endpoints/binaries may use them.
  The gateway injects the credential only into matching requests — the
  in-sandbox env value is an opaque handle, never the raw secret.
- **No `/dev/kvm` in sandboxes**: everything CPU-bound inside is TCG —
  substitution-only nix adds, `-sm` vm tests, patience.

## 4. AI coding agents — interactive and remote

**Inside the sandbox terminal** (`openshell sandbox connect code`):

```bash
pi       # kimi-for-coding subscription, key via attached kimi-for-coding provider
kimi     # pre-wired for the same subscription (baked config.toml, apiKeyEnv
         # $KIMI_API_KEY) — no /login; the OAuth hosts are policy-unreachable
claude   # Claude Pro/Max/Team subscription via the attached
         # claude-subscription provider (`claude setup-token` OAuth token,
         # injected as $CLAUDE_CODE_OAUTH_TOKEN); platform-key billing via
         # claude-code instead — never attach both (bearer precedence
         # shadows the subscription token)
         # (platform.claude.com preflight + auth-login polling admitted in policy)
```

**From the outside via ssh/editors** (review/editing without entering
the sandbox): the CLI emits a working Remote-SSH config, and
`code-sandbox` already appends it to `~/.ssh/config.local` at create
time (managed per-sandbox block, replaced not duplicated;
`--no-ssh-config` to skip):

```bash
openshell sandbox ssh-config code >> ~/.ssh/config
ssh openshell-code.default                 # raw interactive ssh works too
```

Raw ssh, VSCodium and Microsoft VS Code all work — full details (the
supervisor's env-scrub model, terminfo, scp/sftp rooting) in the
[image guide's Remote access section](code-agent-image.md#remote-access-ssh-vscodium-vs-code).

VSCodium (jeanp413 **Open Remote - SSH** from open-vsx — the MS Marketplace
extension is license-restricted) → connect to `openshell-code.default` →
open `/sandbox`. The remote window IS the sandbox filesystem: the agent's
edits appear live, SCM shows diffs, and the integrated terminal runs all
three CLIs with provider credentials attached. First connect needs no
download (server is pre-baked); the install script falls back to fetching
it only when the baked commit no longer matches the client's VSCodium.

Creating the providers (profiles are versioned in-repo; provider creation
holds the secret and stays manual):

```bash
# kimi-for-coding subscription key
export KIMI_API_KEY=$(jq -r '."kimi-coding".key' ~/.pi/agent/auth.json)
openshell profile import --file openshell/profiles/kimi-for-coding.yaml
openshell provider create --name kimi-for-coding --type kimi-for-coding \
  --credential KIMI_API_KEY

# Claude Pro/Max/Team subscription (default): mint a 1-year OAuth token
# (browser flow, works on any machine with the claude CLI), never stored:
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=<token from setup-token>
openshell profile import --file openshell/profiles/claude-subscription.yaml
openshell provider create --name claude-subscription --type claude-subscription \
  --credential CLAUDE_CODE_OAUTH_TOKEN

# Platform-key alternative (Console pay-per-token credits) — attach INSTEAD
# of claude-subscription, never both:
export ANTHROPIC_AUTH_TOKEN=<Console platform API key, sk-ant-api...>
openshell profile import --file openshell/profiles/claude-code.yaml
openshell provider create --name claude-code --type claude-code \
  --credential ANTHROPIC_AUTH_TOKEN
```

Rotating a credential: `openshell provider update <name> --credential KEY`
then restart the sandbox — injected values reach only new processes.

## 5. Lessons learned (read before changing any of this)

Gateway/driver (`nixosModules/openshell-gateway`):

- **Launch authentication is mandatory** — the VM driver rejects sandbox
  creation without gateway-minted launch auth, which requires the Ed25519
  `gateway_jwt` keys. No dev flag.
- **TLS wants three identities**: server cert/key, `client_ca_path`
  (validates CLI certs ⇒ mTLS), and a complete `guest_tls_ca/cert/key`
  bundle (the supervisor's client identity). A plain TLS cert is not
  enough — startup fails.
- **`programs.nix-ld` is required for the VM driver**: the release driver
  extracts its host supervisor (dynamically linked) and execs it.
- **The driver is spawned, not socket-connected**; `grpc_endpoint` must
  match the gateway cert SANs (`https://127.0.0.1:<port>` + `IP:127.0.0.1`).
- **The embedded `libkrun.so` needs `LD_LIBRARY_PATH`** for `libcap-ng`,
  `libseccomp`, `libnuma`, openssl at dlopen time (see
  `packages/openshell-driver-vm` wrapper).
- **The release driver embeds its whole VM runtime** — the rolling
  `vm-runtime` tarball is dev-only; do not pin its hash.
- **Clan vars secrets need explicit ownership** for the `openshell` user
  (membership in `keys` + per-file owner/group/mode), and
  `environment.etc` cannot carry secret material (symlink; mode ignored).

Image/driver interplay:

- **Build sandbox images with nix2container, not dockerTools.** The VM
  driver's image-prep reproducibly corrupts the ext4 it produces from a
  large dockerTools stream ("Block bitmap checksum does not match");
  tiny dockerTools images pass, nix2container images of any size pass.
  Also: images need a `Cmd`/`Entrypoint` (the driver's `docker create`
  export step fails otherwise), and nix2container `perms` need an explicit
  `mode` (the store default 0555 leaves the workdir read-only).
- **There is no OpenSSH sshd in the sandbox** — the supervisor speaks
  ssh itself and spawns every process with a scrubbed env
  (`env_clear`; the image Env is NOT propagated under the VM driver).
  Interactive sessions are `bash -i` (read the baked `~/.bashrc`,
  which sources `/etc/profile`), remote commands are `bash -lc` (read
  `/etc/profile`), and create-time `--env`
  (`packages.code-agent-env`, passed by `code-sandbox create`) is the
  only channel covering every spawn path. Client SetEnv/SendEnv
  requests are discarded; the client TERM arrives verbatim via the pty
  request, so the image bakes a full ncurses + ghostty terminfo db at
  `/usr/share/terminfo`. The Remote-SSH toolchain lives in
  `/usr/local/bin`, not behind an image entrypoint (the supervisor sets
  `HOME` to the workdir and doesn't run workload commands through one).
- **Foreign glibc binaries run through nix-ld, not an ld.so.cache**:
  nixpkgs glibc's compiled-in cache path is its own read-only store
  etc/, so a baked `/etc/ld.so.cache` is never read (and copied FHS
  libs are invisible). The nix-ld shim at `/lib64/ld-linux-x86-64.so.2`
  reads `NIX_LD` + `NIX_LD_LIBRARY_PATH` from the env instead — the
  pre-baked vscodium-reh node is patchelf'd to the store and doesn't
  need it, but any other downloaded glibc ELF does. Python manylinux
  wheels are the other half: the handful of system libs they link
  (libstdc++/libgcc_s/libz) resolve from a scoped `/usr/lib/wheel-deps`
  dir on `LD_LIBRARY_PATH` — broader dirs would shadow nix RUNPATHs
  process-wide (loader search order puts LD_LIBRARY_PATH before
  DT_RUNPATH).
- **nix in sandboxes needs `sandbox = false` + `filter-syscalls = false`**:
  the supervisor stacks ~5 seccomp filters; nix's builder-child filter
  cannot install underneath ("unable to load seccomp BPF program").
- **Supervisor-matched binaries are resolved exes** (`/proc/<pid>/exe`),
  not PATH wrappers: pi is `libexec/pi/pi` (a bun-compiled ELF), kimi-code
  is `nodejs`, claude-code is `.claude-wrapped` — profiles/policies pin
  those, and nixpkgs-wrapped CLIs must be pinned by their wrapped path.
  Worse, nixpkgs `bin/` entries can themselves be symlinks into other
  outputs (`nix`'s `bin/nix` is): pinning the symlink path denies every
  egress of that binary (nix's github.com tarball fetches EACCES'd while
  git/curl worked). The flake renders both templates with `readlink -f`-
  resolved paths for every pinned binary (`flake-parts/openshellConfig.nix`).
- **claude-code's startup preflight is not telemetry**: it hits
  `platform.claude.com/v1/oauth/hello` and hard-fails ("Unable to connect
  to Anthropic services") before the first prompt — admit the host in the
  policy (GET/HEAD/OPTIONS + POST `/v1/oauth/**` covers `claude auth login`
  token polling too), and silence updater/sentry/statsig traffic with the
  `DISABLE_*` env vars in the image instead of admitting those hosts.
- **kimi-code is pre-wired, never `/login`ed**: its config schema
  (`providers.<name>.{type,apiKey,apiKeyEnv,baseUrl}`,
  `defaultProvider`/`defaultModel`, `[models.<alias>]` with required
  `maxContextSize`) supports env-referenced keys. The baked config.toml
  uses `type = "anthropic"` (the Anthropic `/messages` wire at
  api.kimi.com/coding — verified live in-sandbox 2026-10) pointed at
  the kimi-upstream headroom proxy (`127.0.0.1:8788`), replacing both
  the OAuth device flow (whose `auth.kimi.com` hosts stay
  policy-closed) and the OpenAI-style `type = "kimi"` wire (not
  proxyable through headroom's anthropic pipeline — the OpenAI-style
  variant remains the fallback if Moonshot ever moves the wire).
  `KIMI_CODE_MODEL_CATALOG_REFRESH_ON_START=false` stops the models.dev
  fetch failure from littering startup.
- **No docker/podman inside sandboxes — and starship shouldn't pretend
  otherwise.** The image rootfs carries a baked `/.dockerenv` (artifact of
  the host `docker create` image-prep), which made starship's `container`
  module show a bogus `⬢ [Docker]` indicator on every prompt; the agent
  home-manager profile disables the `container` and `docker_context`
  modules. A container runtime is not possible in the microVM anyway
  (verified in-sandbox): workloads run as uid 1000 and user namespaces
  are blocked (`unshare --user --map-root-user` → EPERM under the
  supervisor's 5-filter seccomp stack), which kills rootless docker and
  rootless podman outright; there is no `/var/lib` (filesystem policy),
  no systemd for a rootful daemon, and registry egress
  (`registry-1.docker.io`) is policy-denied. If a task needs containers,
  run them on the host or in a VM test — the microVM itself is the
  isolation boundary.
- **`openshell ... | grep -q` panics the CLI on EPIPE (exit 101)** —
  redirect to a file, then grep.

## 6. Testing

`vm-tests/openshell-gateway.nix` (run via `nix run .#vm-test --
openshell-gateway-sm`, or `-- openshell-gateway-lg --driver` for the tier
that boots a real sandbox in nested KVM): builds a throwaway CA/certs/JWT
store at build time, feeds them through the `provisionSecrets = false`
overrides, boots gateway + managed VM driver in QEMU, and asserts
`openshell status` reports Connected + Authenticated. The `lg` tier pulls
the image, boots a libkrun microVM inside the test VM, and execs
`uname -r` in it (needs external network — run with `--driver`).

## Future plan: `@andrewthomaslee/openshell` clan service

A multi-host variant where any machine can run a gateway and every machine
is a client of every gateway, modeled as a clan service with `server` /
`client` roles. Status: **researched and designed, then deliberately
deferred** — the single-machine module above is the shipping artifact. This
section preserves the design and everything learned, so the work can be
resumed without re-deriving it.

### Design

- `clanServices/openshell/` with `roles.server` (gateway, also a client of
  all servers) and `roles.client` (CLI + registrations). Every machine in
  the instance is a client of every server — including the servers
  themselves — so the CLI wiring lives in `perMachine`, which reads the
  instance's `roles.server.machines` scope directly (the borgbackup
  pattern); no exports needed.
- The CLI natively supports multiple gateways (`gateway add/list/select`,
  `-g`/`OPENSHELL_GATEWAY` per command); the system registry holds many
  `gateways/<name>/` entries with one `active_gateway` fallback.
- Vars generators: shared instance CA (`ca.key` `deploy = false`), per-server
  `gateway-tls` (SANs: machine name, `<machine>.<domain>`, `dnsName`),
  shared `guest-tls` (supervisor identity), per-server Ed25519 `jwt`, and
  per-machine `client-tls` (the machine-wide CLI identity, mode 0644 —
  per-machine, *not* per-user, matching the host-SSH-key threat model).
- Role settings carry `provisionCerts` + `*File` overrides so external PKI
  material works without generators (same escape hatch as the module).
- Split into pure factories (`config.nix` TOML builder, `server-module.nix`,
  `client-module.nix`) + thin clan glue, so tests can import the factories
  without clan machinery — exactly the layering the nixosModule uses today.

### Transport research

clan-core ships `mycelium`, `wireguard`, `yggdrasil`, `zerotier`;
clan-community has `wireguard-star`. All follow one pattern: a vars
generator for node keys, then `exports peer.hosts` populated via
`clanLib.getPublicValue` so consumers get overlay IPs at eval time. **This
fleet already runs Tailscale on every machine** (`tailscale0` is a trusted
interface), so the planned default was: gateway bound to `0.0.0.0` with the
firewall port scoped to `tailscale0`, clients dialing `<machine>` via
MagicDNS, `bindInterface = "tailscale0"` as the server role default
(`"all"` as escape hatch). Mycelium/wireguard would only matter for
machines without Tailscale.

### Clan-native VM testing (clan machinery, mock fleets)

clan-core has first-class support for testing services against **mock
inventories**:

- `perSystem.clan.nixosTests.<name>` (clan-core
  `lib/flake-parts/clan-nixos-test.nix`) accepts a test module that sets
  `clan.directory`, a mock `clan.inventory` (machines + instances +
  `clan.modules` registrations), and `testScript`; upstream
  `hello-world`/`wifi`/`borgbackup`/`syncthing` ship `tests/vm/default.nix`
  this way. It becomes `checks.<system>.<name>` via `nixosLib.runTest` +
  `clan-core.modules.nixosTest.clanTest`.
- **Vars generators run automatically at test build** through
  `varsExecutor.generateVarsDerivation` (IFD on the host system, fixed test
  age key) — no pre-generation. `clan-generate-test-vars` exists only for
  expensive/prompt generators.
- `test.useContainers = true` (default, nspawn) is mutually exclusive with
  user `nodes.<name>`; a gateway test needs `useContainers = false` +
  `nodes` (systemd, KVM, kernel modules).
- Name resolution in the mock fleet: an `importer` instance with
  `roles.default.extraModules` setting `networking.extraHosts`
  (syncthing-test pattern), plus static `eth0` addresses on the nodes.
- Machine pkgs come from the machine's own nixpkgs config (`overridePkgs`
  is only forced for the vars-eval config), so an `importer` instance
  spreading `nixpkgs.overlays` injects the service's packages — keeping
  the service itself free of any building/fetching (packages must come from
  the consuming flake's overlay).
- **CI caveat:** `clan.nixosTests` land in `checks`, and this repo's CI is
  GitHub `ubuntu-latest` — **no KVM**. VM tests must stay in
  `legacyPackages.vmTests` (via `flake-parts/tests.nix`) and be run with
  `nix run .#vm-test`, never through `clan.nixosTests`, until CI has KVM
  runners.

### Lessons learned (implementation gotchas)

- **Nix language**: the pipe operator (`|>`) is not enabled on this flake's
  Nix — use `lib.pipe`/nesting. `builtins.pathExists` guards are needed for
  `readDir`-based autodiscovery of optional directories.
- **Clan service scoping**: `config` is not in scope in `perMachine`/
  `perInstance` outer `let` bindings (lexical scoping) — functions that
  resolve vars generator paths must take `config` as an explicit parameter
  and be called inside the `nixosModule` body. `perMachine` has **no
  `settings` argument** (role settings read via
  `instances.<i>.roles.<r>.machines.<m>.settings`); `perInstance` results
  are `{nixosModule = ...}` attrsets — `concatLists` over them fails,
  extract `.nixosModule`.
- **OpenShell CLI in scripts**: piping `openshell ... | grep -q` makes the
  CLI panic on EPIPE (exit 101) — redirect to a file first, then grep.
- **Sandboxed nix builds have no external network** — any tier pulling a
  container image only works in `--driver` mode (driver runs outside the
  sandbox).
- **The release `openshell-driver-vm` binary is glibc-dynamic** — needs
  `autoPatchelfHook` on NixOS.
- **clan vars secrets are unreachable by service users unless you say so.**
  sops-nix deploys secret files `root:root 0400` under
  `/run/secrets.d/<gen>/vars/...` whose directories are `root:keys 0710`.
  A non-root service user needs (a) membership in the `keys` group (dir
  traversal) and (b) `owner`/`group`/`mode` on the generator *file* —
  these are real per-file options (`modules/clan/export-modules/generic-generator.nix`
  in clan-core, mapped onto `sops.secrets`), as is `restartUnits`, which
  restarts the unit when the var rotates. Without them the gateway
  crash-loops on `Permission denied (os error 13)` reading its JWT key.
- **`environment.etc` cannot carry secret material.** An etc entry whose
  source is a `/run/secrets` path is just a symlink — the `mode` is ignored
  and non-root readers hit the unreadable target (both the service user
  and CLI users, via the home-manager mirror, failed this way). To make a
  secret readable beyond root, override `path` on the clan-mapped
  `sops.secrets` entry (guard with `builtins.pathExists` on
  `vars/.../<file>/secret`, mirroring clan's own filter, and never read
  `config.sops.secrets` from inside a `sops.secrets` definition — infinite
  recursion). The generator file's `.path` follows the override, so the
  gateway config and every CLI user share one deployment.
- Open question never resolved (clan-core at the pinned rev): during a
  `clanTest` machine eval, an import of `<serviceDir>/tests/default.nix`
  was demanded even though nothing referenced it — likely an undocumented
  auto-discovery convention (cf. the unused `lib/clanTest/relativeDir.nix`
  infra). If the clan service is revived, place a `tests/default.nix`
  shim or investigate `clanInternals.inventoryClass` first.
