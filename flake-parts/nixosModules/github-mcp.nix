_: {
  # ------ NixOS Modules ------ #
  # Self-configuring GitHub MCP support. All user-facing options live under
  # homeSpec.agents.mcp.github (homeModules/agents.nix) — this module has
  # none of its own. The github MCP server is wired as a local stdio PAT
  # wrapper for pi/kimi/claude ALWAYS (they can't run opencode's browser
  # OAuth flow from a file config), and for opencode when
  # mcp.github.auth = "pat". So for every home-manager user whose agents
  # config has mcp.github.enable AND (any of pi/kimi/claude enabled OR
  # opencode pat-mode), it declares the clan vars generator provisioning
  # the PAT; sops-nix deploys it to
  #   /run/secrets/vars/shared/github-mcp/pat
  # (owner = user, mode 0400, neededFor = services), where the wrapper
  # picks it up at MCP server start.
  #
  # Provisioning (interactive, no fake values in the repo):
  #   clan vars set github-mcp pat <machine>   (or: clan vars generate)
  #
  # NOTE: this scan mirrors the option paths in homeModules/agents.nix by
  # hand (defensive `or` access to avoid fixpoint recursion). If you rename
  # or restructure those options, update BOTH places — a stale scan
  # silently stops declaring the generator (regression seen when the mcp
  # namespace moved from homeSpec.agents.opencode.mcp to the shared
  # homeSpec.agents.mcp: the scan kept reading opencode.mcp, found nothing,
  # and no PAT was ever provisioned).
  #
  # NOTE: assumes at most one pat-mode user per machine (shared generator);
  # conflicting owners would fail the merge at eval time.
  flake.nixosModules.github-mcp = {
    config,
    lib,
    ...
  }: {
    # Read-only scan of home-manager.users (attrsOf hmModule submodule —
    # merged option values, mkIf flattened). The module never writes to
    # home-manager.users, so no fixpoint recursion is possible.
    config.clan.core.vars.generators = lib.mkMerge (
      lib.mapAttrsToList
      (
        userName: hmUser: let
          agents = hmUser.homeSpec.agents or {};
          gh = (agents.mcp or {}).github or {};
          # pi/kimi/claude always get the local PAT wrapper; opencode only
          # with auth = "pat".
          patConsumer =
            (agents.pi.enabled or false)
            || (agents.kimi.enabled or false)
            || (agents.claude.enabled or false)
            || (((agents.opencode or {}).enabled or false) && ((gh.auth or "oauth") == "pat"));
        in
          lib.mkIf ((gh.enable or false) && patConsumer)
          {
            github-mcp = {
              share = true;
              prompts.pat = {
                persist = true;
                type = "hidden";
                description = "GitHub Personal Access Token for github-mcp-server";
              };
              files.pat = {
                owner = userName;
                mode = "0400";
                neededFor = "services";
              };
            };
          }
      )
      config.home-manager.users
    );
  };
}
