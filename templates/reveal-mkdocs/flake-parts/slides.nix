{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # reveal.js' prebuilt files (reveal.js, reveal.css, theme/, plugin/).
    reveal = "${inputs.reveal-js}/dist";
  in {
    # nix build .#slides → ./result is the static slide deck: the files in
    # slides/ plus reveal.js under reveal/ (index.html links reveal/...).
    packages.slides = pkgs.runCommand "slides" {} ''
      mkdir -p $out
      cp -r ${../slides}/. $out/
      cp -r ${reveal} $out/reveal
    '';

    # nix run .#serve-slides → http://127.0.0.1:8000
    # Serves slides/ straight from your checkout, so edits show up on a
    # browser refresh. A web server is needed because browsers refuse to
    # load slides.md from a file:// page. Run it from the repo root.
    apps.serve-slides = {
      type = "app";
      program = lib.getExe (pkgs.writeShellApplication {
        name = "serve-slides";
        runtimeInputs = [pkgs.python3];
        text = ''
          if [ ! -d slides ]; then
            echo "No slides/ folder here — run this from the repository root." >&2
            exit 1
          fi
          root=$(mktemp -d)
          trap 'rm -rf "$root"' EXIT
          ln -s ${reveal} "$root/reveal"
          for f in "$PWD"/slides/*; do ln -s "$f" "$root/"; done
          port="''${1:-8000}"
          echo "Slides on http://127.0.0.1:$port — edit slides/slides.md, then refresh."
          python3 -m http.server --bind 127.0.0.1 --directory "$root" "$port"
        '';
      });
      meta.description = "Serve slides/ with reveal.js on localhost for live editing.";
    };
  };
}
