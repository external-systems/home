# Full-size desktop wallpapers are kept as-is; sizelint's 2 MB cap is
# meant for code and generated files.
{
  perSystem.treefmt.settings.formatter.sizelint.excludes = [
    "documentation/docs/assets/wallpapers/*"
  ];
}
