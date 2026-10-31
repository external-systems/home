# One nixpkgs for every machine: the org pin (inputs.nixpkgs follows
# org-pkgs/nixpkgs) with the org overlay (headroom, kimi-code,
# kubernetes-mcp-server, ... from external-systems/pkgs). No
# pkgs.unstable: the pin is nixos-unstable already.
{
  inputs,
  lib,
  ...
}: {
  flake.nixosModules.nixpkgs = {
    nixpkgs = {
      overlays = [inputs.org-pkgs.overlays.default];
      config.allowUnfree = lib.mkDefault true;
    };
  };
}
