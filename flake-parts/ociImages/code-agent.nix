{inputs, ...}: {
  # ------ Per-System ------ #
  # General-purpose coding sandbox image for OpenShell (VM driver): a
  # lean, hand-picked toolset + nix (runtime package adds via
  # substitution) + first-class VSCodium Remote-SSH support. This is the
  # single place OpenShell sandbox images come from — devenv stays
  # human-only.
  #
  # Built with nix2container, NOT dockerTools: the VM driver's image-prep
  # (umoci-v3) reproducibly corrupts the ext4 it produces from the
  # dockerTools stream of a large image ("Block bitmap checksum does not
  # match"), while nix2container images (same layer counts, same sizes)
  # provision fine. Tiny dockerTools images pass, so the trigger is
  # size/layer-count dependent; nix2container is the proven path on this
  # driver.
  #
  # Delivery to the VM driver (openshell-driver-vm): the driver first
  # checks the host container engine's local image store, so
  # `nix run .#load-code-agent-image` (skopeo copy into docker-daemon:)
  # is enough; OCI registry pull is the fallback.
  #
  # Remote-SSH contract (learned the hard way): the in-VM sshd runs
  # extension commands with a store-only PATH, so the install-script
  # toolchain lives in /usr/local/bin (+ /etc/profile for login shells)
  # on top of /bin from the base toolset; the vscodium-reh tarball's
  # bundled node is a foreign glibc binary — it gets patchelf'd to the
  # image glibc (pre-baked server below), and the nix-ld shim
  # (/lib64/ld-linux-x86-64.so.2 + NIX_LD env, rootfs below) covers any
  # other downloaded glibc ELF.
  perSystem = {
    pkgs,
    inputs',
    self',
    customLib,
    ...
  }: let
    inherit (pkgs) lib;
    inherit (customLib) relativeToRoot;
    n2c = inputs'.nix2container.packages.nix2container;

    # VSCodium release whose vscodium-reh server matches the fleet's
    # codium 1.126.0 (DISTRO_COMMIT from `Help > About`). Bump both when
    # nixpkgs' vscodium moves; on mismatch the install script falls back
    # to downloading (github.com + *.githubusercontent.com must stay
    # admitted in openshell/policies/code-agent.yaml).
    vscodiumVersion = "1.126.04524";
    vscodiumCommit = "4c0b0c6cc561d2d3636d1ec250935431876ce4dc";

    # vscodium-reh server payload with the bundled node patchelf'd to
    # the image toolchain: nix store rpath/interpreter, so it runs with
    # no env, no ld.so.cache dependency, and no FHS assumptions.
    vscodium-server = pkgs.stdenv.mkDerivation {
      pname = "vscodium-reh";
      version = vscodiumVersion;
      src = pkgs.fetchurl {
        url = "https://github.com/VSCodium/vscodium/releases/download/${vscodiumVersion}/vscodium-reh-linux-x64-${vscodiumVersion}.tar.gz";
        hash = "sha256-NC+skexxc6/7jdALQ5uGiz7mziKdx9GLuUx83W2YWoA=";
      };
      nativeBuildInputs = [pkgs.patchelf];
      dontUnpack = true;
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        tar -xzf $src -C $out --strip-components=1
        patchelf \
          --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 \
          --set-rpath ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib pkgs.glibc]} \
          $out/node
        # The upstream tarball ships scripts with the CI's nix store
        # bash in the shebang — an accident of matching nixpkgs pins,
        # not a contract. Point them at the image bash.
        sed -i '1s|^#!.*|#!${pkgs.bashInteractive}/bin/sh|' $out/bin/codium-server
        runHook postInstall
      '';
    };

    # Repo skill set baked read-only at /opt/skills, built by
    # inputs.agents.lib.mkSkills — the same helper (and the same repo
    # skills/ + external-sources composition) home-manager installs for
    # the agents on NixOS hosts (homeSpec.agents.skills in
    # flake-parts/homeModules/agents.nix). Wired into pi/kimi/claude in
    # agentDirs above.
    skillsTree = inputs.agents.lib.mkSkills {
      inherit pkgs;
      customSkills = relativeToRoot "skills";
      # Mirror of the fleet-wide list in
      # flake-parts/homeModules/agents.nix (externalSkillSources) —
      # the same tree the NixOS hosts install for their agents.
      # homeSpec.agents.skills.extraSources remains the per-machine
      # escape hatch on the home-manager side (not baked here).
      externalSkills = [
        {
          src = inputs.skills-anthropic;
          selectSkills = ["doc-coauthoring" "docx" "internal-comms" "mcp-builder" "skill-creator" "xlsx"];
        }
        {src = inputs.skills-cloudflare;}
        {src = inputs.skills-payloadcms;}
        {src = inputs.skills-supabase;}
        {src = inputs.skills-fluxcd;}
        {src = inputs.skills-terraform;}
        # Google official skills — all categories (nested
        # skills/<category>/<name> layout, one entry per category).
        {
          src = inputs.skills-google;
          skillsDir = "skills/ads";
        }
        {
          src = inputs.skills-google;
          skillsDir = "skills/analytics";
        }
        {
          src = inputs.skills-google;
          skillsDir = "skills/cloud";
        }
        {
          src = inputs.skills-google;
          skillsDir = "skills/developers";
        }
        {
          src = inputs.skills-google;
          skillsDir = "skills/identity";
        }
        {src = inputs.openshell;}
        {
          src = inputs.openshell;
          skillsDir = ".agents/skills";
        }
      ];
    };

    # /bin + /usr/bin toolset (the sshd default PATH covers /bin) plus
    # merged /etc contributions (ssl certs, ssh client config, nix
    # profile snippets, /usr/bin/env).
    baseTools = pkgs.buildEnv {
      name = "code-agent-base";
      paths = with pkgs; [
        bashInteractive
        coreutils
        gnused
        gnugrep
        gawk
        findutils
        gnutar
        gzip
        xz
        procps
        util-linux
        git
        gh
        curl
        cacert
        jq
        yq
        python3
        ripgrep
        openssh
        tmux
        less
        nix
        # Nix language server + the repo's lint trio: agent-edited
        # .nix files can be vetted in-sandbox (runtime `nix profile
        # install` adds work too, but TCG builds crawl — bake them).
        nixd
        alejandra
        statix
        deadnix
        # General build/debug tooling: archives (unzip/zstd), scripted
        # downloads (wget — many install scripts hardcode it), foreign
        # ELF inspection (file/readelf/objdump/ldd — the patchelf/FHS
        # fallback path), hand-applied patches (diff/patch), k8s clients
        # (kubectl/helm — cluster API egress rides an attached provider
        # or port-forward, so no policy host is bound here), agent
        # ergonomics (fd/sd), shell vetting (shellcheck/shfmt), DNS
        # digs for policy debugging (dnsutils), and rsync for
        # backup/world-file work.
        unzip
        zstd
        wget
        file
        binutils
        diffutils
        patch
        kubectl
        kubernetes-helm
        fd
        sd
        shellcheck
        shfmt
        dnsutils
        rsync
        # uv: wheel-first Python package installer (baked so PyPI
        # egress — admitted read-only in the sandbox policy — has a
        # pinned binary; pip itself ships inside `python3 -m venv`).
        uv
        # Go toolchain: module/toolchain fetches ride the golang policy
        # entry (proxy.golang.org + sum.golang.org admitted for the go
        # binary; direct-VCS fallback reuses git's github/gitea
        # admissions). GOPATH/GOMODCACHE default to writable $HOME/go.
        go
        # Tiny but constantly missed: which (install scripts probe with
        # it) and ncurses' clear/tput/reset (nixpkgs ncurses carries its
        # own terminfo db — verified clear works under a real TERM).
        which
        ncurses
        # The clan CLI: baked because it can never be obtained
        # in-sandbox — clan-cli's clan-runtime dependency builds with a
        # nested `nix flake update --store ./.` inside the builder,
        # which the sandbox supervisor's egress and the overlayfs
        # rename assert cannot support (verified: exit 134 in-sandbox).
        # On the image-build host the derivation substitutes/builds
        # normally, and in-sandbox the finished closure runs fine.
        clan-cli
        # AI coding agents (all from the llm-agents flake input, see
        # overlays/default.nix): pi runs on bun, kimi-code and
        # claude-code are bundled node/bun apps — closures carry their
        # runtimes.
        pi-coding-agent
        kimi-code
        claude-code
        dockerTools.usrBinEnv
        # github-mcp-server: driven by the agents' baked mcp.json
        # (see sandboxMcpServers); auth rides the github-agent provider
        # attached at sandbox creation.
        pkgs.unstable.github-mcp-server
      ];
      pathsToLink = ["/bin" "/usr/bin" "/etc"];
    };

    # FHS rootfs additions merged at the image /:
    #  - /usr/local/bin: install-script + server-side toolchain, in case
    #    the sshd PATH lacks /bin in some invocation path.
    #  - /etc/{os-release,profile,passwd,group,shadow}: truthful
    #    os-release for the install script, PATH + foreign-ELF/wheel
    #    runtime env for login shells, and identity for nix (getpwuid
    #    home lookup) and the vscodium server's shells.
    #  - /lib64/ld-linux-x86-64.so.2: the nix-ld shim (with
    #    /usr/lib/wheel-deps) — foreign glibc ELFs resolve through the
    #    shim's NIX_LD/NIX_LD_LIBRARY_PATH env, not through copied libs
    #    or an ld.so.cache (nixpkgs glibc never reads /etc/ld.so.cache;
    #    its compiled-in cache path is the read-only store etc/).
    rootfs = pkgs.runCommand "code-agent-rootfs" {} ''
      mkdir -p $out/usr/local/bin $out/etc \
        $out/lib64 $out/usr/lib/wheel-deps

      # sshd-default-PATH toolchain.
      ln -s ${pkgs.bashInteractive}/bin/bash        $out/usr/local/bin/bash
      ln -s ${pkgs.coreutils}/bin/uname             $out/usr/local/bin/uname
      ln -s ${pkgs.gnused}/bin/sed                  $out/usr/local/bin/sed
      ln -s ${pkgs.gnugrep}/bin/grep                $out/usr/local/bin/grep
      ln -s ${pkgs.gnutar}/bin/tar                  $out/usr/local/bin/tar
      ln -s ${pkgs.gzip}/bin/gzip                   $out/usr/local/bin/gzip
      ln -s ${pkgs.gzip}/bin/gunzip                 $out/usr/local/bin/gunzip
      ln -s ${pkgs.curl}/bin/curl                   $out/usr/local/bin/curl
      ln -s ${pkgs.procps}/bin/ps                   $out/usr/local/bin/ps
      ln -s ${pkgs.util-linux}/bin/flock            $out/usr/local/bin/flock
      ln -s ${pkgs.git}/bin/git                     $out/usr/local/bin/git
      ln -s ${pkgs.gh}/bin/gh                       $out/usr/local/bin/gh
      ln -s ${pkgs.jq}/bin/jq                       $out/usr/local/bin/jq
      ln -s ${pkgs.yq}/bin/yq                       $out/usr/local/bin/yq
      ln -s ${pkgs.python3}/bin/python3             $out/usr/local/bin/python3
      ln -s ${pkgs.ripgrep}/bin/rg                  $out/usr/local/bin/rg
      ln -s ${pkgs.tmux}/bin/tmux                   $out/usr/local/bin/tmux
      ln -s ${pkgs.less}/bin/less                   $out/usr/local/bin/less
      ln -s ${pkgs.openssh}/bin/ssh                 $out/usr/local/bin/ssh
      ln -s ${pkgs.nix}/bin/nix                     $out/usr/local/bin/nix
      ln -s ${pkgs.pi-coding-agent}/bin/pi          $out/usr/local/bin/pi
      ln -s ${pkgs.kimi-code}/bin/kimi              $out/usr/local/bin/kimi
      ln -s ${pkgs.claude-code}/bin/claude          $out/usr/local/bin/claude
      ln -s ${pkgs.clan-cli}/bin/clan               $out/usr/local/bin/clan
      ln -s ${pkgs.nixd}/bin/nixd                   $out/usr/local/bin/nixd
      ln -s ${pkgs.alejandra}/bin/alejandra         $out/usr/local/bin/alejandra
      ln -s ${pkgs.statix}/bin/statix               $out/usr/local/bin/statix
      ln -s ${pkgs.deadnix}/bin/deadnix             $out/usr/local/bin/deadnix
      ln -s ${pkgs.unzip}/bin/unzip                 $out/usr/local/bin/unzip
      ln -s ${pkgs.zstd}/bin/zstd                   $out/usr/local/bin/zstd
      ln -s ${pkgs.wget}/bin/wget                   $out/usr/local/bin/wget
      ln -s ${pkgs.file}/bin/file                   $out/usr/local/bin/file
      ln -s ${pkgs.binutils}/bin/readelf            $out/usr/local/bin/readelf
      ln -s ${pkgs.binutils}/bin/objdump            $out/usr/local/bin/objdump
      ln -s ${pkgs.glibc.bin}/bin/ldd               $out/usr/local/bin/ldd
      ln -s ${pkgs.diffutils}/bin/diff              $out/usr/local/bin/diff
      ln -s ${pkgs.patch}/bin/patch                 $out/usr/local/bin/patch
      ln -s ${pkgs.kubectl}/bin/kubectl             $out/usr/local/bin/kubectl
      ln -s ${pkgs.kubernetes-helm}/bin/helm        $out/usr/local/bin/helm
      ln -s ${pkgs.fd}/bin/fd                       $out/usr/local/bin/fd
      ln -s ${pkgs.sd}/bin/sd                       $out/usr/local/bin/sd
      ln -s ${pkgs.shellcheck}/bin/shellcheck       $out/usr/local/bin/shellcheck
      ln -s ${pkgs.shfmt}/bin/shfmt                 $out/usr/local/bin/shfmt
      ln -s ${pkgs.dnsutils}/bin/dig                $out/usr/local/bin/dig
      ln -s ${pkgs.rsync}/bin/rsync                 $out/usr/local/bin/rsync
      ln -s ${pkgs.uv}/bin/uv                       $out/usr/local/bin/uv
      ln -s ${pkgs.go}/bin/go                       $out/usr/local/bin/go
      ln -s ${pkgs.go}/bin/gofmt                    $out/usr/local/bin/gofmt
      ln -s ${pkgs.which}/bin/which                 $out/usr/local/bin/which
      ln -s ${pkgs.ncurses}/bin/clear               $out/usr/local/bin/clear
      # headroom via the env-mapping wrapper (MCP configs and
      # interactive use both resolve to this PATH entry).
      ln -s ${sandboxHeadroom}/bin/headroom         $out/usr/local/bin/headroom

      # Login shells (interactive SSH + VSCodium terminal) read
      # /etc/profile: put the layer on PATH there too, plus the
      # foreign-ELF/wheel runtime env (sshd-spawned shells can run with
      # a scrubbed env, losing the image Env values). LD_LIBRARY_PATH
      # and NIX_LD_LIBRARY_PATH append rather than overwrite. (Quoted
      # heredoc: Nix interpolates the store paths at eval time; the
      # runtime $ expansions stay literal for the sourcing shell.)
      # Idempotent under repeat sourcing: nested `bash -l` shells
      # re-read this file, and the pre-fix version appended on every
      # pass — tripling PATH, LD_LIBRARY_PATH and NIX_LD_LIBRARY_PATH
      # in long agent sessions (observed live). PATH and
      # LD_LIBRARY_PATH get a membership test; NIX_LD and
      # NIX_LD_LIBRARY_PATH are set only when absent (they are image
      # Env values; a shell that scrubbed its env still gets them, but
      # an existing value is never re-appended to).
      cat > $out/etc/profile <<'EOF'
      case ":$PATH:" in
        *:/usr/local/bin:*) ;;
        *) export PATH="/usr/local/bin:$PATH" ;;
      esac
      # uv tool/pipx-style user binaries (uv warns otherwise; $HOME is
      # /sandbox under the supervisor, /home/agent under plain docker).
      case ":$PATH:" in
        *:"$HOME/.local/bin":*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
      esac
      case ":$LD_LIBRARY_PATH:" in
        *:/usr/lib/wheel-deps:*) ;;
        *) export LD_LIBRARY_PATH="/usr/lib/wheel-deps''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
      esac
      if [ -z "''${NIX_LD:-}" ]; then
        export NIX_LD="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
      fi
      if [ -z "''${NIX_LD_LIBRARY_PATH:-}" ]; then
        export NIX_LD_LIBRARY_PATH="${nixLdLibs}"
      fi
      EOF

      # nix config on disk (see nixConfig above): unlike $NIX_CONFIG in
      # the image Env, every nix invocation reads this — VSCodium-server
      # and sshd-spawned shells can run with a store-only or scrubbed
      # env, which is exactly how `nix run` ended up with flakes
      # disabled.
      mkdir -p $out/etc/nix
      cat > $out/etc/nix/nix.conf <<'EOF'
      ${nixConfig}
      EOF

      # Pin the flake registry so `nix run nixpkgs#…` resolves without
      # channels.nixos.org (not admitted; nix reports "you don't have
      # Internet access" otherwise). A baked-in nixpkgs checkout was
      # dropped on purpose: it is the image's single heaviest payload
      # (hundreds of MB unpacked for a tree an agent touches rarely),
      # and nix2container's copyToRoot rewrite semantics dump the tree
      # at the image root instead of its store path. Pinning the alias
      # to the nixos-unstable branch on github.com (admitted) costs one
      # ~50MB tarball fetch on first resolution, cached in
      # ~/.cache/nix afterwards; binaries still come from the admitted
      # cache.nixos.org substituter.
      cat > $out/etc/nix/registry.json <<'EOF'
      {
        "flakes": [
          {
            "from": {"id": "nixpkgs", "type": "indirect"},
            "to": {"owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable", "type": "github"}
          }
        ],
        "version": 2
      }
      EOF

      printf '%s\n' 'NAME="code-agent"' 'ID="code-agent"' > $out/etc/os-release

      # Git defaults: the org bot identity (andrewthomaslee-agent, per
      # the external-systems org — per-repo config can still override)
      # and a credential helper scoped to github.com that feeds git the
      # provider-injected $GITHUB_TOKEN — without it git prompts for
      # credentials on every https push. Scoped by URL on purpose: only
      # github.com receives the (opaque) handle; the supervisor
      # substitutes the real token at egress.
      cat > $out/etc/gitconfig <<'EOF'
      [user]
      	name = andrewthomaslee-agent
      	email = andrewthomaslee-agent@users.noreply.github.com
      [credential "https://github.com"]
      	helper = "!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f"
      EOF

      # Minimal identity database: nix resolves the user's home via
      # getpwuid, and the vscodium server spawns shells for uid 1000.
      cat > $out/etc/passwd <<EOF
      root:x:0:0:System administrator:/root:${pkgs.bashInteractive}/bin/bash
      agent:x:1000:1000:Agent:/home/agent:${pkgs.bashInteractive}/bin/bash
      EOF
      cat > $out/etc/group <<EOF
      root:x:0:
      agent:x:1000:
      EOF
      echo 'root:!x:::::::' > $out/etc/shadow
      echo 'agent:!x:::::::' >> $out/etc/shadow

      # Foreign-glibc ELF support, replacing the old glibc-copy +
      # ld.so.cache approach (which never worked: nixpkgs glibc's
      # compiled-in cache path is its own read-only store etc/, so the
      # baked /etc/ld.so.cache was never read and the copied libs were
      # invisible at runtime):
      #  - nix-ld (github.com/nix-community/nix-ld):
      #    /lib64/ld-linux-x86-64.so.2 IS the shim; it reads NIX_LD (the
      #    real loader) and NIX_LD_LIBRARY_PATH (extra search dirs) from
      #    the env and runs the downloaded binary against the nix glibc.
      #  - /usr/lib/wheel-deps: libstdc++/libgcc_s/libz reachable via
      #    LD_LIBRARY_PATH (image Env + /etc/profile) so python3's
      #    manylinux wheel extensions (numpy, pillow, lxml, ...) resolve
      #    the handful of system libs they link at dlopen time. Scoped
      #    to those three libs on purpose: loader search order puts
      #    LD_LIBRARY_PATH before DT_RUNPATH, so a broader dir would
      #    shadow nix store libs process-wide. The agent runtimes are
      #    unaffected (pi's bun links no libstdc++; claude's node is
      #    smoke-tested against the shadow).
      ln -s ${pkgs.nix-ld}/libexec/nix-ld $out/lib64/ld-linux-x86-64.so.2
      ln -s ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 $out/usr/lib/wheel-deps/
      ln -s ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 $out/usr/lib/wheel-deps/
      ln -s ${pkgs.zlib}/lib/libz.so.1 $out/usr/lib/wheel-deps/
    '';

    # Home, workdir, and the pre-baked per-agent wiring. Owned
    # 1000:1000 via perms below (OpenShell runs USER-less images as
    # UID/GID 1000; the image declares that user explicitly).
    agentDirs = pkgs.runCommand "code-agent-dirs" {} ''
      mkdir -p $out/home/agent $out/sandbox/.vscodium-server/bin
      # Pre-baked server at the path the jeanp413 open-remote-ssh
      # install script probes ($HOME/.vscodium-server with HOME=/sandbox
      # under the supervisor): script present means "already installed",
      # so connect is instant and offline.
      ln -s ${vscodium-server} $out/sandbox/.vscodium-server/bin/${vscodiumCommit}

      # pi's kimi-for-coding wiring: models.json overrides the built-in
      # kimi-coding provider to read its key from $KIMI_API_KEY (env
      # interpolation, no key in the image). Baked at both $HOME roots:
      # the supervisor points HOME at /sandbox, plain docker runs at
      # /home/agent.
      mkdir -p $out/sandbox/.pi/agent $out/home/agent/.pi/agent
      cp ${pi-models} $out/sandbox/.pi/agent/models.json
      cp ${pi-models} $out/home/agent/.pi/agent/models.json
      # pi skills: explicit resource path at the canonical baked
      # location (the ~/.agents/skills symlink below is the same tree
      # via the Agent Skills standard location, belt and braces).
      cp ${pi-settings} $out/sandbox/.pi/agent/settings.json
      cp ${pi-settings} $out/home/agent/.pi/agent/settings.json
      # pi MCP servers: ~/.pi/agent/mcp.json is the user-level spot
      # (available in every project) — same trio as claude, with
      # pi-specific exposure/description fields (pi-mcp-json below).
      cp ${pi-mcp-json} $out/sandbox/.pi/agent/mcp.json
      cp ${pi-mcp-json} $out/home/agent/.pi/agent/mcp.json

      # kimi-code: config.toml pre-wires the Kimi for Coding
      # subscription (no /login — the OAuth hosts are deliberately
      # unreachable under the sandbox policy); skills dir at the
      # location kimi scans ($KIMI_CODE_HOME/skills).
      mkdir -p $out/sandbox/.kimi-code $out/home/agent/.kimi-code
      cp ${kimi-config} $out/sandbox/.kimi-code/config.toml
      cp ${kimi-config} $out/home/agent/.kimi-code/config.toml
      # kimi MCP servers: ~/.kimi-code/mcp.json, same shared trio.
      cp ${sandbox-mcp-json} $out/sandbox/.kimi-code/mcp.json
      cp ${sandbox-mcp-json} $out/home/agent/.kimi-code/mcp.json
      ln -s /opt/skills $out/sandbox/.kimi-code/skills
      ln -s /opt/skills $out/home/agent/.kimi-code/skills

      # claude: personal skills dir + first-run onboarding skipped
      # (settings.json and the legacy ~/.claude.json both carry
      # hasCompletedOnboarding — claude merges either).
      mkdir -p $out/sandbox/.claude $out/home/agent/.claude
      cp ${claude-settings} $out/sandbox/.claude/settings.json
      cp ${claude-settings} $out/home/agent/.claude/settings.json
      cp ${claude-settings} $out/sandbox/.claude.json
      cp ${claude-settings} $out/home/agent/.claude.json
      ln -s /opt/skills $out/sandbox/.claude/skills
      ln -s /opt/skills $out/home/agent/.claude/skills

      # Agent Skills standard location, scanned by pi and claude-code
      # (and walked as a project-root skill dir from any /sandbox cwd).
      mkdir -p $out/sandbox/.agents $out/home/agent/.agents
      ln -s /opt/skills $out/sandbox/.agents/skills
      ln -s /opt/skills $out/home/agent/.agents/skills

      # Environment briefing baked into every agent's user-level system
      # prompt / memory (see the sandboxContext variants below): pi
      # APPEND_SYSTEM.md and kimi SYSTEM.md add to the agents' system
      # prompts, claude CLAUDE.md is user-level memory loaded every
      # session.
      cp ${sandboxContext-pi} $out/sandbox/.pi/agent/APPEND_SYSTEM.md
      cp ${sandboxContext-pi} $out/home/agent/.pi/agent/APPEND_SYSTEM.md
      cp ${sandboxContext-kimi} $out/sandbox/.kimi-code/SYSTEM.md
      cp ${sandboxContext-kimi} $out/home/agent/.kimi-code/SYSTEM.md
      cp ${sandboxContext-claude} $out/sandbox/.claude/CLAUDE.md
      cp ${sandboxContext-claude} $out/home/agent/.claude/CLAUDE.md
    '';

    # Repo agent material baked read-only at /opt: the merged skills
    # tree (wired into pi/kimi/claude in agentDirs above).
    agentMaterial = pkgs.runCommand "code-agent-material" {} ''
      mkdir -p $out/opt
      cp -r ${skillsTree} $out/opt/skills
    '';

    # pi user settings: the baked skills tree as an explicit resource
    # path (absolute paths are supported; resolves regardless of HOME).
    pi-settings = pkgs.writeText "pi-settings.json" ''
      {
        "skills": ["/opt/skills"]
      }
    '';

    # kimi-code pre-wired for the Kimi for Coding subscription — the
    # same api.kimi.com/coding product pi's built-in kimi-coding provider
    # uses, over the wire Moonshot's own CLI speaks to it (the kimi
    # wire's managed default base URL is exactly .../coding/v1, Bearer
    # auth via apiKeyEnv — the OpenAI-style chat-completions surface,
    # not the Anthropic /messages one). The key is the provider-injected
    # $KIMI_API_KEY, so no /login and no auth.kimi.com egress. If
    # Moonshot ever moves the wire, the Anthropic-protocol variant is
    # type = "anthropic" + baseUrl = "https://api.kimi.com/coding".
    kimi-config = pkgs.writeText "kimi-config.toml" ''
      defaultProvider = "kimi-for-coding"
      defaultModel = "kimi-for-coding"

      [providers.kimi-for-coding]
      type = "kimi"
      baseUrl = "https://api.kimi.com/coding/v1"
      apiKeyEnv = "KIMI_API_KEY"

      [models.kimi-for-coding]
      provider = "kimi-for-coding"
      model = "kimi-for-coding"
      maxContextSize = 1048576
      maxOutputSize = 32768

      [identity]
      name = "code-agent"
      slug = "code-agent"

      # MCP permission rules: the local/offline servers are safe to
      # auto-allow; github MCP can write, so it stays on per-call
      # approval (the default permission mode is manual).
      [[permission.rules]]
      decision = "allow"
      pattern = "mcp__nixos__*"

      [[permission.rules]]
      decision = "allow"
      pattern = "mcp__headroom__*"
    '';

    # github-mcp-server wrapper: the attached github-agent provider
    # injects $GITHUB_TOKEN as an OPAQUE HANDLE (the gateway substitutes
    # the real secret at egress for profile-matched binaries — see
    # openshell/profiles/github-agent.yaml). github-mcp-server reads
    # GITHUB_PERSONAL_ACCESS_TOKEN, so map the handle onto it; nothing
    # secret lands in the image.
    sandboxGithubMcp = pkgs.writeShellScriptBin "github-mcp-server-sandbox" ''
      if [ -z "''${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ] && [ -n "''${GITHUB_TOKEN:-}" ]; then
        export GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN"
      fi
      exec ${lib.getExe pkgs.unstable.github-mcp-server} stdio "$@"
    '';

    # Headroom wrapper: the attached claude-code provider injects the
    # subscription bearer as $ANTHROPIC_AUTH_TOKEN, but headroom's
    # Anthropic client reads ANTHROPIC_API_KEY — map one onto the other
    # so `headroom mcp serve` can compress against api.anthropic.com
    # (already admitted by the policy). headroom-slim (core+proxy+mcp)
    # is enough for the MCP server and keeps the image closure small.
    sandboxHeadroom = pkgs.writeShellScriptBin "headroom" ''
      if [ -z "''${ANTHROPIC_API_KEY:-}" ] && [ -n "''${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        export ANTHROPIC_API_KEY="$ANTHROPIC_AUTH_TOKEN"
      fi
      exec ${lib.getExe pkgs.headroom-slim} "$@"
    '';

    # MCP servers baked into ALL sandbox agents' user configs (pi
    # ~/.pi/agent/mcp.json, kimi ~/.kimi-code/mcp.json, claude
    # ~/.claude/settings.json mcpServers — all three speak the same
    # claude-compatible {command, args} JSON shape): headroom (context
    # compression) and mcp-nixos (NixOS/Home Manager option search)
    # work offline-ish against already-admitted endpoints. github MCP
    # works too — but ONLY when the sandbox is created with the
    # github-agent provider attached (its profile admits the read-write
    # api.github.com endpoints and substitutes the credential at egress;
    # without the provider the server's calls are denied and it errors
    # on startup).
    sandboxMcpServers = {
      headroom = {
        command = "${sandboxHeadroom}/bin/headroom";
        args = ["mcp" "serve"];
      };
      nixos = {
        command = "${inputs'.mcp-nixos.packages.mcp-nixos}/bin/mcp-nixos";
        args = [];
      };
      github = {
        command = "${sandboxGithubMcp}/bin/github-mcp-server-sandbox";
        args = [];
      };
    };

    # Shared user-level mcp.json for kimi-code: same mcpServers table
    # as claude's settings.json (the shape is identical across all
    # three clients), baked at both HOME roots in agentDirs below.
    sandbox-mcp-json = pkgs.writeText "mcp.json" (builtins.toJSON {
      mcpServers = sandboxMcpServers;
    });

    # One-line MCP server descriptions (pi lists them in the system
    # prompt's mcp_servers section and ranks tool_search matches by
    # them).
    sandboxMcpDescriptions = {
      headroom = "Context compression for the conversation: compress/retrieve/stats.";
      nixos = "NixOS, Home Manager and nix-darwin option and package search.";
      github = "GitHub repos, issues, PRs; requires the github-agent provider attached at sandbox creation.";
    };

    # pi's own mcp.json: same servers plus pi-specific exposure and
    # description fields. Pi defaults MCP servers to codemode exposure
    # (tools hidden from the top-level tool list until a codemode
    # script or tool_search reaches them); all three are `direct` so
    # their tools are listed in the system prompt at session start —
    # the agent must SEE the github tools to plan GitHub work. A
    # provider-less github server fails loudly at startup (pi marks the
    # server failed and continues); it never blocks the first prompt.
    pi-mcp-json = pkgs.writeText "pi-mcp.json" (builtins.toJSON {
      mcpServers =
        lib.mapAttrs (
          name: server:
            server
            // {
              exposure = "direct";
              description = sandboxMcpDescriptions.${name};
            }
        )
        sandboxMcpServers;
    });

    # claude MCP servers ride ~/.claude/settings.json mcpServers (NOT
    # ~/.claude.json — that is claude's mutable state file). Onboarding
    # skip keys merge with the server table.
    claude-settings = pkgs.writeText "claude-settings.json" (builtins.toJSON {
      hasCompletedOnboarding = true;
      theme = "dark";
      mcpServers = sandboxMcpServers;
    });

    # pi's built-in kimi-coding provider, pointed at the key the
    # kimi-for-coding OpenShell provider injects as $KIMI_API_KEY.
    pi-models = pkgs.writeText "pi-models.json" ''
      {
        "providers": {
          "kimi-coding": {
            "apiKey": "$KIMI_API_KEY"
          }
        }
      }
    '';

    # Flake revision baked into the briefing's Image line, pinpointing
    # the image generation a sandbox runs. NOTE: flake-parts' self' is
    # the perSystem-narrowed view and carries no sourceInfo — the real
    # self (with shortRev) arrives via inputs.self (shortRev is absent
    # on non-git evals and null on dirty trees).
    imageRev =
      if inputs.self ? shortRev && inputs.self.shortRev != null
      then inputs.self.shortRev
      else "dirty";

    # Search dirs for the nix-ld shim's NIX_LD_LIBRARY_PATH (foreign
    # glibc binaries): the store lib dirs themselves — no FHS copies.
    nixLdLibs = lib.makeLibraryPath [pkgs.glibc pkgs.stdenv.cc.cc.lib pkgs.zlib];

    # Environment briefing baked into every agent's system prompt /
    # memory: what this sandbox is, what works here and what does not.
    # Kept deliberately terse — it is tokens in every session. One
    # parameterized template, three renderings — the per-agent deltas
    # are the identity line and the Agent notes section:
    # - agentName: only kimi interpolates ''${product_name} (from
    #   [identity].name in the baked kimi config below), so pi and
    #   claude get their real product names baked while kimi keeps the
    #   live slot.
    # - notes: short per-agent MCP/diagnostics pointers.
    # Spots: pi ~/.pi/agent/APPEND_SYSTEM.md (adds to Pi's system
    # prompt, pi configuration docs), kimi-code ~/.kimi-code/SYSTEM.md
    # ($KIMI_CODE_HOME/SYSTEM.md, kimi configuration docs), claude-code
    # ~/.claude/CLAUDE.md (user-level memory loaded every session) —
    # at BOTH $HOME roots (the supervisor points HOME at /sandbox,
    # plain docker runs at /home/agent).
    sandboxContext = agentName: notes:
      pkgs.writeText "sandbox-context.md" ''
        # Sandbox environment

        You are ${agentName}, running inside an OpenShell code-agent sandbox: an isolated microVM with deny-by-default network egress, running as uid 1000 (agent), workdir /sandbox, HOME=/home/agent. Image: code-agent @ ${imageRev}.

        ## Toolset
        A full toolset is pre-baked on PATH (/bin, /usr/bin, /usr/local/bin): shell + coreutils, git/gh, curl/wget/jq/yq, python3 + uv, go, ripgrep/fd/sd/tmux/less, which/clear, archive + foreign-ELF tools (file/readelf/objdump/ldd), kubectl/helm, shellcheck/shfmt, nix (+ nixd/alejandra/statix/deadnix), the clan CLI, and the pi/kimi/claude CLIs.

        - Use baked tools directly. NEVER `nix run` or `nix profile install` a package that is already installed.
        - The nix store is single-user and WRITABLE by design
          (`nixUid`/`nixGid` 1000 in the image spec, and the sandbox
          filesystem policy marks /nix read_write): additions through
          nix itself (`nix build`, `nix profile install`, substitutions)
          are normal and expected. Never add or remove store paths
          BEHIND nix's back — raw `cp`/`rm` in /nix/store desyncs the
          db and breaks later nix runs; repair is a sandbox restart.
        - Plain nix builds run at NATIVE speed — the microVM is
          KVM-backed on the host (the repo's `checks.lint` builds here
          in seconds). The hard limits are: no /dev/kvm in the guest
          (NixOS VM tests and nested VMs are CI's job — never
          `nix run .#vm-test`), no `nixos-rebuild`, and FOD/source
          fetches are policy-gated to the admitted hosts. If nix starts
          building a LARGE package from source (llvm/rustc-class), stop
          it — substitute instead; big source builds also eat the 32 GiB
          overlay.
        - nix ALWAYS warns "you don't have Internet access" in this
          sandbox — that is a `getifaddrs()` heuristic (the microVM has
          no routable interface), NOT a network failure. Substitution to
          the admitted caches works: ALWAYS pass `--option substitute
          true` to `nix build` / `nix flake check` here (e.g. `nix build
          --option substitute true .#checks.x86_64-linux.lint -L`).
          Without the override, cache hits degenerate into doomed
          from-source builds (recipe: **sandbox-environment** skill).
        - Flakes evaluate from the GIT TREE: `git add` new/changed files
          BEFORE `nix build` / `nix flake check` — untracked files do
          not exist to Nix.
        - In a nix repo, before declaring work done: `git add` everything
          new, then run the repo's lint loop (`alejandra --check`,
          `statix check`, `deadnix --fail`, or the flake's `checks.lint`
          via `nix build --option substitute true .#checks.<system>.lint
          -L`), then the lightest real build/eval that covers the
          change. Full `nix flake check` is allowed (checks only; VM
          tests are legacyPackages and never part of it) but evaluates
          every output — prefer the targeted gate when iterating.
        - Python: `python3` ships WITHOUT global pip — bootstrap it with
          `python3 -m venv`, or prefer the baked `uv` (wheel-first).
          PyPI (`pypi.org` + `files.pythonhosted.org`) is admitted
          READ-ONLY for python3/uv. Install WHEELS ONLY (`uv pip
          install --only-binary=:all: …`): no C toolchain ships here,
          so sdists that compile cannot build in-sandbox — get those
          via nix substitution (`nix run --option substitute true
          nixpkgs#…`). Binary wheels import as-is: the few system libs
          they link (libstdc++/libgcc_s/libz) resolve from the baked
          /usr/lib/wheel-deps dir (on LD_LIBRARY_PATH).
        - Foreign glibc binaries (downloaded FHS ELFs) run via the
          nix-ld shim: /lib64/ld-linux-x86-64.so.2 reads NIX_LD and
          NIX_LD_LIBRARY_PATH from the env.
        - Do NOT run the NixOS VM tests (`nix run .#vm-test`): they need /dev/kvm, which the guest does not have. VM tests are CI's job — flag the gap rather than running them.

        ## MCP servers
        Pre-configured in every agent's user-level MCP config (pi ~/.pi/agent/mcp.json, kimi ~/.kimi-code/mcp.json, claude ~/.claude/settings.json): **headroom** (context compression), **nixos** (NixOS / Home Manager option search), **github** (repos / issues / PRs — only functional when the sandbox was created with the github-agent provider attached). There is deliberately NO kubernetes MCP server; use kubectl/helm directly.

        ## Skills
        /opt/skills holds the repo's merged skill tree (repo skills/ + external sources), wired into pi, kimi and claude. Load with /skill:<name>; read a SKILL.md before relying on a skill. The **sandbox-environment** skill carries this sandbox's deep reference (full egress list, cache keys, recipes).

        ## Network
        Egress is deny-by-default and matches (binary, host) PAIRS. Admitted: github.com (read + api), the nix cache estates (*.nixos.org, *.cachix.org, clan's cache.geninf.io/cache.clan.lol), flake-input hosts for nix/git fetches (git.clan.lol read-write, code.m3ta.dev read-only, api.flakehub.io/api.flakehub.com, files.pythonhosted.org for the headroom wheel input), PyPI (pypi.org + files.pythonhosted.org) for python3/uv, the Go module proxy + checksum db (proxy.golang.org/sum.golang.org) for go, api.kimi.com, api.anthropic.com, platform.claude.com. A host admitted for ONE binary is not admitted for others (e.g. PyPI is python3/uv-only; curl is refused). Everything else is DENIED — do not retry dead hosts in a loop; report the blocked host. Full host/rule list: **sandbox-environment** skill.

        ## Identity and secrets
        - Git commits are authored as the andrewthomaslee-agent bot.
        - No secrets are baked into the image. API keys arrive via attached providers: $KIMI_API_KEY (kimi), $ANTHROPIC_AUTH_TOKEN (claude), $GITHUB_TOKEN (git credential helper).
        - This is a clean sandbox, NOT a checkout of the home repo — clone github.com/external-systems/home if repo work is needed.

        ## Troubleshooting
        - github MCP errors at startup → the sandbox was created without the github-agent provider attached; headroom/nixos are unaffected.
        - nix starts building a package from source → stop it; use the baked tool (or a substituter key is missing — report it).
        - A host is DENIED → report it instead of retrying; the policy hot-reloads (`openshell policy set` from the host), no sandbox recreation needed. Host-side diagnosis: `openshell logs <sandbox> --source sandbox | grep -iE 'denied|reject|block|forbidden'` (plain `openshell logs <name>` is flooded by known upstream supervisor ssh WARNs — `data on unknown channel` — ignore those).
        - An admitted-LOOKING host refusing connections instantly (`Could not connect to server`) usually means the (binary, host) PAIR is missing from the policy, not a network failure — and the deny log is not authoritative (observed 2026-10: nix→files.pythonhosted.org refused with NO deny line; that host was admitted only for python3/uv, fixed in this policy revision). Check the pair against the sandbox's composed policy from the host before concluding drift. Rare one-off refuses on genuinely admitted pairs (observed once for nix→github.com) are proxy-level flakes: retry once or twice (self-recovers within minutes), then report.
        - `error: killing process ...: Operation not permitted` during nix builds is the supervisor's seccomp blocking nix→builder signals — cosmetic; the build result stands.
        - `ls /` fails (EACCES): the sandbox filesystem policy marks /bin /usr /lib /lib64 /etc /opt /proc read_only and /sandbox /tmp /nix /home read_write, and `/` itself is in neither list — deny by default, so it cannot be listed. Every real path below it works normally.

        ## Agent notes

        ${notes}
      '';

    sandboxContext-pi = sandboxContext "pi" "- MCP exposure: all three servers are `direct` — their tools are listed in the system prompt at session start; the github server still needs the github-agent provider attached to answer calls. Diagnose servers with `pi mcp list`; add project-only servers with `pi mcp add -l <name> -- <cmd>`.";

    sandboxContext-kimi = sandboxContext "\${product_name}" "- Inspect MCP connections with `/mcp`. Pre-approved by baked permission rules: mcp__nixos__* and mcp__headroom__*; mcp__github__* asks per call — approve for the session only when doing GitHub work.";

    sandboxContext-claude = sandboxContext "Claude Code" "- Inspect MCP connections with `/mcp`. Servers ride the baked ~/.claude/settings.json mcpServers table; ~/.claude.json is claude's mutable state file and stays writable.";

    tmpDir = pkgs.runCommand "code-agent-tmp" {} "mkdir -p $out/tmp";

    # Multiline nix config: flakes on; the microVM is the isolation
    # boundary and the OpenShell supervisor's seccomp stack blocks nix's
    # builder-child filter ("unable to load seccomp BPF program:
    # Operation not permitted"), so builders skip their own filter.
    # Substituters: the repo's own cachix caches (openshell — this
    # flake's closure — plus devenv/nix-community/chaotic-nyx,
    # mirroring flake.nix's nixConfig minus cache.numtide.com, whose
    # host the sandbox policy does not admit) and clan-core's niks3
    # cache (cache.geninf.io; objects may be signed under either
    # cache.geninf.io-1 or cache.clan.lol-1, so both keys are trusted —
    # keys verbatim from the cache's own usage page). The FlakeHub
    # binary caches were dropped: they answer nix-cache-info with 401
    # Unauthorized anonymously, so they were dead substituters adding
    # warning noise to every nix invocation (api.flakehub.io stays
    # admitted in the sandbox policy for flakehub: inputs — verified
    # 401-in-sandbox, 2026-10). Baked at BOTH /etc/nix/nix.conf (rootfs
    # below) and $NIX_CONFIG (image Env below). NOTE (verified live
    # 2026-10): the supervisor does NOT pass the image Env's NIX_CONFIG
    # through to the sandbox process env — it rewrites Env wholesale
    # (SSL_CERT_FILE arrives pointed at the supervisor CA bundle), so
    # /etc/nix/nix.conf is the ONLY copy guaranteed in effect under
    # OpenShell; $NIX_CONFIG remains for plain docker runs.
    nixConfig = lib.concatStringsSep "\n" [
      "experimental-features = nix-command flakes"
      "sandbox = false"
      "filter-syscalls = false"
      # The gateway proxy occasionally refuses an admitted (binary, host)
      # pair with an instant "Could not connect to server" that
      # self-recovers within a minute (observed 2026-10 for
      # nix→github.com input tarballs). Retry downloads and allow a
      # sane connect window so these flakes self-heal instead of
      # failing the eval.
      "connect-timeout = 10"
      "download-attempts = 3"
      "extra-substituters = https://openshell.cachix.org/ https://devenv.cachix.org/ https://nix-community.cachix.org/ https://chaotic-nyx.cachix.org/ https://cache.geninf.io/"
      "extra-trusted-public-keys = openshell.cachix.org-1:OAr5MunsfH5PZvUsfD08OtGx5RtcwdNZGJdU5FqLm5w= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n8ae7W70yP3m9y9633ndgliTLGsQI= cache.geninf.io-1:uhEViaczNKSoerYM+w7uqXUzlAhnbEBKsFzgg9n3cvI= cache.clan.lol-1:3KztgSAB5R1M+Dz7vzkBGzXdodizbgLXGXKXlcQLA28="
    ];
  in {
    packages.code-agent-image = n2c.buildImage {
      name = "code-agent";
      tag = "latest";

      copyToRoot = [baseTools rootfs agentDirs agentMaterial tmpDir];

      # Register the image store paths in the nix db at build time so
      # `nix` works in-sandbox without a db init.
      initializeNixDatabase = true;
      nixUid = 1000;
      nixGid = 1000;

      maxLayers = 128;

      perms = [
        {
          path = agentDirs;
          regex = ".*";
          # nix store defaults are 0555; without an explicit mode the
          # workdir would be read-only for the runtime user.
          mode = "0755";
          uid = 1000;
          gid = 1000;
          uname = "agent";
          gname = "agent";
        }
        {
          path = tmpDir;
          regex = "/tmp";
          mode = "1777";
          uid = 0;
          gid = 0;
          uname = "root";
          gname = "root";
        }
      ];

      config = {
        User = "agent";
        WorkingDir = "/sandbox";
        Env = [
          "HOME=/home/agent"
          "NIX_CONFIG=${nixConfig}"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          # pi defaults to the kimi-for-coding subscription endpoint; the
          # key itself is injected by the attached kimi-for-coding
          # provider (models.json above reads it from $KIMI_API_KEY).
          "PI_PROVIDER=kimi-coding"
          "PI_MODEL=kimi-for-coding"
          # kimi-code: no models.dev catalog fetch on start (no catalog
          # egress under the sandbox policy — the provider/model is
          # baked in config.toml) and no telemetry.
          "KIMI_CODE_MODEL_CATALOG_REFRESH_ON_START=false"
          "KIMI_DISABLE_TELEMETRY=1"
          # claude-code: updater/telemetry/error-reporting/survey traffic
          # all targets hosts the policy does not admit; disabling keeps
          # the DENIED log to real API traffic. (The startup connectivity
          # preflight is NOT telemetry — platform.claude.com is admitted
          # in openshell/policies/code-agent.yaml for it and for
          # `claude auth login` token polling.)
          "DISABLE_AUTOUPDATER=1"
          "DISABLE_TELEMETRY=1"
          "DISABLE_ERROR_REPORTING=1"
          "DISABLE_BUG_COMMAND=1"
          "DISABLE_GROWTHBOOK=1"
          "DISABLE_FEEDBACK_SURVEY=1"
          # Foreign-glibc + manylinux-wheel runtime (see rootfs): the
          # nix-ld shim at /lib64/ld-linux-x86-64.so.2 reads NIX_LD /
          # NIX_LD_LIBRARY_PATH when a downloaded FHS binary execs, and
          # python wheel extensions resolve libstdc++/libgcc_s/libz from
          # the scoped wheel-deps dir. Deliberately narrow: a broader
          # LD_LIBRARY_PATH would shadow nix store RUNPATHs
          # process-wide (search order puts it before DT_RUNPATH).
          "LD_LIBRARY_PATH=/usr/lib/wheel-deps"
          "NIX_LD=${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
          "NIX_LD_LIBRARY_PATH=${nixLdLibs}"
        ];
        Cmd = ["${pkgs.bashInteractive}/bin/bash" "-l"];
      };
    };

    # The nix2container image is an image-spec JSON, not a loadable
    # tarball: copy it into the host docker store (where the VM driver
    # resolves images first) with skopeo. Registry pull is the fallback.
    apps.load-code-agent-image = {
      type = "app";
      program = toString (pkgs.writeShellScript "load-code-agent-image" ''
        set -euo pipefail
        exec ${inputs'.nix2container.packages.skopeo-nix2container}/bin/skopeo --insecure-policy \
          copy "nix:${self'.packages.code-agent-image}" docker-daemon:code-agent:latest
      '');
    };
  };
}
