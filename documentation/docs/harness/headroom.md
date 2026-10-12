# Headroom — Context Optimization

[Headroom](https://www.headroomlabs.ai/) is the context optimization layer
of the [OpenCode harness](index.md): a local compression proxy between the
agent and the upstream LLM providers (DeepSeek, Anthropic, OpenAI, ...).
This flake packages it, integrates it with OpenCode declaratively, and
exposes it as a standalone proxy service.

## What Headroom does

```
┌─────────────────────────────┐
│ OpenCode                    │
│  tools + headroom MCP       │
└──────────────┬──────────────┘
               │ HTTP
               ▼
┌─────────────────────────────┐
│ headroom proxy (:8787)      │
│  compression pipeline:      │
│  SmartCrusher, Kompress ML, │
│  code-aware (tree-sitter),  │
│  log/tabular compactors     │
│  CCR store (retrieve)       │
└──────────────┬──────────────┘
               ▼
   Upstream LLM providers
```

- **Optimization proxy** — local FastAPI server (`headroom proxy`), default
  `127.0.0.1:8787`. `cache` mode freezes prior turns to maximize provider
  prefix-cache hits; `token` mode aggressively rewrites prior turns.
- **Compression engines** compress large tool outputs (bash logs, diffs,
  file reads, tables) before they reach the model.
- **CCR (Compress-Cache-Retrieve)** — compressed content is replaced by
  markers (`<<ccr:<hash>>>`); the agent can call `headroom_retrieve(hash)`
  to fetch the verbatim original on demand.
- **MCP server** (`headroom mcp serve`) — stdio MCP server exposing
  `headroom_compress`, `headroom_retrieve`, and `headroom_stats`.
- **OpenCode transport plugin** — bundled JS plugin (`entry.opencode.js`),
  upstream's V1-era integration: it rerouted *all* provider traffic through
  the proxy and registered `headroom_retrieve` as a native tool. **Not
  wired here**: OpenCode v2 only loads V2 plugins (`{ id, setup }` default
  exports) and this entry is a V1 hook function; headroom is integrated
  via the declarative config below instead.

## Why `headroom wrap opencode` is not used

Upstream `headroom wrap opencode` mutates `~/.config/opencode/opencode.json`
in place. Under Home-Manager that file is a symlink into the read-only Nix
store, so wrap fails with `Read-only file system`. The declarative
equivalent is implemented directly in the home-manager modules instead.

## OpenShell code-agent sandbox

The code-agent OCI image wires headroom differently from the NixOS
hosts (no systemd, no HM session variables — the supervisor scrubs the
process env):

- **One baked proxy instance per sandbox serves EVERY agent** — a
  proxy process carries one upstream per WIRE PIPELINE, and the two
  pipelines this fleet needs are disjoint: Anthropic `/v1/messages` →
  api.anthropic.com (claude-code, pi's anthropic provider), OpenAI
  `/v1/chat/completions` → api.kimi.com/coding/v1 (kimi-code's native
  `type = "kimi"` wire). pi's Anthropic-wired kimi-coding provider
  rides the Anthropic pipeline with a per-request
  `x-headroom-base-url: https://api.kimi.com/coding` override
  (SSRF-guarded; the proxy runs with `HEADROOM_ALLOWED_BASE_URLS`
  naming exactly that URL because the gateway's interception DNS
  resolves admitted hosts to fake 198.18.0.0/15 IPs the guard would
  otherwise reject). `code-sandbox --inference <menu|all>`
  (default `all`) only selects which inference credential providers
  attach —
  kimi-for-coding, claude-subscription, claude-code, openrouter — with
  `all` auto-attaching every menu provider PRESENT on the gateway except
  claude-code (it would shadow claude-subscription). The OCI image never
  changes per provider set.
- **Lazy start** — each agent's `/usr/local/bin` launcher wrapper runs
  `headroom-proxy-ensure <port>` (flock-serialized,
  `--stateless`, `--disable-kompress` — the image ships headroom-slim
  without the [ml] extra and huggingface.co is not policy-admitted, so
  the optional ML compressor could never load; the structural
  compressors carry the savings — `HEADROOM_BEACON=off`), refuses to
  run against a STALE proxy from an older image generation (whose
  Anthropic pipeline was bound to the kimi upstream), and `exec`s the
  real CLI.
- **Routing via config files** — claude `settings.json`
  `env.ANTHROPIC_BASE_URL`, pi `models.json` `baseUrl` +
  `headers."x-headroom-base-url"`, kimi `config.toml` `type = "kimi"`
  + `base_url` (with the `/v1` suffix) — all rendered by the
  image's home-manager evaluation (`homeSpec.agents.*`, see
  `flake-parts/ociImages/code-agent.nix`).
- **Policy**: api.anthropic.com and api.kimi.com are admitted for
  headroom-slim's python interpreter (`@bin_headroom_py@` in the
  `claude_code` and `kimi_for_coding` rules); gateway credential
  substitution works for proxy-routed traffic.
