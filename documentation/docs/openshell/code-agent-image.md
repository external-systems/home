# Code-Agent Image — User Guide

Day-to-day guide for the pre-baked `code-agent` OCI image: what it ships,
how to build/load/refresh it, and how to work in a sandbox. For the
architecture and the lessons that shaped the design, see the
[OpenShell overview](index.md).

## What the image gives you

- **Toolset on PATH** (`/bin`, `/usr/local/bin`, login shells): bash,
  coreutils, git, gh, curl, jq, yq, python3, go, ripgrep, fd, sd,
  openssh, tmux, nix, which, clear — plus the Nix language tooling
  (`nixd`, `alejandra`,
  `statix`, `deadnix`), shell vetting (`shellcheck`, `shfmt`), archive
  tools (`unzip`, `zstd`, `wget`), ELF inspection (`file`, `readelf`,
  `objdump`, `ldd`), patching (`diff`, `patch`), k8s clients
  (`kubectl`, `helm`), and `dig`/`rsync`. Foreign glibc binaries run via
  the nix-ld shim (`/lib64/ld-linux-x86-64.so.2` +
  `NIX_LD`/`NIX_LD_LIBRARY_PATH`). For Python work: `uv`
  (wheel-first installer) plus `python3` — PyPI is admitted read-only
  for both, WHEELS ONLY (`uv pip install --only-binary=:all: …`), since
  no C toolchain ships in the image (pip itself bootstraps inside
  `python3 -m venv`). Binary wheels import as-is: the few system libs
  they link (`libstdc++`/`libgcc_s`/`libz`) resolve from the baked
  `/usr/lib/wheel-deps` dir on `LD_LIBRARY_PATH`.
  Verified in-sandbox (2026-10): `uv venv` + wheel installs (numpy,
  pillow, lxml), `uv init --package` + `uv build`, `uv tool install`,
  `uv python install` (managed CPython via the nix-ld shim), `pip`
  inside `python3 -m venv`, and the docs stack (`mkdocs-material` +
  `mkdocs-glightbox`, `mkdocs build --strict` in `documentation/`).
  Practical notes:
  - `uv tool install`ed binaries land in `$HOME/.local/bin`, which
    login shells put on PATH via `/etc/profile` (re-login or
    `export PATH="$HOME/.local/bin:$PATH"` in non-login shells).
  - `uv venv` does NOT seed pip — use `uv pip …` inside it, or
    `uv venv --seed` when you need real pip.
  - An sdist that compiles still fails without a toolchain, but nix
    supplies one on demand:
    `nix shell --option substitute true nixpkgs#gcc` then re-run the
    uv/pip install inside that shell (verified with psutil).
  - uv's "Failed to hardlink files" warning is benign: it appears
    only when the project lives on `/tmp` (tmpfs) while the uv cache
    is on the overlay — projects under `/sandbox` hardlink fine.
  For Go work: the full `go` toolchain is baked (with `gofmt`) —
  `proxy.golang.org` + `sum.golang.org` are admitted read-only for the
  go binary (and for any `/nix/store/*-go-*/bin/go`, so go-modules
  fixed-output derivations inside nix builds fetch too), and
  GOPATH/GOMODCACHE default to the writable `$HOME/go`. Direct-VCS
  fallback (`GOPRIVATE`/`GOPROXY=direct`) rides git's github.com /
  git.clan.lol admissions.
- **Three pre-wired AI agents** (no interactive login ever), each with
  the sandbox environment briefing baked into its user-level system
  prompt / memory (pi `~/.pi/agent/APPEND_SYSTEM.md`, kimi
  `~/.kimi-code/SYSTEM.md`, claude `~/.claude/CLAUDE.md` — toolset,
  admitted egress, skills location, identity and secrets posture) and a
  shared MCP trio: **headroom** (context compression; wrapper maps the
  injected `$ANTHROPIC_AUTH_TOKEN` onto `ANTHROPIC_API_KEY`), **nixos**
  (option search; `search`-family queries call the `search.nixos.org`
  backend, admitted for the server's binary) and **github** (works only
  with the `github-agent` provider attached — the profile admits
  read-write api.github.com and substitutes the credential at egress;
  the baked wrapper maps the `$GITHUB_TOKEN` handle onto
  `GITHUB_PERSONAL_ACCESS_TOKEN`). The trio is baked at each agent's
  user-level MCP spot: pi `~/.pi/agent/mcp.json`, kimi
  `~/.kimi-code/mcp.json`, claude `~/.claude/settings.json`
  `mcpServers` — in pi all three are `direct`, so the github tools are
  listed in the system prompt at session start (a provider-less github
  server fails loudly at startup and pi marks it failed; the tools are
  still visible):
  - `pi` — Kimi for Coding subscription, key from the attached provider's
    `$KIMI_API_KEY`.
  - `kimi` — same subscription via a baked `~/.kimi-code/config.toml`
    (`type = "kimi"`, `https://api.kimi.com/coding/v1`,
    `apiKeyEnv = "KIMI_API_KEY"`). Do **not** run `/login` — the OAuth
    hosts are unreachable on purpose.
  - `claude` — Claude Teams subscription bearer (`$ANTHROPIC_AUTH_TOKEN`
    from the attached provider); onboarding pre-completed and the
    `platform.claude.com` startup preflight admitted by the policy.
