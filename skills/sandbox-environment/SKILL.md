---
name: sandbox-environment
description: Deep reference for the OpenShell code-agent sandbox OCI image — full admitted-egress host list with the reasoning, nix registry/substituter setup with trusted keys, the baked MCP trio's failure modes, the SSH/shell environment model (no OpenSSH sshd; env scrub; bash -i vs -lc), VSCodium Remote-SSH contract, and troubleshooting recipes. Load when working inside the OpenShell code-agent sandbox and the inline APPEND_SYSTEM.md/SYSTEM.md/CLAUDE.md briefing is not enough (policy misses, cache failures, MCP errors, image layout questions).
---

# Sandbox environment — deep reference

Deep reference for the `code-agent` OpenShell sandbox image (built by
`flake-parts/ociImages/code-agent.nix` in the home repo). The inline
briefing baked into every agent's system prompt
(`~/.pi/agent/APPEND_SYSTEM.md`, `~/.kimi-code/SYSTEM.md`,
`~/.claude/CLAUDE.md`) is the summary; this skill is the detail. Keep
the briefing token-lean — extend THIS file when reference material
grows.

## Layout and runtime facts

- microVM (OpenShell VM driver), uid/gid 1000 (`agent`), workdir
  `/sandbox`, `HOME=/home/agent` in the image Env but the supervisor
  points HOME at `/sandbox` — both roots carry identical per-agent
  config, so either works.
- `/etc` is root-owned read-only. `/nix/store` stays agent-writable on
  purpose (runtime `nix profile install` adds need it); an agent can
  corrupt its own toolset, but the blast radius ends at the disposable
  VM. `/tmp` is mode 1777. Long-running scratch space: `/sandbox`.
- The VSCodium Remote-SSH server is pre-baked at
  `/sandbox/.vscodium-server/bin/<commit>` (also `/home/agent/...`).