- The **MCP server** (`headroom mcp serve`) is one of the baked MCP
  trio and shares the proxy's CCR store, so `headroom_retrieve`
  resolves proxy-placed `<<ccr:…>>` markers. With the default
  claude-subscription provider (no platform key) the MCP server's
  LLM transforms are unavailable — headroom falls back to its local
  structural compressors, which carry the bulk of the savings.

## Package

`flake-parts/packages/headroom.nix` builds `headroom-ai` **v0.37.0** from
the prebuilt manylinux wheel pinned as the `headroom` flake input (abi3,
CPython 3.10–3.13), patched with `autoPatchelfHook` and propagated with the
`[all]` runtime dependency set from `nixpkgs#python313Packages` (including
`h2`, required for the proxy's HTTP/2 upstream client). It is exposed as:

- top-level output: `nix build .#headroom`
- overlay: `pkgs.headroom`

A full variant `packages.headroom` (adds torch/sentence-transformers/OCR
for the ML compressors and memory features) is built from the same
wheel; the home-manager module installs `headroom-slim` by default and
can be pointed at the full package via `homeSpec.programs.headroom.package`.

## Home-manager module

`flake-parts/homeModules/headroom.nix` — options under
`homeSpec.programs.headroom`:

| Option | Default | Description |
|---|---|---|
| `enable` | `false` | Install headroom and enable the integration |
| `package` | `pkgs.headroom-slim` | Headroom package to install |
| `proxy.enable` | `true` | Run `headroom proxy` as a systemd **user** service |
| `proxy.port` | `8787` | Proxy listen port |
| `proxy.host` | `127.0.0.1` | Proxy bind host |
| `proxy.mode` | `cache` | `cache` (prefix-cache friendly) or `token` (max compression) |
| `proxy.memory` | `false` | Persistent cross-session memory (off by default: proxy-injected memory tools have no executor in opencode; also pulls embedding models at startup) |
| `proxy.learn` | `false` | Live traffic learning |
| `proxy.extraArgs` | `[]` | Extra CLI args for `headroom proxy` |

The service (`headroom-proxy.service`) is `Restart=always` and
`WantedBy=default.target`.

!!! note "First boot with memory/learn"
    `--memory`/`--learn` pull embedding models from Hugging Face on first
    startup; with an empty `HOME` cache this can stall the service for a
    long while. Leave both off for a fast first boot.

## OpenCode integration

`flake-parts/homeModules/agents.nix` declaratively merges the following
into `programs.opencode.settings` when headroom is enabled (no
`headroom wrap opencode` needed — wrap is unusable on a read-only
home-manager config):

- **MCP server** — `mcp.servers.headroom = { type = "local"; command = ["headroom" "mcp" "serve"]; }`
  (native V2 shape: servers live under `mcp.servers`, there is no
  `enabled` toggle — present means enabled)
- **Provider baseURL overrides** — `providers.deepseek/anthropic/openai.settings.baseURL`
  point at `http://127.0.0.1:8787/v1` (native V2 provider shape; the
  compression path — *every* request through those providers is routed
  through the proxy).

Providers NOT overridden (intentionally):

- **openrouter / google gemini** — native OpenCode providers resolved from
  models.dev. Keep their real upstream baseURLs; the proxy's OpenAI handler
  honors its routing headers and its Gemini handler serves
  `/v1beta/models/...` natively. Config-level entries for them are
  unnecessary (and would break upstream selection).
- **Auth** — use `/connect` in the TUI (writes
  `~/.local/share/opencode/auth.json`) or provider env vars
  (`OPENROUTER_API_KEY`, `GEMINI_API_KEY`). Never in the read-only store.
