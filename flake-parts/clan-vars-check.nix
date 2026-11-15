# checks.clan-vars-present: every var each machine's generators declare is
# committed under vars/, so a PR with missing vars cannot merge (CI runs
# only `nix flake check`). Missing vars matter because clan's sops wiring
# skips them silently (clan-core generators-to-sops.nix filters on
# pathExists): eval, build and CI pass, and the first `clan machines
# update` generates them and commits them to whatever branch is checked
# out, main included. Shared secrets deployed to a machine also need its
# machines/<m> link. Needs no key: it looks at paths only. The devenv
# `check` also runs `clan vars check` (validation hashes, recipients).
{
  self,
  lib,
  ...
}: let
  varsDir = "${self}/vars";
  missingFor = machine: nixos:
    lib.concatLists (lib.mapAttrsToList (
        generator: gen:
          lib.concatLists (lib.mapAttrsToList (
              file: f: let
                dir =
                  if gen.share
                  then "${varsDir}/shared/${generator}/${file}"
                  else "${varsDir}/per-machine/${machine}/${generator}/${file}";
                present = builtins.pathExists "${dir}/${
                  if f.secret
                  then "secret"
                  else "value"
                }";
                needsAccess = gen.share && f.secret && f.deploy;
              in
                lib.optional (!present) "${machine}: ${generator}/${file}"
                ++ lib.optional (present && needsAccess && !builtins.pathExists "${dir}/machines/${machine}") "${machine}: ${generator}/${file} (no access for ${machine})"
            )
            gen.files)
      )
      nixos.config.clan.core.vars.generators);
  missing = lib.concatLists (lib.mapAttrsToList missingFor self.nixosConfigurations);
in {
  perSystem = {pkgs, ...}: {
    checks.clan-vars-present = pkgs.runCommand "clan-vars-present" {} (
      if missing == []
      then "touch $out"
      else ''
        echo "Missing clan vars (generate them on a branch, never on main):" >&2
        ${lib.concatMapStrings (m: "echo ${lib.escapeShellArg "  - ${m}"} >&2\n") missing}
        echo "Fix: worktree new vars-<machine>-<topic>; cd there; clan vars generate <machine>; push and open a PR." >&2
        exit 1
      ''
    );
  };
}
