_: {
  # Large hardware on fast, long paths: generous socket buffer ceiling
  # (module default 32 MiB).
  hostSpec.networking.optimization.bufferMax = 134217728; # 128 MiB
}
