# OpenShell on this fleet

Working notes + artifacts for using the local OpenShell gateway (VM driver)
from this repo. Concepts and the gateway itself:
[documentation/docs/openshell/index.md](../documentation/docs/openshell/index.md).

## Concepts in 60 seconds

- **Gateway** — the control plane (`openshell-gateway` systemd service,
  loopback + mTLS). Owns sandboxes, providers, policies.
- **CLI** — `openshell`, talks to the gateway as a client over mTLS.
- **Compute driver** — what actually runs sandboxes. Here: **vm**
  (openshell-driver-vm): every sandbox is its own libkrun microVM.
- **Sandbox** — a workload instance: an OCI image's rootfs as a microVM
  root disk, a canonical main process, optional attached providers and a
  policy.
- **Policy** — the security contract: filesystem (read-only/read-write
  paths), Landlock, process identity, and `network_policies` (which binary
  may reach which host:port, with L7 method/path rules). FS/Landlock are
  static (recreate to change); network rules hot-reload via
  `openshell policy set`.
- **Provider** — a named bundle of credentials (API keys, tokens) created
  from a **profile** and attached to a sandbox. The gateway only injects
  the credential into requests to endpoints the profile declares, and the
  profile's endpoint/binary bindings become part of the effective policy.
- **Profile** — gateway catalog entry describing a service: credential env
  vars, endpoints, allowed binaries. Profiles live in
  `openshell/profiles/`.
