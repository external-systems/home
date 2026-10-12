# MCP Servers

MCP servers are declared by `flake-parts/homeModules/agents.nix` under the
shared namespace `homeSpec.agents.mcp.<name>` and written into **every
enabled agent's** config — opencode (`programs.opencode.settings.mcp.servers`,
native V2 `{type = local; command = [...];}` shape), pi
(`~/.pi/agent/mcp.json`), kimi-code (`~/.kimi-code/mcp.json`) and claude-code
(see the note below). No docker, no `npx`/`uvx` runtime downloads: local
servers are hermetic nix packages, remote servers are hosted.

!!! note "claude-code MCP delivery"
    Current claude-code **ignores** `mcpServers` in `~/.claude/settings.json`
    (verified with `claude mcp list`, 2026-10) — it only reads user-scope MCP
    servers from `~/.claude.json`'s top-level `mcpServers`. Since that file is
    claude's mutable state, home-manager does not own it; instead a
    `home.activation.claudeMcpServers` step deep-merges the shared set into
    `~/.claude.json` at every switch (skipped when `claude.writeClaudeJson`
    bakes the file — the sandbox image path).

## All servers

| Option | Default | Kind | Description |
|---|---|---|---|
| `mcp.nixos.enable` | `true` | local | mcp-nixos flake package: NixOS / Home Manager / nix-darwin package & option search |
| `mcp.github.enable` | `true` | local *or* remote | GitHub's official MCP server (`github-mcp-server` from nixpkgs-unstable). Auth method selected by `mcp.github.auth` — see [below](#github-mcp-server) |
| `mcp.headroom.enable` | `true` | local | headroom MCP server (compress/retrieve/stats). No-op unless `homeSpec.programs.headroom.enable` — see [Headroom](headroom.md) |
| `mcp.artifacthub.enable` | `false` | local | ArtifactHub MCP server — Helm-chart tools against artifacthub.io: chart info, default `values.yaml` (with fuzzy search), templates (with fuzzy search). Built hermetically from the `v1.1.1` source pin (`flake-parts/packages/artifacthub-mcp.nix`), so no docker/`npx` runtime downloads; no secrets — it queries the public artifacthub.io API |
| `mcp.kubernetes.enable` | `false` | local | Kubernetes MCP server (`containers/kubernetes-mcp-server`, hermetic `buildGoModule` in `flake-parts/packages/kubernetes-mcp-server.nix`) against the user's kubeconfig; stdio is the default transport. **Off by default**: the server exits at startup without a kubeconfig (`~/.kube/config` or `KUBECONFIG`), so enable it per profile/machine once cluster credentials exist. `mcp.kubernetes.readOnly` (default `false`) adds `--read-only` (only `readOnlyHint` tools exposed) |
| `mcp.varlock-docs.enable` | `false` | remote | Varlock docs MCP server (`https://docs.mcp.varlock.dev/mcp`) — searches the varlock.dev documentation; public, no auth. **opencode-only** (the file-configured agents get only local servers) |
| `mcp.extraServers` | `{}` | local | Extra stdio servers merged verbatim into the shared set (used by the OpenShell code-agent image); per-server `description`/`exposure` fields are pi-only |

The opt-in servers (`artifacthub`, `kubernetes`, `varlock-docs`) are off
by default; enable them per profile or machine, e.g. the netsa profile or
a machine that has cluster credentials.

## GitHub MCP server

`mcp.github` is **on by default** (`mcp.github.enable`, default `true`).
Two pieces, per agent:

- **pi / kimi / claude always get the local stdio server** via the
  `github-mcp-server-opencode` wrapper — they cannot run a browser OAuth
  flow from a file config.
- **opencode** selects by `mcp.github.auth`:

| `mcp.github.auth` | opencode entry | Secret |
|---|---|---|
| `"oauth"` (**default**) | `type = "remote"`, `url = "https://api.githubcopilot.com/mcp/"` — GitHub's hosted server; opencode runs the browser OAuth flow automatically on first tool use | none (for opencode — the other agents still need the PAT) |
| `"pat"` | `type = "local"`, command = the `github-mcp-server-opencode` wrapper (`github-mcp-server stdio`) | PAT file at `mcp.github.patFile` (default: the clan var path below) |

Exclusivity is enforced by the `mcp.github.auth` enum (one method at a
time) plus an eval-time home-manager assertion: `"oauth"` requires
`mcp.github.patFile` to be `null`.

The wrapper reads the PAT file (explicit `mcp.github.patFile` override,
else the canonical `/run/secrets/vars/shared/github-mcp/pat`) and
exports `GITHUB_PERSONAL_ACCESS_TOKEN` before exec'ing the server. The
upstream server exits immediately when that env var is unset, so a
readable PAT file is a hard requirement.

### Clan vars provisioning (`flake-parts/nixosModules/github-mcp.nix`)

All github options live under `homeSpec.agents.mcp.github` — there is no
separate NixOS option tree. The option-less NixOS module
`nixosModules.github-mcp` scans every home-manager user's agents config
and, for each user with `mcp.github.enable` **and any PAT consumer**
(pi/kimi/claude enabled, or opencode with `auth = "pat"`), declares the
shared clan vars generator:

```nix
clan.core.vars.generators."github-mcp" = {
  share = true;              # one PAT for the whole fleet
  prompts.pat.persist = true;
  prompts.pat.type = "hidden";
  files.pat = {
    owner = <user>;          # readable by the agent user
    mode = "0400";
    neededFor = "services";  # deployed via sops-nix at boot
  };
};
```

Provisioning (interactive, **no fake values in the repo**):

```bash
clan vars set github-mcp pat <machine>   # or: clan vars generate
```

sops-nix then deploys the secret to
`/run/secrets/vars/shared/github-mcp/pat` (owner = user, mode `0400`)
and the wrapper picks it up on every MCP server start.

!!! warning "The scan mirrors option paths by hand"
    `nixosModules/github-mcp` re-reads the `homeSpec.agents.*` paths from
    the NixOS side (defensive `or` access, no fixpoint recursion). If the
    options are renamed or restructured, update BOTH places — a stale scan
    silently stops declaring the generator and pi/kimi/claude's github MCP
    fails at startup with "authentication required".
