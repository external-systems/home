# euc-hel-0 — Hetzner Robot bare metal (Xeon W-2295, 2x PM983 960G NVMe,
# 2x PM883 480G SATA; see facter.json). Formerly borg's
# helsinki-manager-1, reinstalled into this fleet as the remote builder
# and CI build box (clanServices/remote-builder, inventory.nix).
#
# disko.nix (install-time truth) and facter.json are carried over from
# borg unchanged.
{secrets, ...}: {
  hostSpec.networking.shim = let
    # Still keyed by the old machine name in the values flakes (see
    # inventory.nix).
    inherit (secrets.hosts.euc-hel-0.links) public;
    network = secrets.networks.${public.network};
  in {
    enabled = true;
    mode = "static";
    inherit (public) interface ipv4 ipv6;
    gateway4 = network.ipv4.gateway;
    # fe80::1 on Robot: link-local, bound to the interface by the shim.
    gateway6 = network.ipv6.gateway;
  };

  # Root is a thin LV (disko.nix): the initrd needs the thin-pool tools,
  # and discards keep the pools from filling up.
  services = {
    lvm.boot.thin.enable = true;
    fstrim.enable = true;
  };
}