- **Policy-enforced egress** — sandbox egress is deny-by-default. The VM
  driver's supervisor intercepts TCP 443 transparently (no proxy env
  vars) and admits or denies per `network_policies` (which binary may
  reach which host:port, with L7 method/path rules). For admitted hosts
  it TLS-intercepts with its own CA, injected as the standard CA env vars
  (`SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `CURL_CA_BUNDLE`,
  `GIT_SSL_CAINFO`, `REQUESTS_CA_BUNDLE`, `DENO_CERT`) so clients verify
  without config. Watch `openshell logs <sandbox> --tail --source
  sandbox` for `DENIED` lines when something is blocked.

## 1. Smoke-test the VM driver

Verified on ghost (kernel `6.12.76`, 4 vCPU / 8 GiB defaults; sizing
is driver-wide — see §2):

```bash
openshell sandbox create --name smoketest --detach -- sleep infinity
openshell sandbox exec -n smoketest -- uname -r          # 6.12.76 (libkrun)
openshell sandbox exec -n smoketest -- sh -c 'ls /dev/kvm'   # No such file
openshell sandbox exec -n smoketest -- python3 -c "import socket; s=socket.socket(); s.settimeout(5); s.connect((\"1.1.1.1\",443))"
# PermissionError: [Errno 13]   ← deny-by-default egress
openshell logs smoketest --tail --source sandbox
openshell sandbox delete smoketest
```

**No `/dev/kvm` inside sandboxes** — nixos vm tests run under QEMU TCG
(software emulation): `-sm` tiers only, with generous `--memory`, minutes
not seconds. Build vm-test *derivations* freely; run the tests on the
host (`.#vm-test` uses host KVM).

CI-equivalent (nested KVM, from the repo root):
`nix run .#vm-test -- openshell-gateway-lg --driver`.

## 2. The code-agent image — the one sandbox image

`flake-parts/ociImages/code-agent.nix` builds `code-agent-image` with
nix2container. It is the single OpenShell sandbox image on this fleet —
devenv is human-only and nothing else ships an OCI. What it bakes in:

- **Toolset on the sshd default PATH** (`/bin` + `/usr/local/bin` +
  `/etc/profile`): bash, coreutils, git, gh, curl, jq, ripgrep, openssh,
  tmux, nix — as user `agent` (UID 1000) with a real `/etc/passwd`. A
  baked `/etc/gitconfig` sets the org bot identity
  (`andrewthomaslee-agent <…@users.noreply.github.com>`) and a
  github.com-scoped credential helper that feeds git the
  provider-injected `$GITHUB_TOKEN` (https push works without prompting;
  verified against the org repo).
- **nix runtime package adds**: `NIX_CONFIG` carries flakes plus
  `sandbox = false` and `filter-syscalls = false` — the microVM is the
  isolation boundary and the supervisor's seccomp stack blocks nix's
  builder-child filter. FlakeHub substituters mirror the host caches,
  and clan-core's niks3 cache (`cache.geninf.io`, keys baked) is
  pre-trusted too. The policy admits `cache.nixos.org`, the clan cache
  hosts, and any `*.cachix.org` cache.
  Add packages at runtime with `nix profile install nixpkgs#<pkg>`
  (**substitution-only**: no `/dev/kvm` in sandboxes, so TCG builds
  crawl). The image's nix db is initialized at build time
  (`initializeNixDatabase`). For another Cachix-backed package, pass the
  cache
  + public key with the install (policy alone doesn't make nix use it):
  `NIX_CONFIG="$NIX_CONFIG extra-substituters = https://nix-community.cachix.org \
    extra-trusted-public-keys = nix-community.cachix.org-1:…" nix profile install nix-community#…`
- **Three AI coding agents** (§3) from the `llm-agents` flake input,
  pre-wired against the kimi-for-coding / claude providers.
- **Repo skills baked at `/opt/skills`** — the same merged skill tree
  `inputs.agents.lib.mkSkills` builds for the NixOS hosts (the home
  repo's `skills/` tree + external flake-input skill sources), wired
  into every CLI: pi via `~/.pi/agent/settings.json`
  (`skills: ["/opt/skills"]`), kimi-code via `~/.kimi-code/skills`,
  claude via `~/.claude/skills`, plus the `~/.agents/skills` standard
  location — all baked at both `$HOME` roots (`/sandbox` under the
  supervisor, `/home/agent` for plain docker).
- **Nix language tooling**: `nixd`, `alejandra`, `statix`, `deadnix` —
  agent-edited `.nix` files can be vetted in-sandbox without a TCG
  package build.
- **Non-API traffic silenced in env**: kimi's models.dev catalog refresh
  and telemetry, and claude's updater/telemetry/error-reporting, are
  disabled (`KIMI_CODE_MODEL_CATALOG_REFRESH_ON_START=false`,
  `DISABLE_AUTOUPDATER`, `DISABLE_TELEMETRY`, ...) so the policy `DENIED`
  log stays meaningful.
- **Foreign-glibc support**: `/lib64` loader, glibc/gcc libs copied into
  the classic multiarch dirs, and a pregenerated `/etc/ld.so.cache`
  (`ldconfig -r` inside the layer; /etc is read-only under policy, so the
  cache must pre-exist). Downloaded dynamically-linked binaries just run.
- **VSCodium server pre-baked**: `vscodium-reh` (pinned to the fleet's
  codium version/commit in the module) lives at
  `/sandbox/.vscodium-server/bin/<commit>` with its bundled node
  patchelf'd to the image glibc — jeanp413 open-remote-ssh connects
  instantly, offline. When nixpkgs' vscodium moves, bump
  `vscodiumVersion`/`vscodiumCommit`; until rebuilt, the install script
  transparently falls back to downloading (the `vscodium_server` policy
  rule covers it).
- **Built with nix2container, not dockerTools**: the VM driver's
  image-prep reproducibly corrupts the ext4 it makes from a large
  dockerTools stream ("Block bitmap checksum does not match"); tiny
  dockerTools images pass and nix2container images of any size/layer
  count pass, so the trigger is size-dependent. Don't switch builders
  without re-running the provisioning test below.

Build + load (the VM driver resolves the host docker store first;
registry pull is the fallback):

```bash
nix run .#load-code-agent-image
```

Sizing is **driver-wide, not per-sandbox**: the VM driver takes vCPUs,
memory and the writable overlay disk size from the gateway config
(`hostSpec.services.openshell.gateway.vm.{vcpus,memMiB,overlayDiskMiB}`
in flake-parts/nixosModules/openshell-gateway.nix — 4 vCPU / 8 GiB / 32
GiB sparse overlay by default). `openshell sandbox create --cpu/--memory`
are accepted but ignored by the VM driver, and there is no disk flag;
a size change applies to newly created sandboxes (existing overlays are
kept as-is). Watch usage with `df -h /` inside the sandbox — /tmp and
/dev/shm are tmpfs (RAM-backed) and do not use the overlay.

Create:

```bash
openshell sandbox create --name code --from code-agent:latest \
  --policy openshell/policies/code-agent.yaml --detach -- bash -l
openshell sandbox connect code      # detach with Ctrl-P, then Ctrl-Q
openshell sandbox exec -n code -- nix --version
```

Attach providers (kimi-for-coding, claude-subscription, github-agent) at create:

```bash
openshell sandbox create --name code --from code-agent:latest \
  --policy openshell/policies/code-agent.yaml \
  --provider kimi-for-coding --provider claude-subscription --provider github-agent \
  --detach -- bash -l
```

## 3. AI coding agents in the sandbox

The image ships three agents, all from the `llm-agents` flake input
(overlays/default.nix routes them into `pkgs`): **pi** (bun-compiled
standalone ELF), **kimi-code** (node), **claude-code** (native binary).
Credentials are never baked in — the attached providers inject them as
env vars ($KIMI_API_KEY, $CLAUDE_CODE_OAUTH_TOKEN or
$ANTHROPIC_AUTH_TOKEN) at sandbox start, and
each CLI's config only *references* those env var names.

**Interactive, inside the sandbox terminal:**

```bash
openshell sandbox connect code        # or: openshell sandbox exec -n code --tty -- pi
pi            # preconfigured: kimi-for-coding via $KIMI_API_KEY (subscription, not platform API),
              # routed through the sandbox's single headroom proxy (127.0.0.1:8787)
kimi          # same subscription via baked config.toml (type = "anthropic", apiKeyEnv
              # $KIMI_API_KEY, same :8787 proxy) — no /login; the OAuth hosts are
              # policy-unreachable on purpose
claude        # via the same :8787 proxy (anthropic upstream in claude sandboxes);
              # credential from claude-subscription ($CLAUDE_CODE_OAUTH_TOKEN, default)
              # or claude-code ($ANTHROPIC_AUTH_TOKEN, platform key) — never both;
              # the platform.claude.com startup preflight is admitted by the policy
```

One sandbox is dedicated to ONE coding agent: `code-sandbox --agent
pi|kimi|claude` at create stamps `$CODE_AGENT` (selecting the proxy's
upstream and the auto-attached credential provider), and a launcher for
the wrong routing family refuses to run. All launchers lazy-start the
headroom proxy on first run (`headroom-proxy-ensure`; log
`/tmp/headroom-proxy-8787.log`, `headroom doctor` health-checks,
`curl -s 127.0.0.1:8787/stats` shows token savings). All agent user
configs — MCP trio (headroom/nixos/github), provider wiring, proxy
routing, the environment briefing — are
home-manager-generated into the agents' config files by the image's
standalone HM evaluation (`homeSpec.agents.*` in
flake-parts/ociImages/code-agent.nix).

The repo's skills (`/opt/skills`) are advertised by name+description in
each CLI (pi and kimi-code: `/skill:<name>`; claude: `/`-invoked skills)
and loaded on demand. `claude auth login` also works: the OAuth token
polling endpoint (`platform.claude.com/v1/oauth/token`) is admitted in
the policy — but with a claude provider attached you don't need
it.

**From the outside via VSCodium** (§5): connect with Remote-SSH, open
`/sandbox`, and run the same CLIs in the integrated terminal — the remote
window IS the sandbox, with live file sync and SCM diffs.

Agent egress is deny-by-default: the `kimi_for_coding` (api.kimi.com) and
`claude_code` (api.anthropic.com + platform.claude.com preflight/login)
rules in `openshell/policies/code-agent.yaml`
pin the resolved process images (`libexec/pi/pi`, node, `.claude-wrapped`);
watch `openshell logs code --tail --source sandbox` for `DENIED` lines when
adding more agents.

## 4. Providers

Providers attach credentials to a sandbox; profiles (versioned in
`openshell/profiles/`) declare the endpoints and binaries they may reach.

```bash
openshell profile list                                   # gateway catalog
openshell profile import --file openshell/profiles/<name>.yaml   # once
openshell provider create --name <name> --type <profile-id> \
  --credential KEY        # bare KEY reads the env var (no shell history)
openshell sandbox provider attach code <name> --wait
```

Verify with `openshell provider list` / `provider get <name>`. Static
credentials resolve only for hosts/ports/paths the profile declares;
`credential_endpoint_mismatch` means the request authority isn't covered.

Existing profiles: `github-agent.yaml` (fine-grained bot PAT for agent
push work — see the token recipe below), `kimi-for-coding.yaml`
(Moonshot Kimi for Coding subscription endpoint, api.kimi.com — NOT the
pay-per-token platform API), and `claude-code.yaml` (Anthropic endpoint
with a Claude Teams subscription bearer token).

```bash
# kimi-for-coding (key from your kimi.com subscription; pi reads it via
# the baked models.json, kimi-code via its own config)
export KIMI_API_KEY=$(jq -r '."kimi-coding".key' ~/.pi/agent/auth.json)
openshell profile import --file openshell/profiles/kimi-for-coding.yaml   # once
openshell provider create --name kimi-for-coding --type kimi-for-coding \
  --credential KIMI_API_KEY    # bare KEY reads the value from the env

# claude-subscription (default claude provider — Pro/Max/Team subscription:
# 1-year OAuth token from `claude setup-token`, injected as
# $CLAUDE_CODE_OAUTH_TOKEN so Claude Code bills the subscription)
claude setup-token   # browser flow on any machine; token prints once
export CLAUDE_CODE_OAUTH_TOKEN=<token>
openshell profile import --file openshell/profiles/claude-subscription.yaml  # once
openshell provider create --name claude-subscription --type claude-subscription \
  --credential CLAUDE_CODE_OAUTH_TOKEN

# claude-code (platform alternative: Console API key, pay-per-token —
# attach INSTEAD of claude-subscription, never both: $ANTHROPIC_AUTH_TOKEN
# outranks $CLAUDE_CODE_OAUTH_TOKEN in Claude Code's credential precedence)
export ANTHROPIC_AUTH_TOKEN=<Console platform API key, sk-ant-api...>
openshell profile import --file openshell/profiles/claude-code.yaml       # once
openshell provider create --name claude-code --type claude-code \
  --credential ANTHROPIC_AUTH_TOKEN
```

### GitHub bot token (for github-agent)

1. Create a dedicated GitHub account for the agent (machine account).
2. On that account: **Settings → Developer settings → Personal access
   tokens → Fine-grained tokens → Generate new token**.
3. Resource owner: your user/org. Repository access: **Only select
   repositories** — just the repos the agent may touch.
4. Permissions: **Contents: Read and write** (clone/push), **Pull
   requests: Read and write** (agent opens PRs), **Issues: Read and
   write** (optional), **Metadata: Read** (mandatory/auto). Skip
   everything else — no Actions, no Administration.
5. Expiration per your paranoia; rotating means re-running
   `openshell provider update github-agent --credential GITHUB_TOKEN`.
6. If an org enforces SAML SSO, authorize the token (Configure SSO).

### Rotating provider credentials

```bash
export GITHUB_TOKEN=github_pat_<new>
openshell provider update github-agent --credential GITHUB_TOKEN
openshell sandbox stop code && openshell sandbox start code
```

Injected credential values are opaque supervisor handles that only reach
**new** processes — always restart the sandbox after a rotation.

## 5. Reviewing sandbox work from VSCodium/VS Code

The CLI emits a working Remote-SSH config block:

```bash
openshell sandbox ssh-config code >> ~/.ssh/config
```

- **VS Code** (official builds): Remote-SSH extension → connect to host
  `code`. Or `openshell sandbox connect code --editor vscode`.
- **VSCodium** (`codium` on this fleet): the MS Marketplace Remote-SSH
  extension is license-restricted — install **Open Remote - SSH**
  (jeanp413) from open-vsx instead, then connect to host
  `openshell-code.default`.
- The workdir inside is `/sandbox`; open that folder. The remote window
  IS the sandbox filesystem — edits made inside the sandbox appear live,
  and the SCM view shows diffs (git is on the server PATH). Files can
  also be moved with `openshell sandbox download code <remote-path> <local>`.

### Host-side git + GitHub (personal identity)

Host remotes use SSH. After a repo moves to an org, point the remote at
the org path (org member with admin/write access pushes with the
personal key):

```bash
git remote set-url origin git@github.com:<org>/<repo>.git
git fetch origin
```

Authorize this machine under your personal account (do **not** reuse the
bot token on the host):

1. Recommended — `gh auth login` → GitHub.com → protocol **SSH** →
   `Login with a web browser`. This uploads a key, configures the git
   credential helper, and gives you `gh` on the host.
2. Or manual: paste `~/.ssh/id_ed25519.pub` at
   github.com/settings/keys (Settings → SSH and GPG keys → New SSH key).

Check with `gh auth status` / `ssh -T git@github.com`. Org enforcement
note: if the org ever enables SAML SSO, each key/token needs SSO
authorization ("Configure SSO" on the key page).

## 6. Iterate on policy

```bash
openshell logs code --tail --source sandbox     # NET:OPEN/HTTP ... DENIED lines
openshell policy get code --base | sed '1,/^---$/d' > /tmp/p.yaml
# edit /tmp/p.yaml (network_policies only for hot reload)
openshell policy set code --policy /tmp/p.yaml --wait
openshell policy list code
```

Network-rule-only changes (like adding the `gitea` rule for
`git.clan.lol`) can go into a running sandbox this way — no recreation;
filesystem/Landlock changes still need a fresh sandbox.

Filesystem/Landlock/process changes require recreating the sandbox.
Narrow additive grants: `openshell policy update code
--add-endpoint host:443:read-only:rest:enforce --rule-name ... --wait`.

## 7. Where policies and profiles should live

- **Profiles**: gateway catalog, not per-user. They carry no secrets —
  keep them as files in `openshell/profiles/` (versioned), import with
  `profile import`. Provider *creation* stays manual (it holds secrets);
  the commands above are the runbook.
- **Provider catalog definitions**: `openshell/providers/` holds
  versioned provider *definitions* (credential env vars, endpoints,
  allowed binaries — no secrets), e.g. `github.yaml`, `openrouter.yaml`.
  Import with `openshell provider import --file openshell/providers/<name>.yaml`;
  creating the actual provider with the secret stays manual.
- **Sandbox policy default**: `homeSpec.programs.openshell.sandboxPolicy`
  (flake-parts/homeModules/openshell.nix) renders
  `~/.config/openshell/policy.yaml` + `OPENSHELL_SANDBOX_POLICY` — a
  per-user default for every `openshell sandbox create`. Good for a
  personal baseline.
- **Per-use-case policies**: `openshell/policies/`, passed with
  `--policy` at create time (overrides the env default). This is the
  sweet spot: the baseline travels with the user, the contract
  travels with the use case.
- **Gateway-global policy** (`openshell policy set --global`) exists but
  locks policy control for ALL sandboxes on the gateway — avoid.
- **NixOS module level**: machine/gateway concerns only (driver, sizing,
  secrets, the `docker` group), not per-user policy.

## Pitfalls already hit on this fleet

- `openshell ... | grep -q` panics the CLI on EPIPE (exit 101) — redirect
  to a file, then grep.
- `openshell sandbox exec -n NAME -- cmd` — the name is a flag; a bare
  positional becomes part of the remote command.
- Never bake credentials into images: providers inject at runtime.
- The supervisor sets `HOME` to the workdir and stacks ~5 seccomp
  filters on workloads; nix in the image runs with `sandbox = false` +
  `filter-syscalls = false` because of that.
- Grant `/dev` (ro) + `/dev/ptmx` + `/dev/pts` (rw) in the policy or nix
  dies opening a pseudoterminal master.
- The built-in `github` profile is read-only; pushing needs
  `openshell/profiles/github-agent.yaml`.
- Provider-injected credential env values are opaque supervisor handles
  (`openshell:…`), not the raw secret — the policy proxy swaps the real
  credential in at egress. Consequences: tools that validate token format
  locally (`gh auth status`) report the env token as "invalid" even
  though real API calls through the proxy work; and a rotated secret only
  reaches new processes (restart long-running processes).
- nixpkgs-wrapped CLIs (e.g. `gh` → `bin/.gh-wrapped`) must be pinned by
  their kernel-resolved exe path in profile/policy `binaries` — the
  supervisor matches `/proc/<pid>/exe`, not the symlink (the DENIED log
  line says this too).
- nix2container image `perms` need an explicit `mode`: the nix store
  default is 0555, so a workdir without one comes up read-only.
- docker images need a `Cmd`/`Entrypoint` for the VM driver's
  `docker create` export step — images without one fail with "no command
  specified" before provisioning even starts.
- claude-code's startup preflight hits `platform.claude.com`
  (`/v1/oauth/hello`) and refuses to start without it ("Unable to connect
  to Anthropic services") — it's admitted in the `claude_code` policy
  rule; updater/telemetry hosts (sentry/statsig/GCS) are NOT admitted —
  disable that traffic in the image env instead. Same for kimi-code's
  models.dev catalog refresh (`KIMI_CODE_MODEL_CATALOG_REFRESH_ON_START=false`)
  and its OAuth login hosts — pre-wire `~/.kimi-code/config.toml` with an
  `apiKeyEnv` provider instead of ever calling `/login`.
- kimi-code provider config schema (verified from the bundled binary):
  `providers.<name>.{type,apiKey,apiKeyEnv,baseUrl}`, top-level
  `defaultProvider`/`defaultModel`, `[models.<alias>]` with required
  `provider`/`model`/`maxContextSize`. `type = "kimi"` speaks the
  OpenAI-style wire with Bearer auth (`https://api.kimi.com/coding/v1`);
  `type = "anthropic"` speaks the Anthropic `/messages` wire at
  `https://api.kimi.com/coding` — the code-agent image uses the
  ANTHROPIC variant (verified live in-sandbox 2026-10) so kimi-code can
  share pi's headroom proxy instance (the proxy's anthropic pipeline
  cannot serve the OpenAI-style kimi wire).

## Shell completions

`homeSpec.programs.openshell.completions.enable` (default true) installs
bash/fish/zsh completions generated from the installed CLI at package
build time (`home.packages` → `openshell-completions`). Requires the
shell's completion loader — `programs.bash.enableCompletion` is already
enabled for netsa. Apply with the normal home/nixos deploy
(`sudo nixos-rebuild switch --flake /home/netsa/home`).
