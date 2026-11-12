# Machines

Every machine in the clan, what it is for, who uses it and what is
loaded on it. What a machine runs comes from three places: its tags in
`inventory.nix` (machine type, purpose, users), each user's profile in
`users/<user>/`, and the few things only that machine has in
`machines/<machine>/configuration.nix`. Hardware is detected from
`machines/<machine>/facter.json`. How tags and networking work in
general: [Machines and networking](../fleet/index.md).

| Machine | What it is | Users | Tags |
| --- | --- | --- | --- |
| [beelink](beelink.md) | shared developer mini PC | netsa, matt | `pc` `dev` |
| [kamrui-h1](kamrui-h1.md) | gaming and developer desktop | netsa, wife | `pc` `dev` `gaming` |
| [nixos](nixos.md) | old gaming desktop, to become a server | netsa, wife | `pc` `dev` `gaming` |
| [ghost](ghost.md) | netsa's developer laptop | netsa | `pc` `dev` |
| [hp-notebook](hp-notebook.md) | wife's laptop | wife | `pc` |
| [euc-hel-0](euc-hel-0.md) | remote builder and CI build box (Hetzner) | root only | `server` |

## What the tags load

**Every machine** (`machine-type` service): clan, the nix daemon
settings and trusted caches, OpenSSH, the login message, network tuning
(BBR, socket buffers, irqbalance), a 1 GiB journal cap, and `root`.

| Tag | Loads |
| --- | --- |
| `pc` | KDE Plasma on Wayland, sound, Bluetooth when present, 1Password (for the machine's desktop users), the Tailscale tray, the desktop apps (Zen browser, Discord, Spotify, Obsidian, Prism Launcher, Tor Browser, KDE utilities), and the remote-builder client: builds go to euc-hel-0 |
| `server` | headless: no desktop or graphics; a `pc` or `gaming` tag on a server fails to evaluate |
| `dev` | developer workstation: Docker, nix-ld, the shared dev apps (Kubernetes and database GUIs, python3) |
| `gaming` | jovian: Steam on the KDE desktop with GE-Proton, a "gaming" boot entry into Steam Gaming Mode and a "developer" entry with the normal kernel; Steam sharing: every user keeps a Steam library of their own, `sudo steam-copy-game` copies a game to another user and shader caches are synced (per-machine settings in `inventory.nix`) |
| `netsa`, `wife`, `matt` | that user's account and home-manager profile |

## What the users load

| User | Profile (`users/<user>/default.nix`) |
| --- | --- |
| netsa | the full developer set: AI coding agents (Claude Code, pi, kimi, opencode) with every skill, the headroom proxy, Docker, VSCodium with every language and the cluster tooling, Ghostty, git with a clan-generated signing key, the Storage Box mount, media apps, office and Plasma settings |
| matt | netsa-lite: Claude Code and pi with every skill, the headroom proxy, Docker, VSCodium with large, readable fonts, Ghostty, git, office and Plasma settings |
| wife | a desktop: Firefox, media apps, Plasma settings |

## Deploying

From the devenv shell (it provides the token for the private values
flake): `clan machines update <machine>`. Builds run on euc-hel-0.

New or changed clan vars come first, on a branch: `clan vars generate`
commits to the current branch, and `main` takes PRs only.

```sh
git switch main && git pull
git switch -c vars-<machine>-<topic>
clan vars generate <machine>        # commits the new vars here
git push -u origin HEAD             # then open a PR and merge it
git switch main && git pull
clan machines update <machine>      # vars are on main: nothing to commit
```
