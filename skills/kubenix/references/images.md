# Nix-built OCI images in kubenix manifests

The `docker` module tracks images as first-class values: each image is a
`dockerTools` derivation, kubenix computes its registry reference, and you
wire that reference into container specs. Pushing to a registry is a
separate, explicit step via a generated skopeo script.

## Declaring images

```nix
{ kubenix, config, pkgs, ... }: {
  imports = [ kubenix.modules.k8s kubenix.modules.docker ];

  docker = {
    registry.host = "registry.internal:5000";   # default host for all images
    images.myapp.image = pkgs.dockerTools.buildLayeredImage {
      name = "myapp";
      tag = "1.4.2";
      contents = [ pkgs.myapp ];
      config.Cmd = [ "${pkgs.myapp}/bin/myapp" ];
    };
  };

  kubernetes.resources.deployments.myapp.spec.template.spec.containers.myapp = {
    image = config.docker.images.myapp.path;   # "registry.internal:5000/myapp:1.4.2"
  };
}
```

Per-image values (`docker.images.<name>`):

- `image` — the dockerTools derivation (`buildImage`, `buildLayeredImage`,
  `streamLayeredImage` all work).
- `name` / `tag` — default to the image's `imageName` / `imageTag`.
- `registry.protocol` / `registry.host` — per-image overrides of the global
  `docker.registry.*`.
- `path` (computed) — `host/name:tag`, what you put in container specs.
- `uri` (computed) — `protocol + path`, e.g. `docker://host/name:tag`.

Third-party images you want to mirror or pin: pull them as fixed-output
derivations with `pkgs.dockerTools.pullImage { imageName; imageDigest;
sha256; }` and register them the same way.

## Pushing: `docker.copyScript`

`config.docker.copyScript` is a ready-to-run package (binary
`kubenix-push-images`) that pushes every image in `docker.export` (which
auto-collects `docker.images`) using skopeo:

```nix
packages.push-images = (kubenixEval).config.docker.copyScript;
# nix run .#push-images
```

- `docker.registry.protocol` (default `docker://`) selects the skopeo
  destination transport: `docker://` (registry), `oci-archive:`,
  `oci:`, `dir:`, `containers-storage:`, `docker-archive:`,
  `docker-daemon:`.
- `docker.copyScriptArgs` appends extra `skopeo copy` args (auth,
  `--dest-tls-verify=false`, …).
- `docker.useVals` (default `true`) resolves `ref+envsubst://$VAR`-style
  vals references in URIs at push time. Set it to `false` for static URIs
  and air-gapped use — it drops the `vals` runtime dependency.
- streamLayeredImage results are streamed (`image | gzip | skopeo copy
  docker-archive:/dev/stdin …`); tarball outputs are copied directly. This
  distinction is handled for you, but explains the two code paths if you
  read the script.

## Air-gapped recipe

There is no airgap module; the recipe composes the pieces:

1. **Charts**: `kubenix.lib.helm.fetch` FODs, or vendored chart directories
   (`chart = ./chart`). Fetch once online; the store path is the artifact.
2. **Images**: build with dockerTools and/or mirror third-party images with
   `dockerTools.pullImage` (FOD). Everything content-addressed in the store.
3. **Transfer**: `nix copy --to file:///… ` (or ssh) the closure of the
   manifest + images to the offline store.
4. **Deliver images** either by pushing to the internal registry
   (`docker.registry.host = "registry.internal:5000"`, run
   `kubenix-push-images` inside the air gap) or by setting
   `docker.registry.protocol = "oci-archive:"`/`"dir:"` and sneaker-netting
   the skopeo output, then `k3s ctr images import` on each node (or drop
   archives in k3s's agent images dir).
5. `docker.useVals = false`.
6. **imagePullSecrets**: declare the pull-secret reference in pod specs
   (`imagePullSecrets`) but never inline the dockerconfigjson — deliver it
   via the secrets patterns in
   [deploy-and-secrets.md](deploy-and-secrets.md).

## Gotchas

- The kubenix CLI does not build/push images for you; `copyScript` is the
  whole mechanism. CI typically runs push before apply.
- 0.4.0 (unreleased) restructured `docker.registry.url` into
  `.protocol`/`.host`; the compat module
  `kubenix.modules.docker-image-from-package` maps old configs. If examples
  online use `docker.registry.url`, translate.
- Image tags are static strings — kubenix doesn't do content-based
  retagging. If you want deploys to pick up rebuilds, set `tag` from your
  own version source (git rev, etc.) or pair with
  `kubernetes.enableHashedNames` style immutability discipline.
