# Parameterized generator for the code-sandbox lifecycle script (shell
# text, no shebang — callers wrap it in writeShellScriptBin or a devenv
# `scripts.<name>.exec`, each of which supplies its own header).
#
# One script, three instantiations (all from this single source):
#   - devenv/default.nix: scripts.code-sandbox (flakeRef "." = the
#     enclosing checkout; devenv may not reference flake values, so the
#     generator is imported by plain relative path);
#   - packages.code-sandbox (flake-parts/openshellConfig.nix): baked with
#     THIS repo's source store path, so hosts can install it on PATH
#     (pkgs.code-sandbox via overlays/default.nix) and run it from ANY
#     directory — no checkout required;
#   - flakeModules/code-sandbox.nix: the exported flake-parts module for
#     other flakes (devenv projects pulling this flake included) — they
#     set perSystem.codeSandbox.* options and get packages/apps.
{
  # Flake whose #<attrs> provide image/policy/profile/loader. "." means
  # "the flake enclosing the cwd" (resolved via the git root so
  # subdirectories work).
  flakeRef ? ".",
  # Canonical PUBLIC flake ref (e.g. "github:owner/repo") used to build
  # the image when the local tree cannot pin a real commit: a dirty or
  # non-git source path bakes "Image: code-agent @ dirty" into every
  # agent briefing, which is useless. With a remoteFlake baked in, the
  # image then builds from "<remoteFlake>/<remote HEAD>" instead, so the
  # briefing always pins a real commit. null disables the fallback
  # (generic consumers get a warning instead).
  remoteFlake ? null,
  # When true (and remoteFlake is set), the bare command ALWAYS builds
  # from <remoteFlake>/<remote HEAD> — the installed wrapper tracks the
  # live repo head, never a stale store path or a dirty checkout.
  # "--flake ." still forces a local build. false keeps local-first
  # resolution (clean checkout at remote HEAD builds locally) — right
  # for the in-repo devenv script.
  alwaysRemote ? false,
  # Attr names inside that flake.
  imageAttr ? "code-agent-image",
  loaderApp ? "load-code-agent-image",
  policyAttr ? "code-agent-policy",
  profileAttr ? "github-agent-profile",
  # Attr name of the create-time sandbox env file (KEY=VALUE lines,
  # passed as `openshell sandbox create --env` flags at create). The
  # supervisor spawns every sandbox process with a scrubbed env, and
  # spec env is the ONLY channel that survives on every spawn path —
  # shells otherwise recover the env from the in-image /etc/profile +
  # ~/.bashrc. A missing attr warns and continues without it (generic
  # consumers may not define one). null disables.
  envAttr ? "code-agent-env",
  # Gateway-side provider profile id (sync/doctor drift-check this one).
  profileId ? "github-agent",
  # BASE providers attached to every sandbox; checked by sync/doctor.
  # The credential provider for the sandbox's coding agent is added on
  # top, derived from --agent: pi/kimi → kimi-for-coding, claude →
  # claude-subscription (Pro/Max/Team OAuth token from
  # `claude setup-token`, injected as $CLAUDE_CODE_OAUTH_TOKEN) — the
  # owner's working credential. Platform-key users pass
  # `--agent claude --provider github-agent --provider claude-code`
  # instead (--provider replaces the whole list). NEVER attach both
  # claude providers: Claude Code's precedence ranks
  # $ANTHROPIC_AUTH_TOKEN above $CLAUDE_CODE_OAUTH_TOKEN, so a $0-credit
  # platform key would shadow the subscription. Note the baked headroom
  # MCP server's LLM transforms need a PLATFORM key (a subscription
  # token only bills correctly on Claude-Code-shaped requests) — with
  # the subscription provider they degrade to local structural
  # compression; the headroom proxy's compressors are all local and
  # unaffected either way.
  providers ? ["github-agent"],
  # Coding agent each created sandbox is dedicated to (--agent
  # overrides): stamped into the sandbox as CODE_AGENT via the
  # create-time --env channel (the only env channel that survives the
  # supervisor's scrub on every spawn path), selecting both the
  # headroom proxy's upstream (pi/kimi → api.kimi.com/coding, claude →
  # api.anthropic.com) and the auto-attached credential provider. The
  # image's launcher wrappers refuse to run an agent from the wrong
  # routing family.
  defaultAgent ? "kimi",
  # OCI image name for the content-hash tag.
  imageName ? "code-agent",
  # Sandbox name prefix.
  defaultName ? "code",
  # Default for the --include-workdir toggle. NOTE: upstream
  # `include_workdir` is a POLICY BIT ONLY — it adds the sandbox's own
  # internal workdir (/sandbox, the VM's ephemeral overlay) to the
  # filesystem policy's read_write set; it never mounts host files (the
  # VM driver has no host-share mechanism at all). This repo's policy
  # already lists /sandbox in read_write, so the toggle is a no-op kept
  # for CLI compatibility — file transfer rides the CLI's native
  # `openshell sandbox upload`/`download`.
  includeWorkdir ? false,
  cpu ? "4",
  memory ? "8Gi",
}: let
  providersStr = builtins.concatStringsSep " " providers;
  remoteFlakeStr =
    if remoteFlake == null
    then ""
    else remoteFlake;
  envAttrStr =
    if envAttr == null
    then ""
    else envAttr;
