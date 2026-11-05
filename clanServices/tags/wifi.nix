{
  # WiFi via NetworkManager (DHCP) until netif lands. Wired machines with
  # static addresses set the shim in their own configuration.nix.
  hostSpec.networking.shim = {
    enabled = true;
    mode = "wifi";
  };
}
