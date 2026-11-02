_: {
  hostSpec.networking = {
    # WiFi via NetworkManager (DHCP) until netif lands.
    shim = {
      enabled = true;
      mode = "wifi";
    };
    # Large hardware on fast, long paths: generous socket buffer ceiling
    # (module default 32 MiB).
    optimization.bufferMax = 134217728; # 128 MiB
  };
}