- **Repo skills at `/opt/skills`** — the same merged skill tree
  `inputs.agents.lib.mkSkills` builds for the NixOS hosts (the home
  repo's `skills/` tree + external flake-input skill sources), wired
  into all three CLIs (`~/.pi/agent/settings.json`,
  `~/.kimi-code/skills`, `~/.claude/skills`, `~/.agents/skills`) —
  advertised by name+description, loaded on demand (`/skill:<name>` in
  pi/kimi). Deep-dive repo knowledge (the former `/opt/references`
  bundles) now lives as skills in the same tree.
- **Baked git identity + credentials**: commits are authored as the org
  bot (`andrewthomaslee-agent`), `git init` defaults to a `main`
  branch, and a github.com-scoped credential helper feeds git the
  provider-injected `$GITHUB_TOKEN` — `git push` over https works
  without prompting. Nothing secret is in the image.
- **Deterministic identity + name resolution**: baked
  `/etc/passwd`/`group`/`shadow` (root + uid 1000 agent only),
  `/etc/nsswitch.conf` with `hosts: files dns` (glibc's built-in
  fallback is dns-FIRST, so `/etc/hosts` went unreachable when DNS
  failed; the explicit file makes it authoritative everywhere) and a
  fallback `/etc/hosts` — container runtimes bind-mount their own over
  it, so the baked copy only serves runtimes that don't. Login shells
  also get a sane `umask 022` from `/etc/profile`.
- **nix with flakes**, pre-initialized store db, and baked substituters:
  the repo's cachix caches (openshell, devenv, nix-community,
  chaotic-nyx) + the clan niks3 cache (`cache.geninf.io` /
  `cache.clan.lol`, both keys baked).
  The config lives at `/etc/nix/nix.conf` (not just `$NIX_CONFIG`), so it
  holds in every shell — including VSCodium-server-spawned ones. The
  flake registry is pinned in-image: `nixpkgs` resolves to
  `github:NixOS/nixpkgs/nixos-unstable` (no `channels.nixos.org`
  lookup, which the policy blocks; first resolution fetches the tarball
  once, then it's cached in `~/.cache/nix`), so `nix run nixpkgs#hello`
  fetches binaries from the admitted `cache.nixos.org`. The sandbox
  policy additionally
  admits the clan cache hosts and any `*.cachix.org` cache.
- **VSCodium Remote-SSH server pre-baked** — first connect is instant,
  offline (see the overview for editor setup).

## Build and load

```bash
nix run .#load-code-agent-image    # builds + copies into the host docker store
```

The VM driver resolves the host docker store first; an OCI registry pull
is the fallback. The flake evaluates from the git tree — `git add` new
`.nix` files before building. The image config carries OCI provenance
labels (`org.opencontainers.image.source` / `.revision` — the flake
commit, `dirty` on uncommitted builds), so `docker inspect` answers
"which tree built this" without booting the image.

## Create a sandbox

The dev shell ships a `code-sandbox` script that does all of the below in
one shot: it builds the image, loads it into docker as
`code-agent:<imghash>` (content-hash tag, never mutable `latest`), and
creates a sandbox named `<name>-<imghash>` (default name: `code`) with
the repo policy and the kimi/github providers. If that sandbox already
exists it prompts to delete and recreate (`-y` to skip the prompt) — the
hash suffix means "same name" always implies "older image". It then
appends the generated Remote-SSH config to `~/.ssh/config.local` as a
managed block (replaced, not duplicated, on re-runs; disable with
`--no-ssh-config`, override the path with `--ssh-config-file`).

```bash
code-sandbox              # create/update the default 'code' sandbox
code-sandbox work --cpu 8 --memory 16Gi
code-sandbox -y           # non-interactive recreate if it exists
code-sandbox connect work-<hash>   # attach (Ctrl-P Ctrl-Q detaches)
code-sandbox exec work-<hash> -- nix --version
code-sandbox ssh-config            # sync ssh configs for ALL active sandboxes
code-sandbox delete work-<hash>    # (the ssh config block is left behind; harmless)
```

`ssh-config` rewrites the managed block for every sandbox in
`openshell sandbox list` (same file and replace-not-duplicate semantics
as the create-time append; `--ssh-config-file` applies here too) — run
it after creating sandboxes outside of `code-sandbox`, or after
recreating one by hand.

The equivalent manual steps:

```bash
openshell sandbox create --name code --from code-agent:latest \
  --policy openshell/policies/code-agent.yaml \
  --provider kimi-for-coding --provider claude-code --provider github-agent \
  --cpu 4 --memory 8Gi --detach -- bash -l

openshell sandbox connect code     # attach; Ctrl-P Ctrl-Q detaches
openshell sandbox exec -n code -- nix --version
```

Providers are created once per gateway (see
[the overview](index.md#4-ai-coding-agents-interactive-and-remote) for
the profile import / provider create commands); attach them at create
time or later with `openshell sandbox provider attach code <name> --wait`.

## Working in the sandbox

```bash
pi            # kimi-for-coding, ready to prompt
kimi          # same subscription, ready to prompt (model preselected)
claude        # subscription token via provider; lands on a prompt

nix run nixpkgs#hello                # pinned registry, substitution-only (no /dev/kvm)
nix profile install nixpkgs#hello    # same, persists into the profile
# a Cachix-backed package: name the cache + key for nix
NIX_CONFIG="$NIX_CONFIG extra-substituters = https://nix-community.cachix.org \
  extra-trusted-public-keys = nix-community.cachix.org-1:…" \
  nix profile install nix-community#…

git push                                     # bot identity + token helper baked
openshell logs code --tail --source sandbox  # DENIED lines = policy misses
```

Agent egress is deny-by-default; the policy admits nix caches, the rest
of the nixos.org estate (read-only: releases/channels/tarballs/hydra),
GitHub (read, incl. `raw`/`gist.githubusercontent.com` and the asset
CDNs), `git.clan.lol` (read-write git transport), the kimi/claude API
endpoints, and the VSCodium bootstrap fallback.

## Refreshing the image / sandbox

`code-sandbox` already does this whole flow — re-running it builds the
image, loads it under the new content hash, and (after the replace
prompt) recreates the sandbox. To do it manually:

```bash
# 1. lint gate (CI runs this on push — fail fast locally)
nix fmt . && statix check . && deadnix --fail .
nix flake check --show-trace

# 2. rebuild + load
nix run .#load-code-agent-image

# 3. recreate the sandbox — filesystem-policy and image changes
#    (e.g. /opt, /etc/gitconfig, NIX_CONFIG, /etc/nix) only apply to new
#    sandboxes; network_policies hot-reload, everything else does not.
openshell sandbox delete code
openshell sandbox create --name code --from code-agent:latest \
  --policy openshell/policies/code-agent.yaml \
  --provider kimi-for-coding --provider claude-code --provider github-agent \
  --cpu 4 --memory 8Gi --detach -- bash -l

# 4. smoke-test the fresh sandbox
openshell sandbox exec -n code -- git config user.name    # andrewthomaslee-agent
openshell sandbox exec -n code -- ls /opt/skills ~/.kimi-code ~/.claude/skills
openshell sandbox exec -n code -- nix --version
openshell logs code --tail --source sandbox              # expect no DENIED spam
```

A network-only policy tweak (new host, new rule) can go into a **running**
sandbox without recreation:

```bash
openshell policy get code --base | sed '1,/^---$/d' > /tmp/p.yaml
# edit network_policies in /tmp/p.yaml
openshell policy set code --policy /tmp/p.yaml --wait
```

Provider credential rotations need a sandbox restart (injected values
reach only new processes):

```bash
openshell provider update github-agent --credential GITHUB_TOKEN
openshell sandbox stop code && openshell sandbox start code
```

## Troubleshooting

- **`Unable to connect to Anthropic services`** (claude): the
  `platform.claude.com` preflight is blocked — make sure the sandbox was
  created with the current `openshell/policies/code-agent.yaml` (hot-reload
  the `claude_code` rule if not).
- **kimi shows `Model: not set, run /login or /provider`**: the baked
  `~/.kimi-code/config.toml` is missing → the sandbox is running an old
  image; rebuild + recreate. Never `/login`.
- **`DENIED` lines in the sandbox log**: something is reaching beyond the
  policy — add a narrowly-scoped rule (see
  [the overview's policy section](index.md#3-sandboxes-policies-providers)).
- **`gh auth status` says the token is invalid**: expected — the env value
  is an opaque supervisor handle; real API calls through the proxy work
  (the push test in the git history verifies this).
- **nix substitution falls back to building**: TCG builds crawl (no
  `/dev/kvm` in sandboxes). Check the cache is in `NIX_CONFIG`
  (substituter **and** trusted public key) and admitted by the policy.
