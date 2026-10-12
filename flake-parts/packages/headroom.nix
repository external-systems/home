{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    py = pkgs.unstable.python313Packages;

    # Runtime deps for `headroom-ai[all]` (= proxy,code,ml,memory,relevance,
    # image,reports,otel,evals,voice,html,mcp,spreadsheet). All are available
    # in nixpkgs python313Packages, so we only build the headroom wheel itself
    # and propagate these pre-built dependencies.
    allDeps = with py; [
      # --- core ---
      tiktoken
      pydantic
      litellm
      click
      rich
      opentelemetry-api
      ast-grep-cli
      pyyaml
      tomlkit
      # truststore joined core in headroom 0.38.
      truststore
      # --- proxy ---
      fastapi
      uvicorn
      orjson
      httpx
      h2
      openai
      mcp
      magika
      zstandard
      websockets
      onnxruntime
      transformers
      watchdog
      sqlite-vec
      # --- code (AST compression) ---
      tree-sitter-language-pack
      tree-sitter
      # --- ml (Kompress) ---
      torch
      huggingface-hub
      # --- memory ---
      sentence-transformers
      # --- relevance ---
      fastembed
      numpy
      # --- image ---
      pillow
      sentencepiece
      rapidocr
      # --- reports ---
      jinja2
      # --- otel ---
      opentelemetry-sdk
      opentelemetry-exporter-otlp-proto-http
      # --- evals ---
      datasets
      scikit-learn
      anthropic
      # --- html ---
      trafilatura
      # --- mcp (server tools; shared with proxy) ---
      starlette
      # --- spreadsheet ---
      openpyxl
      xlrd
    ];

    # The flake input `headroom` is the prebuilt manylinux_2_28 x86_64 wheel
    # (cp310-abi3, compatible with CPython 3.10–3.13). Nix stores non-archive
    # URL inputs under the bare filename `source` (no `.whl` extension), which
    # breaks buildPythonApplication's `dist/*.whl` globs. We re-materialize the wheel
    # under its real PyPI filename via runCommand.
    headroom-wheel = pkgs.runCommand "headroom-ai-wheel" {} ''
      mkdir -p $out
      cp ${inputs.headroom} $out/headroom_ai-0.40.0-cp310-abi3-manylinux_2_28_x86_64.whl
    '';

    # Base wheel packaging shared by full and slim variants
    mkHeadroom = propagatedBuildInputs:
      py.buildPythonApplication {
        pname = "headroom-ai";
        version = "0.40.0";
        format = "wheel";
        src = "${headroom-wheel}/headroom_ai-0.40.0-cp310-abi3-manylinux_2_28_x86_64.whl";
        nativeBuildInputs = [pkgs.autoPatchelfHook];
        buildInputs = [pkgs.stdenv.cc.cc.lib];
        inherit propagatedBuildInputs;
        autoPatchelfIgnoreMissingDeps = ["libonnxruntime.so"];
        meta = {
          description = "Context compression layer for AI agents";
          homepage = "https://headroom-docs.vercel.app/docs";
          license = lib.licenses.asl20;
          mainProgram = "headroom";
          platforms = ["x86_64-linux"];
        };
      };
  in {
    # Full build: headroom-ai[all] — ml/memory/relevance/image/evals/voice/
    # html/spreadsheet features enabled (torch, sentence-transformers, OCR...).
    packages.headroom = mkHeadroom allDeps;

    # Slim build: core + proxy + code + mcp only (~3.8 GB smaller closure).
    # Supports proxy serve + MCP compress/retrieve roundtrip; drops features
    # that need torch/embedding-models (memory, learn, image OCR, evals).
    packages.headroom-slim = mkHeadroom (with py; [
      # --- core ---
      tiktoken
      pydantic
      litellm
      click
      rich
      opentelemetry-api
      ast-grep-cli
      pyyaml
      tomlkit
      # truststore joined core in headroom 0.38.
      truststore
      # --- proxy ---
      fastapi
      uvicorn
      orjson
      httpx
      h2
      openai
      mcp
      zstandard
      websockets
      watchdog
      magika
      transformers
      # --- code (AST compression) ---
      tree-sitter-language-pack
      tree-sitter
      # --- mcp (server tools; shared with proxy) ---
      starlette
    ]);
  };
}