- SSH/shell environment model (source: openshell-sandbox
  boundary_exec.rs, openshell-supervisor-process ssh.rs): there is NO
  OpenSSH sshd — the supervisor speaks ssh itself and spawns every
  process with a SCRUBBED env (`env_clear`; only HOME/USER/PATH/TERM/
  SHELL + injected TLS vars + provider creds survive; the OCI image Env
  does NOT propagate under the VM driver). The user-level dotfiles and
  toolset come from a baked home-manager evaluation
  (homeModules.profile-agent-base + the profile-agent OCI flavor,
  generated at image-build time — no runtime HM). Interactive sessions
  are `bash -i` (read the baked ~/.bashrc, which sources the idempotent
  /etc/profile), remote commands/editor bootstraps are `bash -lc`
  (/etc/profile), and the create-time `--env` set (packages.code-agent-env,
  passed by code-sandbox create: LD_LIBRARY_PATH, NIX_LD,
  NIX_LD_LIBRARY_PATH, TERMINFO_DIRS) is the only channel on EVERY spawn
  path — including a workdir-masked HOME (--include-workdir mounts over
  /sandbox's dotfiles). Client SetEnv/SendEnv requests are accepted and
  DISCARDED; TERM arrives verbatim via the pty request, so the image
  bakes the full ncurses + ghostty (`xterm-ghostty`) terminfo db at
  /usr/share/terminfo (+ /etc/terminfo, /lib/terminfo links) with
  TERMINFO_DIRS exported from every env channel. This is also why the
  image carries a /usr/local/bin toolchain and an /etc/profile PATH
  prefix.
- Foreign glibc ELFs run via the nix-ld shim: `/lib64/ld-linux-
  x86-64.so.2` is the shim; it reads `NIX_LD` (the real loader) and
  `NIX_LD_LIBRARY_PATH` (extra store lib dirs) from the env. (The old
  copied-libs + `/etc/ld.so.cache` approach never worked — nixpkgs
  glibc's compiled-in cache path is its own read-only store etc/, so
  the cache was never read.)
- Python manylinux wheel extensions (numpy, pillow, ...) resolve the
  handful of system libs they link (libstdc++/libgcc_s/libz) from
  `/usr/lib/wheel-deps`, which the image puts on `LD_LIBRARY_PATH`
  (scoped to those three libs on purpose — a broader dir would shadow
  nix RUNPATHs process-wide). Binary wheels import as-is; sdists that
  compile still cannot build (no C toolchain).

## Network: full admitted list

Egress is deny-by-default and matches (binary, host) PAIRS — a host
listed here is reachable only by the binaries its policy entry pins
(the `binaries:` lists in `openshell/policies/code-agent.yaml`), e.g.
PyPI is python3/uv/nix-only and curl is refused. Admitted hosts (from
`openshell/policies/code-agent.yaml`):

| Host | Access | Why |
|---|---|---|
| `github.com` | read (GET/HEAD/OPTIONS) + `git-upload-pack` | clone/fetch |
| `github.com` `/**/git-receive-pack` (via github-agent profile) | POST | `git push` |
| `api.github.com` | read; read-write with github-agent provider | gh + github MCP |
| `codeload.github.com`, `raw.githubusercontent.com`, `gist.github.com`, `*.githubusercontent.com` asset hosts | read | tarballs, raw files, release assets (VSCodium fallback download) |
| `update.code.visualstudio.com`, `vscode.download.prss.microsoft.com` | read (curl/wget only) | Microsoft VS Code Remote-SSH server bootstrap (proprietary server downloads on every connect; runs via the nix-ld shim) |
| `*.nixos.org` | read | cache.nixos.org substitution, releases/channels/tarballs |
| `*.cachix.org` | read | cachix binary caches (the repo's openshell/devenv/nix-community/chaotic-nyx are baked substituters) |
| `api.flakehub.io`, `api.flakehub.com` | read | flakehub: inputs (the cache.flakehub.com binary caches were dropped: 401 Unauthorized anonymously — dead substituters) |
| `cache.geninf.io`, `cache.clan.lol` | read | clan niks3 caches |
| `git.clan.lol` | read-write git transport | clan repos |
| `code.m3ta.dev` | read-only git smart-HTTP | the home flake's `agents` input (nix input fetch / clones; no push) |
| `pypi.org`, `files.pythonhosted.org` | read | python3/uv wheel fetches (no uploads); nix also admitted — the home flake's headroom input is a wheel URL, and flake input fetches run as the nix binary |
| `search.nixos.org`, `wiki.nixos.org`, `cache.nixos.org`, `nix-community.github.io`, `nix-darwin.github.io`, `api.flakehub.com`, `nix.dev`, `noogle.dev`, `search.devbox.sh`, `nvf.notashelf.dev`, `api.github.com` | read | mcp-nixos live sources (package/option `info` is a local index) — pinned to the server's python interpreter, see the `mcp_nixos` policy rule |
| `api.kimi.com` | — | kimi-for-coding API |
| `api.anthropic.com`, `platform.claude.com` | — | claude API + startup preflight |

Everything else is DENIED. Do not retry dead hosts in a loop — report
the blocked host. The policy hot-reloads: `openshell policy get/set`
from the HOST (not inside the sandbox) changes network rules without
recreating the sandbox; filesystem/image changes require recreation.

## nix setup

- Flakes on; `sandbox = false` + `filter-syscalls = false` (the
  supervisor's seccomp stack blocks nix's builder-child BPF filter).
- Registry: `nixpkgs` is pinned in-image to
  `github:NixOS/nixpkgs/nixos-unstable` (`/etc/nix/registry.json`) —
  the default indirection via channels.nixos.org is NOT admitted. First
  resolution fetches the nixpkgs tarball (~50MB) from the admitted
  github endpoints into `~/.cache/nix`; later runs reuse the cache. A
  baked-in nixpkgs checkout was dropped deliberately: it was the
  image's heaviest payload, and nix2container copyToRoot rewrites
  dumped the tree at the image root rather than its store path.
- Substituters + trusted keys baked in `/etc/nix/nix.conf` (also
  `$NIX_CONFIG`): the repo's own cachix caches (`openshell` — this
  flake's closure — plus `devenv`, `nix-community`, `chaotic-nyx`,
  mirroring flake.nix's nixConfig minus cache.numtide.com, whose host
  the policy does not admit) and clan niks3 (`cache.geninf.io-1`,
  `cache.clan.lol-1` — objects may be signed under either). The
  FlakeHub binary caches were dropped: they answer nix-cache-info with
  401 Unauthorized anonymously, so they were dead substituters adding
  warning noise to every nix invocation.
- For a Cachix-backed package, name cache + key explicitly:
  `NIX_CONFIG="$NIX_CONFIG extra-substituters = https://<cache>.cachix.org extra-trusted-public-keys = <cache>.cachix.org-1:…" nix profile install …`
- No `/dev/kvm` in the guest: NixOS VM tests and nested VMs cannot
  run — those are CI's job. Plain nix builds run at NATIVE speed (the
  microVM is KVM-backed on the host; the repo's `checks.lint` builds
  in seconds). What bites instead: large source builds eat the 32 GiB
  overlay and FOD fetches are policy-gated — never let an llvm/rustc-
  class source build start; substitute instead.
- Every nix command warning "you don't have Internet access; disabling
  some network-dependent features" is NOT a network problem: nix
  2.34's `haveInternet()` (src/nix/main.cc) is not a connectivity
  probe, it returns true only when `getifaddrs()` shows a
  non-loopback/non-link-local interface address (or a proxy env), and
  the microVM's sinkhole-intercepted networking has neither. nix then
  switches substitution OFF before attempting any fetch, so perfectly
  cache-served paths fall back to (doomed) from-source builds. Actual
  egress to the admitted caches works — `nix store prefetch-file
  https://cache.nixos.org/nix-cache-info` succeeds. Workaround: pass
  the substitute setting as an explicit override — `nix --option
  substitute true build …` (the CLI only zeroes it when NOT
  overridden; `--option`/`NIX_CONFIG` count). Works in-sandbox:
  `nix build --option substitute true .#checks.x86_64-linux.lint -L`.
