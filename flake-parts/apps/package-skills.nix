_: {
  perSystem = {
    pkgs,
    lib,
    customLib,
    ...
  }: let
    package-skills = pkgs.writeShellApplication {
      name = "package-skills";
      runtimeInputs = with pkgs; [
        coreutils
        zip
        (python3.withPackages (ps: [ps.pyyaml]))
      ];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "Usage: package-skills OUTPUT_DIR" >&2
          exit 2
        fi

        output=$(realpath -m -- "$1")
        if [ -e "$output" ] || [ -L "$output" ]; then
          echo "package-skills: output path already exists: $output" >&2
          exit 1
        fi

        skills=${customLib.relativeToRoot "skills"}
        python3 ${customLib.relativeToRoot "lib/check-skill-metadata.py"} "$skills"
        mkdir -p -- "$output"

        for skill_dir in "$skills"/*; do
          if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            skill=$(basename "$skill_dir")
            (cd "$skills" && zip -q -r "$output/$skill.zip" "$skill")
          fi
        done

        printf 'Created skill archives in %s\n' "$output"
      '';
    };
  in {
    apps.package-skills = {
      type = "app";
      program = lib.getExe package-skills;
      meta.description = "Package each skill directory into its own ZIP archive";
    };
  };
}
