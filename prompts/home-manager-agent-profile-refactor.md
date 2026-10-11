# AI Prompt: Refactor the code-agent OCI image to bake a home-manager profile for the agent user

> Paste this whole file into a coding agent (pi / kimi / claude) working on a
> checkout of `github.com/external-systems/home`. It is self-contained:
> context, constraints, the proven mechanism, the step-by-step plan, and the
> verification gates. Work on a branch; run the gates; commit.

## Mission

Replace the hand-written shell dotfiles in the OpenShell `code-agent` sandbox
OCI image with a **baked home-manager evaluation** for the `agent` user
(uid 1000). Home-manager is used strictly as a **dotfile + user-package-set
generator at image-build time** — no activation, no systemd, no runtime
`home-manager switch`. Keep the profile MINIMAL.

Non-goals: do not convert the image to a nixosConfiguration (evaluated and
rejected — the sandbox never boots NixOS: no systemd PID 1, no activation
pass, identity must be statically baked uid 1000, and the supervisor
scrubs/rebuilds the process environment itself). Do not add the home-manager
CLI as a runtime mechanism (HOME duality makes runtime activation write to
the wrong root; substitution-only nix makes it fragile).

## Repo map (what you will touch)

- `flake-parts/ociImages/code-agent.nix` — the image (nix2container). The
  ONLY place sandbox images come from.
- `flake-parts/homeModules/profiles/` — per-user HM profiles
  (`netsa.nix`, `root.nix`, `wife.nix`). You will add `agent.nix` here.
  NOTE: `flake-parts/homeModules/default.nix` auto-imports everything EXCEPT
  `profile-*`; profiles are composed explicitly.
- `users/<name>/default.nix` shows how hosts wire a profile:
  `home-manager.users.netsa = self.homeModules.profile-netsa;` — the sandbox
  will NOT use this path (no NixOS host); it evaluates HM standalone instead.
- `documentation/docs/openshell/code-agent-image.md` — user guide; has a
  "Remote access: SSH, VSCodium, VS Code" section that documents the env
  model. Update it if the mechanism description changes.

## The sandbox runtime contract (hard constraints — verified from the
## OpenShell supervisor source, openshell-sandbox boundary_exec.rs and
## openshell-supervisor-process ssh.rs)

1. There is NO OpenSSH sshd in the sandbox. The supervisor speaks ssh itself
   and spawns EVERY process with `env_clear()`: only `HOME`/`USER`/`PATH`
   (default `/usr/local/bin:/usr/bin:/bin`)/`TERM`/`SHELL` plus injected TLS
   vars (`SSL_CERT_FILE`, `GIT_SSL_CAINFO`, …) and attached provider
   credentials survive. The OCI image `Env` does NOT propagate under the VM
   driver.
2. Interactive ssh/editor-terminal sessions are `bash -i` — a NON-login
   shell that reads ONLY `~/.bashrc`. Remote commands and editor server
   bootstraps are `bash -lc` — login shell, reads `/etc/profile`.
3. The supervisor sets `HOME=/sandbox` (the workdir). Plain docker runs use
   `HOME=/home/agent`. BOTH roots must carry the dotfiles.
4. `--include-workdir` sandboxes mount a host directory OVER `/sandbox`,
   hiding its dotfiles. The env channel that still applies then is the
   create-time `--env` set (`packages.code-agent-env`, passed by
   `code-sandbox create` — `lib/mkCodeSandbox.nix`, parameter `envAttr`).
5. Client `TERM` arrives verbatim via the ssh pty request; the image bakes
   a merged ncurses+ghostty terminfo db (`terminfoDb` in the image module)
   at `/usr/share/terminfo` and exports `TERMINFO_DIRS` from every channel.

These three env channels already exist and MUST keep working:
`/etc/profile` (idempotent, POSIX-safe), baked `~/.bashrc` at both roots,
and `packages.code-agent-env`. Home-manager REPLACES the hand-written
dotfiles (channel 2); it must not break channels 1 and 3.

## The proven mechanism (already verified in-sandbox against this repo's pins)

Standalone HM evaluation works and produces a bakeable tree:

```nix
# inputs.home-manager is the repo's pinned home-manager input
hmAgent = inputs'.home-manager.lib.homeManagerConfiguration # or inputs.home-manager.lib
  {
    inherit pkgs;            # the perSystem pkgs (repo overlays applied)
    modules = [agentProfile];
  };
# Build products:
#   hmAgent.activationPackage + "/home-files"  → .bashrc, .bash_profile,
#                                                .profile, .config/git/, ...
#   hmAgent.activationPackage + "/home-path"   → bin/<user packages>
```

The HM module MUST disable docs/news (the manpage derivation build fails
under the in-sandbox FS policy, and the image needs files, not manuals):

```nix
manual.manpages.enable = false;
manual.html.enable = false;
manual.json.enable = false;
news.display = "silent";
```

## Step-by-step plan

