# OpenCode Harness

[OpenCode](https://opencode.ai) is the primary AI agent harness used
across the machines in this flake, alongside **pi**, **kimi-code** and
**claude-code**. All four are managed **declaratively** by one
home-manager module, `flake-parts/homeModules/agents.nix`, under the
`homeSpec.agents` namespace: enabling an agent installs it and wires the
shared repo skill set into its config, and opencode additionally gets a
fully declarative `~/.config/opencode/opencode.json` (a symlink into the
read-only Nix store — no imperative config mutation).

A companion module, `flake-parts/homeModules/headroom.nix`, adds the
[Headroom](headroom.md) context-compression proxy and its integration.

## Module options (`homeSpec.agents`)

### Shared skills

| Option | Default | Description |
|---|---|---|
| `skills.enabled` | `true` when any agent is enabled | Build the shared skills tree (repo `skills/` + external flake-input sources via `inputs.agents.lib.mkSkills`) and wire it into every enabled agent's skills dir |
| `skills.extraSources` | `[]` | Per-machine external skill sources appended to `mkSkills`' `externalSkills` (`{src = …;}`, optionally `skillsDir` / `selectSkills`) |

See [Skills](skills.md) for the skill tree, composition and precedence.

### Agents

| Option | Default | Description |
|---|---|---|
| `opencode.enabled` | `false` | opencode v2 + the declarative configuration below; skills at `~/.config/opencode/skills` |
| `pi.enabled` | `false` | pi coding agent (`pkgs.pi-coding-agent`); skills at `~/.agents/skills` |
| `kimi.enabled` | `false` | Kimi Code CLI (`pkgs.kimi-code`); skills at `~/.kimi-code/skills` |
| `claude.enabled` | `false` | Claude Code CLI (`pkgs.claude-code`); skills at `~/.claude/skills` |
| `pi.package` / `kimi.package` / `claude.package` | `pkgs.pi-coding-agent` / `pkgs.kimi-code` / `pkgs.claude-code` | Overridable package pins (kimi/pi/claude come from the `llm-agents` flake input via the overlay) |

The pi/kimi/claude CLIs are otherwise self-contained (interactive
login, state under the user's home); opencode carries the repo's
declarative configuration.

### opencode configuration (`homeSpec.agents.opencode`)

| Option | Default | Description |
|---|---|---|
| `machineContext.enable` | `true` | Generate `~/.config/opencode/AGENTS.md` — the global per-machine system-prompt file (see below) |
| `machineContext.repoPath` | `home` | Directory name of the local flake checkout relative to the user's home directory, written into the generated file |
| `machineContext.repoOwner` | `andrewthomaslee` | Owner of the remote flake repo, written into the generated file's `Repo:` line |
| `machineContext.repoName` | `home` | Name of the remote flake repo, written into the generated file's `Repo:` line |
| `machineContext.environment` | `null` | Host-environment annotation written after the `Machine:` line (e.g. `vm (KubeVirt guest)`). NixOS has no eval-time VM marker, so VM images set this explicitly; NixOS containers are auto-detected (`boot.isContainer`); bare metal stays unset (no line) |
| `machineContext.facterReport` | `null` | Synthetic nixos-facter report overriding the `machines/<hostname>/facter.json` read (VM tests). Null reads the real file |
| `machineContext.extraText` | `null` | Optional per-machine notes appended to the generated file (set from `machines/<hostname>/configuration.nix`) |
| `mcp.<name>.enable` | see [MCP Servers](mcp-servers.md) | Shared MCP servers under `homeSpec.agents.mcp.<name>`, written into every enabled agent's config (opencode `mcp.servers.*`, pi/kimi `mcp.json`, claude `~/.claude.json` via activation merge) |

## What the module configures (opencode)

- **Model** — `glm-5.3-flash` for the main model and the built-in title
  agent; checkpoint-based auto compaction (`compaction.auto`).
- **Ordered `permissions` array** (native V2 shape, last match wins):
  `read` + `external_directory` for `/nix/store/**` and `/tmp/**`,
  `read` for `/home/netsa/.config/opencode/` and `/etc/hostname`.
- **MCP servers** — the shared `homeSpec.agents.mcp.<name>` set, rendered
  into opencode's native V2 `mcp.servers.*`. See [MCP Servers](mcp-servers.md).
- **Headroom integration** — when
  `homeSpec.programs.headroom.enable` is on, the headroom MCP server joins
  the shared set and every agent's provider traffic is routed through the
  local compression proxy (opencode: `providers.anthropic.settings.baseURL`).
  See [Headroom](headroom.md).
- **Skills** — the shared skills tree symlinked at
  `~/.config/opencode/skills`. See [Skills](skills.md).
- **Machine context** — a compact, matter-of-fact machine descriptor
  (no markdown decoration, token-lean) loaded into the system prompt of
  every opencode session on the machine. One shared home module renders
  it per machine and writes it to the **global AGENTS.md discovery
  spot**, `~/.config/opencode/AGENTS.md`: the hostname comes from
  `osConfig` (home-manager runs as a NixOS module) and the machine's
  `machines/<hostname>/facter.json` is read at eval time to bake
  hardware facts (CPU/GPU/RAM/disk, best-effort — missing fields are
  skipped; VM tests can inject a synthetic report via
  `machineContext.facterReport`). The generated file contains one
  identity line (`Machine: <host> (NixOS <platform>)`), an optional
  `Environment:` line (VMs set `machineContext.environment` explicitly —
  NixOS has no eval-time VM marker; NixOS containers are detected via
  `boot.isContainer`), a `Hardware:` list, a one-line repo reference
  (`Repo: github.com/<repoOwner>/<repoName> (local: <checkout>)`), a
  one-line `Machine facts:` path list (`facter.json`, `disko.nix`,
  `configuration.nix` under `machines/<hostname>/`), a read-only rule
  (machine config may only be changed by the repo owner, or by an agent
  instructed to while working in the home repo) and one generic rule:
  read a repo's AGENTS.md before working in it. It is wired as the
  **global** AGENTS.md, so it applies to sessions in any project (a
  project's own AGENTS.md still auto-loads on top when working in that
  project). Consumers without a facter report (the installer ISO) get
  the identity/environment/repo/rules lines only. It deliberately does
  **not** use `settings.instructions`: opencode v2 decodes that array
  but never resolves its entries (see
  `services/www/src/docs/content/instructions.mdx` at the pinned
  opencode rev), while the global `~/.config/opencode/AGENTS.md` is
  v2's supported global instruction source. The repo's skills (incl.
  `nix-style`, the user's Nix-writing preferences) are advertised by
  opencode itself from the skills dir.
- **Wrapper scripts** — `github-mcp-server-opencode` (exports the GitHub
  PAT, see [MCP Servers](mcp-servers.md#github-mcp-server)).

## Packages

`nix build .#<package>` outputs relevant to the harness:

| Package | Purpose |
|---|---|
| `headroom` / `headroom-slim` | context-compression proxy (see [Headroom](headroom.md)) |
| `artifacthub-mcp` | ArtifactHub MCP binary (`flake-parts/packages/artifacthub-mcp.nix`) |
| `kubernetes-mcp-server` | containers/kubernetes-mcp-server, hermetic `buildGoModule` (`flake-parts/packages/kubernetes-mcp-server.nix`) |

The agent CLIs themselves (`opencode`, `pi`, `kimi`, `claude`) are
nixpkgs / `llm-agents`-pinned and routed through the repo overlay —
they are installed via the home module, not as standalone packages.

## Profiles

- **Dev profile** (`flake-parts/homeModules/profiles/netsa.nix`,
  `flake.homeModules.profile-netsa`) — applied to `netsa` on the
  netsa-tagged dev machines (nixos, kamrui-h1, ghost) through the users
  clan service in `inventory.nix`. Enables the shared skills plus all
  four agents (`homeSpec.agents.skills/opencode/pi/kimi/claude`), enables
  the headroom proxy (`homeSpec.programs.headroom`) with provider reroute
  for all four agents, uses the github MCP in PAT mode
  (`mcp.github.auth = "pat"` — the per-user clan var `github-netsa`
  provisions the PAT to `/run/secrets/vars/shared/github-netsa/pat`), and
  turns on declarative github.com git/gh auth
  (`homeSpec.programs.git.githubAuth.enabled`) on the same token.
- **root profile** (`profiles/root.nix`) — shell/ssh/starship/k9s only,
  no agents.
- **wife profile** (`profiles/wife.nix`) — plasma-manager/firefox/media
  only, no agents.
- **matt profile** (`profiles/matt.nix`) — netsa-lite: desktop basics,
  claude only (github MCP off), whisper-dictation, docker; git auth off
  until Matt has a GitHub PAT to provision.
- The netsa tag itself (`clanServices/tags/`) carries only machine-level
  `hostSpec` options; all agent opt-ins live in the home profiles.

## Files

| File | Purpose |
|---|---|
| `flake-parts/homeModules/agents.nix` | everything agent-related: `homeSpec.agents.{skills,opencode,pi,kimi,claude}` — per-agent enable + package, shared `skillsDir` via `inputs.agents.lib.mkSkills`, shared MCP set under `homeSpec.agents.mcp.<name>` (opencode native V2 `mcp.servers.*`, pi/kimi `mcp.json`, claude activation-merge into `~/.claude.json`), headroom provider reroute per agent, ordered `permissions` array, model/title/compaction settings, machine context (`machineContext.*`), PAT wrapper |
| `flake-parts/homeModules/headroom.nix` | headroom options + `headroom-proxy.service` user unit — see [Headroom](headroom.md) |
| `flake-parts/homeModules/profiles/netsa.nix` | dev profile: enables skills + all four agents |
| `flake-parts/homeModules/profiles/root.nix`, `profiles/wife.nix` | minimal profiles without agents |
| `flake-parts/nixosModules/git.nix` | per-user `github-<user>` clan vars PAT generator — one token for git/gh + the MCP wrapper (see [MCP Servers](mcp-servers.md#github-mcp-server)) |
| `flake-parts/packages/artifacthub-mcp.nix` | artifacthub-mcp package |
| `flake-parts/packages/kubernetes-mcp-server.nix` | kubernetes-mcp-server package |
| `overlays/default.nix` | repo overlay: `pkgs.unstable` + the `llm-agents` agent CLIs (`kimi-code`, `pi-coding-agent`, `claude-code`) and service packages |
| `clanServices/tags/` | machine-level `hostSpec` tag modules (amd/intel/lan/wan/virt/dev) |