in ''
  set -euo pipefail

  usage() {
    cat >&2 <<'USAGE'
  usage: code-sandbox [create] [name] [options]   build + load image, sync configs, create sandbox
         code-sandbox delete <name>               delete a sandbox
         code-sandbox connect <name>              attach to a sandbox (Ctrl-P Ctrl-Q detaches)
         code-sandbox exec <name> -- <cmd...>     run a command in a sandbox
         code-sandbox ssh-config                  append ssh configs for ALL active sandboxes
         code-sandbox sync                        render policy + profile from the flake, push on drift
         code-sandbox doctor                      drift/health report + per-sandbox egress smoke (exit 1 on findings)

  options:
    -y, --yes          don't prompt when the sandbox already exists (delete + recreate)
        --agent A      dedicate the sandbox to one coding agent: pi, kimi or claude
                       (default: ${defaultAgent}). Stamps CODE_AGENT into the sandbox's
                       create-time env, selects the headroom proxy's upstream
                       (pi/kimi → api.kimi.com/coding, claude → api.anthropic.com),
                       and attaches the matching credential provider on top of the
                       base providers (${providersStr}): kimi-for-coding for pi/kimi,
                       claude-subscription for claude
        --cpu N        CPUs for the sandbox (default: ${cpu})
        --memory SIZE  memory for the sandbox (default: ${memory})
                       both are accepted but IGNORED by the VM driver — sizing
                       there is driver-wide gateway config, not per-sandbox
        --flake REF    build image/policy/profile from flake REF — ${
    if alwaysRemote
    then "default is ${remoteFlakeStr}@<remote HEAD> (the live repo head), so this runs from ANY directory"
    else "default is the flake baked in at install time, so this runs from ANY directory"
  }; "." = the flake enclosing the cwd (for working
                       on that flake itself)
        --provider N   attach provider N INSTEAD of the defaults (repeatable;
                       e.g. claude platform-key users: --agent claude
                       --provider github-agent --provider claude-code)
        --no-sync      create only: skip the profile sync (default: sync before create)
      --include-workdir / --no-include-workdir
                     toggle the policy's include_workdir BIT at create (default off).
                     Policy bit only: it adds the sandbox's INTERNAL /sandbox to
                     read_write (this policy already lists it) — no host files are
                     ever mounted into a sandbox (the VM driver has no host-share
                     mechanism; use `openshell sandbox upload/download`).
    -h, --help         this help
        --no-ssh-config           don't append the Remote-SSH config (default: append)
        --ssh-config-file FILE    where to append it (default: ~/.ssh/config.local)

  Naming: sandboxes are <name>-<imghash> (default name: ${defaultName}-<agent>) and
  images ${imageName}:<imghash> — both content-addressed, so an existing name
  means an older image. Recreate for image changes; network policy hot-reloads
  via `code-sandbox sync`. The image bakes its flake git rev into every agent
  briefing; --flake picks the build source (default: ${
    if alwaysRemote
    then "${remoteFlakeStr}@<remote HEAD> (the live repo head)"
    else "a clean checkout at the remote HEAD, else ${remoteFlakeStr}@<remote HEAD>"
  }).

  Full design docs (rev pinning, policy/profile drift lifecycle, sandbox env):
  documentation/docs/openshell/code-sandbox.md.
  USAGE
    exit "''${1:-0}"
  }

  # Append (or replace) the generated Remote-SSH config for one sandbox
  # as a managed, comment-delimited block — idempotent across re-runs.
  append_ssh_config() {
    mkdir -p "$(dirname "$ssh_config_file")"
    tmp="$ssh_config_file.code-sandbox.tmp"
    if [ -f "$ssh_config_file" ]; then
      sed "/^# code-sandbox: $1\$/,/^# end code-sandbox: $1\$/d" \
        "$ssh_config_file" >"$tmp"
    else
      : >"$tmp"
    fi
    {
      echo "# code-sandbox: $1"
      openshell sandbox ssh-config "$1"
      echo "# end code-sandbox: $1"
    } >>"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$ssh_config_file"
    echo "code-sandbox: ssh config for '$1' appended to $ssh_config_file"
  }

  # Active sandbox names, one per line (first column of `openshell
  # sandbox list`; header/separator dropped). Redirect, never pipe the
  # CLI — it panics (exit 101) on EPIPE.
  list_sandbox_names() {
    sandbox_list="$(mktemp)"
    openshell sandbox list >"$sandbox_list" 2>/dev/null || true
    awk 'NF && $1 !~ /^[Nn][Aa][Mm][Ee]|^-+$/ {print $1}' "$sandbox_list"
    rm -f "$sandbox_list"
  }

  # "." means "the flake enclosing the cwd" — resolve via the git root
  # (fall back to cwd) so running from a subdirectory works.
  resolve_flake_ref() {
    if [ "$flake_ref" = "." ]; then
      git rev-parse --show-toplevel 2>/dev/null || pwd
    else
      printf '%s' "$flake_ref"
    fi
  }

  # Image source resolution (rev pinning): the image bakes "Image:
  # ${imageName} @ <rev>" — from the flake's git revision — into every
  # agent briefing, and a dirty or git-less source pins "dirty", which
  # is useless. Resolve the build source:
  #   --flake REF (explicit)   -> REF verbatim (caller's choice; a dirty
  #                                local ref pins "dirty")
  #   alwaysRemote             -> <remoteFlake>/<remote HEAD>, ALWAYS:
  #                                the bare command tracks the live repo
  #                                head, never a stale store path or a
  #                                dirty checkout ("--flake ." forces
  #                                local)
  #   otherwise (local-first)  -> clean local checkout whose HEAD equals
  #                                origin HEAD builds locally; a dirty/
  #                                behind tree builds <remoteFlake>/<HEAD>
  #                                when remoteFlake is set, else warns and
  #                                builds local
  remote_git_url() {
    # Map a flake ref to a git URL for ls-remote. Handles the refs this
    # generator is instantiated with (github:owner/repo[/ref]); anything
    # else is used verbatim (git+https://..., https://..., file paths).
    ref="${remoteFlakeStr}"
    case "$ref" in
      github:*)
        owner_repo="''${ref#github:}"
        # Strip an optional /ref (and ?params) — ls-remote wants the
        # repository URL only.
        owner_repo="''${owner_repo%%\?*}"
        repo_part="''${owner_repo#*/}"
        printf 'https://github.com/%s/%s' "''${owner_repo%%/*}" "''${repo_part%%/*}"
        ;;
      *) printf '%s' "''${ref%%\?*}" ;;
    esac
  }

  resolve_image_ref() {
    if [ "$flake_explicit" = 1 ]; then
      resolve_flake_ref
      return
    fi
    # shellcheck disable=SC2157 # remoteFlakeStr is nix-interpolated per
    # instantiation — a compile-time constant in the emitted script.
    if [ -n "${remoteFlakeStr}" ]; then
      # Redirect, never pipe git (SIGPIPE can kill the writer early).
      lsremote="$(mktemp)"
      remote_head=""
      if git ls-remote "$(remote_git_url)" HEAD >"$lsremote" 2>/dev/null; then
        remote_head="$(awk 'NR==1{print $1}' "$lsremote")"
      fi
      rm -f "$lsremote"
      if [ -z "$remote_head" ]; then
        echo "code-sandbox: WARNING: cannot reach $(remote_git_url) (offline?) — falling back to the flake baked in at install time, which may be stale" >&2
        printf '%s' "${flakeRef}"
        return
      fi
      # shellcheck disable=SC2050 # alwaysRemote is nix-interpolated
      # per instantiation — a compile-time constant in the emitted
      # script.
      if [ "${
    if alwaysRemote
    then "1"
    else "0"
  }" = 1 ]; then
        echo "code-sandbox: using ${remoteFlakeStr}/$remote_head (live remote HEAD; force a local build with --flake .)" >&2
        printf '%s/%s' "${remoteFlakeStr}" "$remote_head"
        return
      fi
      # Local-first: a clean checkout whose HEAD equals the remote HEAD
      # builds locally (same content, rev pins correctly); anything else
      # builds the remote HEAD so the briefing pins a real commit.
      repo="$(resolve_flake_ref)"
      if head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
        && [ "$head" = "$remote_head" ] \
        && [ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
        printf '%s' "$repo"
        return
      fi
      echo "code-sandbox: local tree is not exactly the remote HEAD — building the image from ${remoteFlakeStr}/$remote_head so the briefing pins a real commit (force a local build with --flake .)" >&2
      printf '%s/%s' "${remoteFlakeStr}" "$remote_head"
      return
    fi
    repo="$(resolve_flake_ref)"
    remote_head=""
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      remote_url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
      if [ -n "$remote_url" ]; then
        # Redirect, never pipe git (SIGPIPE can kill the writer early).
        lsremote="$(mktemp)"
        git ls-remote "$remote_url" HEAD >"$lsremote" 2>/dev/null || true
        remote_head="$(awk 'NR==1{print $1}' "$lsremote")"
        rm -f "$lsremote"
      fi
    fi
    if head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
      && [ -n "$remote_head" ] && [ "$head" = "$remote_head" ] \
      && [ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
      printf '%s' "$repo"
      return
    fi
    echo "code-sandbox: WARNING: cannot verify the local tree against a remote HEAD (no git remote / no remoteFlake baked in) — the image briefing may pin 'dirty'" >&2
    printf '%s' "$repo"
  }

  # Render the sandbox policy + provider profile from the flake: the
  # templates' @bin_*@ placeholders become the exact store paths of the
  # image's package set, so the files handed to openshell always match
  # the image about to be built. Rendered from the SAME resolved source
  # as the image (resolve_image_ref), never from a different ref. Sets
  # policy_path/profile_path.
  render_configs() {
    ref="$(resolve_image_ref)"
    echo "code-sandbox: rendering sandbox policy + '${profileId}' profile from $ref ..."
    policy_path="$(nix build "''${ref}#${policyAttr}" --no-link --print-out-paths)"
    profile_path="$(nix build "''${ref}#${profileAttr}" --no-link --print-out-paths)"
  }

  # Canonicalize a profile YAML for drift comparison: sort keys and
  # keep only the fields the owning repo controls (the gateway manages
  # resource_version/source/scope itself).
  canon_profile() {
    yq -S -y '{id, display_name, description, category, credentials, endpoints, binaries, inference_capable, discovery}' "$1"
  }

  # Push the rendered provider profile when the gateway copy has
  # drifted (or is missing). Attached sandboxes re-compose their policy
  # from the new profile automatically.
  sync_profile() {
    gw="$(mktemp)"; gw_canon="$(mktemp)"; rendered_canon="$(mktemp)"
    if openshell profile export "${profileId}" --output yaml >"$gw" 2>/dev/null; then
      canon_profile "$profile_path" >"$rendered_canon"
      canon_profile "$gw" >"$gw_canon"
      if diff -u "$gw_canon" "$rendered_canon" >/dev/null; then
        echo "code-sandbox: profile '${profileId}' up to date"
      else
        echo "code-sandbox: profile '${profileId}' drifted from the flake — pushing rendered copy"
        openshell profile update "${profileId}" --file "$profile_path"
      fi
    else
      echo "code-sandbox: profile '${profileId}' missing on the gateway — importing"
      openshell profile import --file "$profile_path"
    fi
    rm -f "$gw" "$gw_canon" "$rendered_canon"
  }

  # Canonicalize a sandbox policy YAML for drift comparison: keep only
  # the fields the owning repo controls (same rationale as
  # canon_profile — the gateway may manage/normalize other fields).
  canon_policy() {
    yq -S -y '{version, filesystem_policy, landlock, network_policies}' "$1"
  }

  # Fetch a sandbox's own (pre-provider-composition) policy into $2.
  # `openshell policy get --base` may prefix the YAML with a comment
  # header up to a '---' separator (the README recipe strips through
  # it); handle both that and a bare/comment-prefixed document, then
  # verify the result actually parses as a policy.
  fetch_base_policy() {
    openshell policy get "$1" --base 2>/dev/null >"$2.raw" || return 1
    if grep -q '^---$' "$2.raw"; then
      sed '1,/^---$/d' "$2.raw" >"$2"
    else
      grep -v '^#' "$2.raw" >"$2"
    fi
    rm -f "$2.raw"
    yq -e '.network_policies' "$2" >/dev/null 2>&1
  }

  # Write the rendered policy into $2, adjusted to preserve the
  # include_workdir value found in the gateway policy file $1 (create
  # flips that line for --include-workdir sandboxes; sync must never
  # silently change a sandbox's filesystem posture).
  rendered_policy_for() {
    if grep -q 'include_workdir: true' "$1"; then
      sed 's/^\( *\)include_workdir: false$/\1include_workdir: true/' "$policy_path" >"$2"
    else
      cp "$policy_path" "$2"
    fi
  }

  # Push the rendered sandbox policy to every sandbox whose gateway
  # copy drifted from the flake (`openshell policy set` hot-reloads —
  # no recreation needed). Only sandboxes whose current policy carries
  # the code-agent marker (a nix_store network entry) are touched: an
  # unrelated sandbox's posture is never rewritten.
  sync_policies() {
    sandbox_names="$(list_sandbox_names)"
    if [ -z "$sandbox_names" ]; then
      echo "code-sandbox: no sandboxes to policy-sync"
      return 0
    fi
    for sb in $sandbox_names; do
      gw="$(mktemp)"; adj="$(mktemp)"
      if ! fetch_base_policy "$sb" "$gw"; then
        echo "code-sandbox: $sb: policy unreadable — skipping" >&2
      elif ! grep -q 'name: nix_store' "$gw"; then
        echo "code-sandbox: $sb: not a code-agent policy (no nix_store entry) — skipping"
      else
        rendered_policy_for "$gw" "$adj"
        if diff <(canon_policy "$gw") <(canon_policy "$adj") >/dev/null 2>&1; then
          echo "code-sandbox: $sb: policy up to date"
        else
          echo "code-sandbox: $sb: policy drifted from the flake — pushing rendered copy (hot-reloads, no recreation)"
          openshell policy set "$sb" --policy "$adj" --wait
        fi
      fi
      rm -f "$gw" "$adj"
    done
  }

  # Report one provider's presence (plus refresh status when present).
  # Returns nonzero when missing: `create` treats that as fatal,
  # `sync`/`doctor` as a finding.
  check_provider() {
    if openshell provider get "$1" >/dev/null 2>&1; then
      echo "code-sandbox: provider '$1' present"
      openshell provider refresh status "$1" 2>/dev/null || true
    else
      echo "code-sandbox: provider '$1' MISSING on the gateway — its sandbox egress fails closed" >&2
      echo "  fix: export <TOKEN_ENV> && openshell provider create --name $1 --type $1 --credential <TOKEN_ENV>" >&2
      return 1
    fi
  }

  # The provider list for this invocation: --provider replaces the
  # baked defaults entirely; otherwise the base providers plus the
  # credential provider for the selected --agent.
  provider_list() {
    if [ -n "$extra_providers" ]; then
      printf '%s' "$extra_providers"
      return
    fi
    case "$agent" in
      claude) agent_credential="claude-subscription" ;;
      *) agent_credential="kimi-for-coding" ;;
    esac
    printf '%s %s' "$default_providers" "$agent_credential"
  }

  cmd="create"
  if [ $# -gt 0 ] && [ "$1" != "''${1#-}" ]; then
    :
  elif [ $# -gt 0 ]; then
    case "$1" in
      create | delete | connect | exec | ssh-config | sync | doctor) cmd="$1"; shift ;;
      -h | --help) usage 0 ;;
      *) usage 1 ;;
    esac
  fi

  flake_ref="${flakeRef}" flake_explicit=0 default_providers="${providersStr}" extra_providers=""
  name="" yes=0 cpu="${cpu}" memory="${memory}" sync=1 include_workdir="${
    if includeWorkdir
    then "1"
    else "0"
  }" \
    ssh_config=1 ssh_config_file="$HOME/.ssh/config.local" agent="${defaultAgent}"
  while [ $# -gt 0 ]; do
    case "$1" in
      -y | --yes) yes=1; shift ;;
      --agent) agent="''${2:?--agent needs a value}"; shift 2 ;;
      --cpu) cpu="''${2:?--cpu needs a value}"; shift 2 ;;
      --memory) memory="''${2:?--memory needs a value}"; shift 2 ;;
      --flake) flake_explicit=1; flake_ref="''${2:?--flake needs a value}"; shift 2 ;;
      --provider) extra_providers="''${extra_providers:-} ''${2:?--provider needs a value}"; shift 2 ;;
      --sync) sync=1; shift ;;
      --no-sync) sync=0; shift ;;
      --include-workdir) include_workdir=1; shift ;;
      --no-include-workdir) include_workdir=0; shift ;;
      --ssh-config) ssh_config=1; shift ;;
      --no-ssh-config) ssh_config=0; shift ;;
      --ssh-config-file) ssh_config_file="''${2:?--ssh-config-file needs a value}"; shift 2 ;;
      -h | --help) usage 0 ;;
      --) shift; break ;;
      -*)
        if [ "$cmd" = exec ]; then break; fi
        echo "code-sandbox: unknown option: $1" >&2; usage 1 ;;
      *)
        if [ -z "$name" ]; then name="$1"; shift
        elif [ "$cmd" = exec ]; then break
        else echo "code-sandbox: unexpected argument: $1" >&2; usage 1
        fi ;;
    esac
  done

  case "$agent" in
    pi | kimi | claude) ;;
    *) echo "code-sandbox: --agent must be pi, kimi or claude (got '$agent')" >&2; usage 1 ;;
  esac

  case "$cmd" in
    delete)
      [ -n "$name" ] || { echo "code-sandbox: delete needs a sandbox name" >&2; usage 1; }
      exec openshell sandbox delete "$name"
      ;;
    connect)
      [ -n "$name" ] || { echo "code-sandbox: connect needs a sandbox name" >&2; usage 1; }
      exec openshell sandbox connect "$name"
      ;;
    exec)
      [ -n "$name" ] || { echo "code-sandbox: exec needs a sandbox name" >&2; usage 1; }
      exec openshell sandbox exec -n "$name" -- "$@"
      ;;
    ssh-config)
      [ -z "$name" ] || { echo "code-sandbox: ssh-config takes no sandbox name (it syncs all of them)" >&2; usage 1; }
      # Redirect, never pipe the CLI (EPIPE panic, exit 101).
      sandbox_names="$(list_sandbox_names)"
      [ -n "$sandbox_names" ] || { echo "code-sandbox: no active sandboxes found" >&2; exit 1; }
      for sb in $sandbox_names; do
        append_ssh_config "$sb"
      done
      exit 0
      ;;
    sync)
      [ -z "$name" ] || { echo "code-sandbox: sync takes no sandbox name" >&2; usage 1; }
      render_configs
      sync_profile
      sync_policies
      for p in $(provider_list); do
        check_provider "$p" || true
      done
      exit 0
      ;;
    doctor)
      [ -z "$name" ] || { echo "code-sandbox: doctor takes no sandbox name" >&2; usage 1; }
      findings=0
      render_configs

      echo "== profile '${profileId}' =="
      gw="$(mktemp)"; gw_canon="$(mktemp)"; rendered_canon="$(mktemp)"
      canon_profile "$profile_path" >"$rendered_canon"
      if openshell profile export "${profileId}" --output yaml >"$gw" 2>/dev/null; then
        canon_profile "$gw" >"$gw_canon"
        if diff -u "$gw_canon" "$rendered_canon" >/dev/null; then
          echo "  up to date"
        else
          echo "  DRIFTED from the flake — run: code-sandbox sync"
          findings=1
        fi
      else
        echo "  MISSING on the gateway — run: code-sandbox sync"
        findings=1
      fi
      rm -f "$gw" "$gw_canon" "$rendered_canon"

      echo "== providers =="
      for p in $(provider_list); do
        if openshell provider get "$p" >/dev/null 2>&1; then
          echo "  $p: present"
          openshell provider refresh status "$p" 2>/dev/null | sed 's/^/    /' || true
        else
          echo "  $p: MISSING — create it (see the fix hint under 'code-sandbox sync')"
          findings=1
        fi
      done

      echo "== sandboxes =="
      sandbox_names="$(list_sandbox_names)"
      if [ -z "$sandbox_names" ]; then
        echo "  (none running)"
      else
        ref="$(resolve_image_ref)"
        img="$(nix build "''${ref}#${imageAttr}" --no-link --print-out-paths)"
        shorthash="$(basename "$img" | cut -c1-8)"
        for sb in $sandbox_names; do
          case "$sb" in
            *"-$shorthash") echo "  $sb: image current (-$shorthash)" ;;
            *)
              echo "  $sb: STALE IMAGE (current is -$shorthash) — recreate to pick up image/policy changes"
              findings=1
              ;;
          esac
          openshell sandbox provider list "$sb" 2>/dev/null | sed 's/^/    providers: /' || echo "    providers: (query failed)"
          openshell policy list "$sb" 2>/dev/null | tail -n 3 | sed 's/^/    policy: /' || true
          # Policy drift vs the rendered flake policy (sync pushes it).
          gwpol="$(mktemp)"; adjpol="$(mktemp)"
          if fetch_base_policy "$sb" "$gwpol" && grep -q 'name: nix_store' "$gwpol"; then
            rendered_policy_for "$gwpol" "$adjpol"
            if diff <(canon_policy "$gwpol") <(canon_policy "$adjpol") >/dev/null 2>&1; then
              echo "    policy drift: none"
            else
              echo "    policy drift: DRIFTED from the flake — run: code-sandbox sync"
              findings=1
            fi
          fi
          rm -f "$gwpol" "$adjpol"
          # Egress smoke: two admitted endpoints probed THROUGH the
          # sandbox's own policy — github.com via curl (read) and
          # cache.nixos.org via nix store ping. Diagnosis rule (learned
          # 2026-10): an instant "Could not connect" with NO deny line
          # in the sandbox log is a proxy-level flake, not policy
          # drift — retry once, then report; only a logged deny line
          # means the policy denied.
          if openshell sandbox exec -n "$sb" -- curl -sf -m 8 -o /dev/null https://github.com 2>/dev/null; then
            echo "    egress: github.com (curl) OK"
          else
            echo "    egress: github.com (curl) FAILED — check the sandbox log for deny lines:"
            echo "      openshell logs $sb --source sandbox | grep -iE 'denied|reject|block|forbidden'"
            findings=1
          fi
          if openshell sandbox exec -n "$sb" -- nix store ping --store https://cache.nixos.org >/dev/null 2>&1; then
            echo "    egress: cache.nixos.org (nix) OK"
          else
            echo "    egress: cache.nixos.org (nix) FAILED — same deny-log grep as above"
            findings=1
          fi
        done
      fi
      if [ "$findings" = 0 ]; then
        echo "code-sandbox: doctor: all good"
      else
        echo "code-sandbox: doctor: findings above (sync: code-sandbox sync)"
        exit 1
      fi
      exit 0
      ;;
  esac

  # ---- create ----
  render_configs
  if [ "$sync" = 1 ]; then
    sync_profile
  else
    echo "code-sandbox: --no-sync: gateway profile NOT checked (it may drift from the image)"
  fi
  for p in $(provider_list); do
    check_provider "$p" || { echo "code-sandbox: aborting: create would fail closed without provider '$p'" >&2; exit 1; }
  done

  ref="$(resolve_image_ref)"
  echo "code-sandbox: building ${imageAttr} from $ref ..."
  img="$(nix build "''${ref}#${imageAttr}" --no-link --print-out-paths)"
  shorthash="$(basename "$img" | cut -c1-8)"
  tag="${imageName}:$shorthash"
  # The default name embeds the agent, so a kimi sandbox and a claude
  # sandbox of the same image don't collide (code-kimi-<hash> vs
  # code-claude-<hash>) — one sandbox per coding agent is the model.
  name="''${name:-${defaultName}-$agent}-$shorthash"

  echo "code-sandbox: loading image as $tag ..."
  nix run "''${ref}#${loaderApp}"
  docker tag ${imageName}:latest "$tag"

  exists=0
  if openshell sandbox inspect "$name" >/dev/null 2>&1; then
    exists=1
  else
    # No `openshell ... | grep -q`: the CLI panics (exit 101) on EPIPE —
    # redirect to a file first (documented lesson in the openshell guide).
    sandbox_list="$(mktemp)"
    openshell sandbox list >"$sandbox_list" 2>/dev/null || true
    if awk '{print $1}' "$sandbox_list" | grep -qx "$name"; then
      exists=1
    fi
    rm -f "$sandbox_list"
  fi
  if [ "$exists" = 1 ]; then
    if [ "$yes" != 1 ]; then
      printf "code-sandbox: sandbox '%s' already exists (older image). Delete and recreate? [y/N] " "$name"
      read -r ans
      case "$ans" in
        y | Y | yes | YES) ;;
        *) echo "code-sandbox: aborted."; exit 1 ;;
      esac
    fi
    openshell sandbox delete "$name"
  fi

  provider_args=()
  for p in $(provider_list); do
    provider_args+=(--provider "$p")
  done

  # Create-time sandbox env: spec env survives the supervisor's env
  # scrub on EVERY spawn path (raw ssh, editor servers, non-shell
  # exec), unlike the image Env. Rendered from the SAME resolved source
  # as the image. A flake without the attr warns and continues.
  env_args=()
  # shellcheck disable=SC2157 # envAttrStr is nix-interpolated per
  # instantiation — a compile-time constant in the emitted script.
  if [ -n "${envAttrStr}" ]; then
    if env_path="$(nix build "''${ref}#${envAttrStr}" --no-link --print-out-paths 2>/dev/null)"; then
      while IFS= read -r env_line; do
        case "$env_line" in
          "" | \#*) ;;
          *) env_args+=(--env "$env_line") ;;
        esac
      done <"$env_path"
    else
      echo "code-sandbox: WARNING: $ref has no #${envAttrStr} — skipping create-time sandbox env (in-image shell env still applies)" >&2
    fi
  fi

  # Stamp the sandbox's coding agent: CODE_AGENT survives the env scrub
  # on every spawn path (spec env, same channel as the file above) and
  # the image's launcher wrappers read it to start the single headroom
  # proxy with the right upstream — and to refuse agents from the wrong
  # routing family.
  env_args+=(--env "CODE_AGENT=$agent")

  create_policy="$policy_path"
  if [ "$include_workdir" = 1 ]; then
    # include_workdir is a POLICY BIT only (the sandbox's internal
    # /sandbox joins read_write; no host files are ever mounted — the VM
    # driver has no host-share mechanism). The rendered policy ships
    # include_workdir: false; the toggle flips that single line for this
    # create, and sync preserves the sandbox's bit. File transfer rides
    # the CLI's native `openshell sandbox upload`/`download`.
    create_policy="$(mktemp)"
    sed 's/^\( *\)include_workdir: false$/\1include_workdir: true/' "$policy_path" >"$create_policy"
  fi

  echo "code-sandbox: creating sandbox '$name' (agent=$agent cpu=$cpu memory=$memory) ..."
  openshell sandbox create --name "$name" --from "$tag" \
    --policy "$create_policy" \
    "''${provider_args[@]}" \
    "''${env_args[@]}" \
    --cpu "$cpu" --memory "$memory" \
    --detach -- bash -l

  echo "code-sandbox: done. Attach with:  code-sandbox connect $name"

  # Append the generated Remote-SSH config (the equivalent of
  # `openshell sandbox ssh-config $name >> ~/.ssh/config.local`).
  if [ "$ssh_config" = 1 ]; then
    append_ssh_config "$name"
  fi
''
