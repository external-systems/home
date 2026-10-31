_: {
  # WiFi via NetworkManager (DHCP) until netif lands.
  hostSpec.networking.shim = {
    enabled = true;
    mode = "wifi";
  };
}