- Do NOT run the NixOS VM tests (`nix run .#vm-test`) in-sandbox:
  they need /dev/kvm. VM tests are CI's job — the fleet CI is not wired
  up yet, so flag the gap rather than running them. Full `nix flake
  check` is allowed (checks only — VM tests are legacyPackages and
  never part of it) but evaluates every output; prefer the targeted
  lint gate when iterating.

## MCP trio failure modes

- `headroom` — `headroom mcp serve`; wrapper maps the injected
  `$ANTHROPIC_AUTH_TOKEN` onto `ANTHROPIC_API_KEY`. Broken when the
  claude-code provider is missing.
- `nixos` — `mcp-nixos`; package/option `info` answers from a local
  index, `search`-family queries call the `search.nixos.org` backend.
  Policy: the `mcp_nixos` rule admits all of the server's live source
  hosts read-only for its PYTHON INTERPRETER (the mcp-nixos input's
  own `python3.14`), not for `bin/mcp-nixos` — nixpkgs python bin
  entries are bash wrapper scripts and the supervisor matches
  `/proc/pid/exe`, i.e. the interpreter the wrapper execs (the
  pre-2026-10 pin on the wrapper script matched nothing: every search
  call EACCES'd). Broken when the sandbox predates the `mcp_nixos`
  policy rule — hot-reload the policy from the host. Same interpreter
  pin pattern covers `headroom` (the `claude_code` rule pins
  nixpkgs-unstable's `python3.13`, the exe of headroom-slim's bash
  wrapper).
- `github` — `github-mcp-server` wrapper mapping the `$GITHUB_TOKEN`
  handle onto `GITHUB_PERSONAL_ACCESS_TOKEN`. In pi it is `direct` (its
  ~44 tools are listed in the system prompt at session start). Errors at
  startup without the github-agent provider attached (its profile admits
  read-write api.github.com and substitutes the real token at egress for
  the pinned binary) — pi marks the server failed and continues. Recreate
  with `--provider github-agent` to make it functional.
- There is deliberately NO kubernetes MCP server. Use `kubectl`/`helm`
  directly; cluster API egress rides an attached provider or
  port-forward.

## Identity and secrets

- Git identity: `andrewthomaslee-agent` bot; github.com-scoped
  credential helper feeds git the provider-injected `$GITHUB_TOKEN`
  (config from the baked HM profile's programs.git —
  ~/.config/git/config).
- Provider env values are OPAQUE HANDLES, not real secrets —
  `gh auth status` failing is expected; egress substitution is what
  authenticates. Real keys never enter the image.
- Nothing secret is baked in. API keys arrive only via attached
  providers (`kimi-for-coding`, `claude-code`, `github-agent`).

## Recipes

- New package at runtime (NOT pre-baked): `nix profile install nixpkgs#<pkg>`.
- Repo work: clone `github.com/external-systems/home` first — the
  sandbox is clean, not a checkout.
- DENIED spam in `openshell logs`: add a narrow rule via
  `openshell policy set` from the host.
- Sandbox feels stale (missing baked files): the image hash-named
  sandbox lifecycle is `code-sandbox` in the dev shell — re-run it to
  rebuild, reload and recreate.

## Troubleshooting recipes

- An admitted-LOOKING host refusing connections instantly (`Could not
  connect to server`) usually means the (binary, host) PAIR is missing
  from the policy, not a network failure — and the deny log is NOT
  authoritative: observed 2026-10, `nix` → `files.pythonhosted.org`
  refused with zero deny lines in `openshell logs <sb> --source
  sandbox` (the host was admitted only for python3/uv; the home
  flake's headroom input fetch runs as the nix binary — fixed by
  adding `@bin_nix@` to the python_packages entry). Diagnose by
  reading the sandbox's composed policy on the host, not the log.
  Same class, latent at the time: `code.m3ta.dev` (agents input) and
  `api.flakehub.com` (moscripts lock URL — policy had only .io).
  Rare one-off refuses on genuinely admitted pairs (observed once for
  nix→github.com) are proxy-level flakes: retry once or twice — it
  self-recovers within minutes — then report.
- Plain `openshell logs <name>` is flooded by upstream supervisor ssh
  WARNs (`data on unknown channel ChannelId(N)`, steady ~5s cadence)
  — noise; always filter with `--source sandbox | grep -iE
  'denied|reject|block|forbidden'`.
- `error: killing process ...: Operation not permitted` during nix
  builds is the supervisor's seccomp blocking nix→builder signals —
  cosmetic; the build result stands.
- `ls /` fails with EACCES: the sandbox filesystem policy marks /bin
  /usr /lib /lib64 /etc /opt /proc read_only and /sandbox /tmp /nix
  /home read_write — `/` itself is in neither list (deny by default),
  so it cannot be LISTED; every real path below it works normally.