1. **Create `flake-parts/homeModules/profiles/agent.nix`** — a MINIMAL
   home-manager module:

   ```nix
   _: {
     flake.homeModules.profile-agent = {pkgs, ...}: {
       home = {
         username = "agent";
         homeDirectory = "/home/agent";
         stateVersion = "25.11"; # pin to the HM input's release
       };
       manual.manpages.enable = false;
       manual.html.enable = false;
       manual.json.enable = false;
       news.display = "silent";

       programs.bash = {
         enable = true;
         # LOAD-BEARING: interactive ssh sessions are `bash -i` and read
         # ONLY ~/.bashrc. HM's own init does not source /etc/profile, so
         # do it here — /etc/profile is idempotent and POSIX-safe.
         initExtra = ''
           if [ -r /etc/profile ]; then
             . /etc/profile
           fi
           # TERM fallback: ssh forwards the client's TERM verbatim; fall
           # back when it has no entry in the baked terminfo db.
           if [ -n "''${TERM:-}" ] && ! infocmp "$TERM" >/dev/null 2>&1; then
             export TERM=xterm-256color
           fi
           # Unmistakable sandbox prompt (disposable microVM, not the host).
           PS1='\[\e[1;35m\][sandbox]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\]\$ '
         '';
         shellAliases = {
           ll = "ls -alF --color=auto";
           la = "ls -A --color=auto";
           l = "ls -CF --color=auto";
           grep = "grep --color=auto";
           # nix's getifaddrs heuristic disables substitution in the
           # microVM; force it back on for interactive use.
           nix = "nix --option substitute true";
         };
         historyControl = ["ignoreboth" "erasedups"];
         historySize = 10000;
         historyFileSize = 20000;
       };
       # Keep it minimal: NO git module (the image already bakes
       # /etc/gitconfig with the bot identity + credential helper),
       # NO systemd-user anything, NO sops-nix, NO sessionVariables that
       # duplicate /etc/profile.
     };
   }
   ```

2. **Evaluate + bake in `flake-parts/ociImages/code-agent.nix`:**

   ```nix
   hmAgent = inputs'.home-manager.lib.homeManagerConfiguration {
     inherit pkgs;
     modules = [self'.homeModules.profile-agent];
   };
   ```

   (Check how the module file accesses `self'`/`inputs'` — the perSystem
   scope in `code-agent.nix` already takes `inputs', self', pkgs, customLib`.
   home-manager's flake lib is at `inputs.home-manager.lib` — verify the
   attr path with `nix eval` before wiring.)

   Then in the `agentDirs` runCommand, replace the `cp ${agentBashrc} …` /
   `cp ${agentBashProfile} …` lines with:

   ```sh
   cp -rL ${hmAgent.activationPackage}/home-files/. $out/home/agent/
   cp -rL ${hmAgent.activationPackage}/home-files/. $out/sandbox/
   ```

   (`-L` dereferences the HM store symlinks into real files — the image
   layer stays self-contained and the perms block can own them 1000:1000.)

   Delete the now-dead `agentBashrc`/`agentBashProfile` let-bindings.

3. **Inspect the generated home-files for absolute `/home/agent`
   embedding.** HM output is mostly store paths (safe under the HOME
   duality), but some modules embed `homeDirectory` literally. List what
   references `/home/agent` and decide per hit: harmless (comments),
   fixable (module config), or accept-and-document. Do NOT evaluate HM
   twice to fix this — one eval, copied to both roots.

4. **Do NOT touch:** `terminfoDb`, `/etc/profile`, `packages.code-agent-env`,
   the image `Env`, `lib/mkCodeSandbox.nix` (the `--env` channel), the
   vscodium-server bake, and the policy templates. HM replaces dotfiles only.

5. **Decide about `home-path`.** If the profile gains user packages later,
   merge `hmAgent.activationPackage + "/home-path"` into `baseTools`' `paths`
   (it is a buildEnv). For the MINIMAL first refactor (bash only, no extra
   packages) skip it — but leave a comment noting where it plugs in.

6. **Docs.** Update `documentation/docs/openshell/code-agent-image.md`
   ("Shell dotfiles + full terminfo" bullet and the Remote access env-model
   table) to say the dotfiles come from the baked `profile-agent` HM eval,
   and note the profile location. Add a bullet to the module header comment
   in `code-agent.nix`.

## Verification gates (all mandatory; run from the repo root)

1. `git add -A` (flakes evaluate from the git tree).
2. `alejandra . && statix check . && deadnix --fail .` (or
   `nix build --option substitute true .#checks.x86_64-linux.lint -L`).
3. `nix build --option substitute true .#code-agent-image --no-link` —
   then inspect the image JSON: `home-files` present in an agentDirs layer,
   `.bashrc` exists at both roots, and `grep` the baked `.bashrc` for the
   `/etc/profile` source line.
4. Scrubbed-env simulation (the supervisor model), using the store paths
   from the fresh image JSON:
   `env -i HOME=<tmp with baked .bashrc> PATH=/usr/local/bin:/usr/bin:/bin TERM=xterm-ghostty bash -i -c '…'`
   → assert `NIX_LD`, `LD_LIBRARY_PATH`, `TERMINFO_DIRS` are set and TERM
   survived as `xterm-ghostty` (terminfo resolves).
5. shellcheck the HM-generated `.bashrc`/`.bash_profile`/`.profile` from
   the store (warnings about HM's own idioms are acceptable; errors are not).
6. `nix build --option substitute true .#code-agent-env .#code-agent-policy
   .#code-sandbox --no-link` — regression check on the untouched channels.
7. `nix build .#documentation` is allowed to fail in-sandbox at plantuml
   (gradle daemon socket bind is policy-denied — PRE-EXISTING, flag it,
   don't fix it here).

## Acceptance criteria

- `bash -i` with a scrubbed env recovers the full environment via the
  HM-generated `.bashrc` at BOTH `/home/agent` and `/sandbox`.
- `bash -lc` (login) still works via `/etc/profile` alone.
- No HM docs/news/systemd artifacts in the image closure.
- Image briefing/comments/docs describe the HM mechanism accurately.
- One commit, conventional style, authored as the repo's bot identity,
  after all gates pass.

## Host prerequisite (if running this OUTSIDE the existing dev setup)

Install the OpenShell CLI (upstream install script; `OPENSHELL_VERSION`
pins a release tag, unset = latest):

```sh
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
```

Day-to-day sandbox lifecycle is `code-sandbox` (baked wrapper from this
flake — see `documentation/docs/openshell/code-sandbox.md`); the refactor
itself only needs `nix`, `git`, and the lint trio.
