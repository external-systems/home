# Using and debugging pairings

Examples and unit paths below describe upstream commit
`0e727d18c6f69f00f9b2786cb09d39d316413847`. Check the README for the
revision pinned by the consumer flake.

## Install and declare state

Follow the pairing's nixpkgs input so its provider build stays aligned with the
host package set:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    declarative-runtime = {
      url = "github:applicative-systems/declarative-runtime";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, declarative-runtime, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        declarative-runtime.nixosModules.keycloak
        ./host.nix
      ];
    };
  };
}
```

Import `nixosModules.forgejo`, `nixosModules.keycloak`, or
`nixosModules.default` for every implemented pairing. Enable both the base
service and its `runtime` submodule. Resource options are typed from the
vendored provider schema, so use that revision's generated option document as
the authoritative surface:

```sh
nix build .#checks.x86_64-linux.forgejo-options-doc
nix build .#checks.x86_64-linux.forgejo-schema-coverage
```

### References and secrets

```nix
services.forgejo.runtime = {
  enable = true;

  organizations.acme.description = "ACME Corporation";
  repositories.widgets.owner = "acme";

  repository_webhooks.ci = {
    repository = "widgets"; # managed key -> repositories.widgets.id
    type = "forgejo";
    events = [ "push" "pull_request" ];
    active = true;
    config = {
      url = "https://ci.example.invalid/forgejo-hook";
      content_type = "json";
    };
    authorization_headerFile = "/run/secrets/forgejo-ci-webhook-header";
  };
};
```

Use a managed collection key for a managed parent; use a literal only where
that reference explicitly permits external/built-in names. Prefer `<attr>File`
for real secrets. See `secrets.md` for clan vars wiring.

## Understand when apply runs

The reconciler is a `Type=oneshot` unit with `RemainAfterExit = true` and a
restart trigger on the generated config file. It runs at boot and when NixOS
activation sees a changed generated config. It does not poll for external
drift, continuously plan, or import every unmanaged object.

Changing only a credential file does not change `.tf.json`; restart the unit
(or wire clan vars `restartUnits`) to reload it. A failed apply leaves the base
service running and fails only the reconciler. Correct the cause, then rerun
with `systemctl restart declarative-<svc>.service` or through the host's normal
deployment flow.

State persists across attempts. A second successful apply of unchanged desired
state should report `0 added, 0 changed, 0 destroyed`.

## Diagnose in dependency order

1. **Base service and readiness**

   ```sh
   systemctl status forgejo.service
   curl -fsS http://localhost:3000/api/healthz
   ```

   Substitute the configured URL and service. The stock reconciler's probe loop
   can exhaust its attempts and then fall through to OpenTofu, so a connection
   error in the apply log may really be a readiness failure. `After=` does not
   prove the API is ready.

2. **Credential bootstrap**

   ```sh
   systemctl status declarative-forgejo-token.service
   journalctl -u declarative-forgejo-token.service -b
   ```

   Keycloak uses `declarative-keycloak-bootstrap.service`. Restarting that
   bootstrap re-probes its persisted client pair and refreshes it if the secret
   was rotated server-side. For operator-supplied files, check that the target
   path exists at unit start; do not print its contents.

3. **Reconciler**

   ```sh
   systemctl status declarative-forgejo.service
   journalctl -u declarative-forgejo.service -b -o cat
   ```

   Look for readiness, credential loading, provider authentication, schema
   validation, API 4xx/5xx, and the final `Apply complete!` counts. Keycloak's
   corresponding unit is `declarative-keycloak.service`.

4. **Live API**

   Query the object the module should have created. This distinguishes provider
   success from actual service behavior and is the same evidence standard used
   by upstream integration tests.

## State and generated files

| Pairing | Runtime work directory | Bootstrap output |
|---|---|---|
| Forgejo | `/var/lib/forgejo/declarative-terraform/` | `/var/lib/declarative-forgejo/api-token` |
| Keycloak | `/var/lib/keycloak/declarative-terraform/` | `/var/lib/declarative-keycloak-bootstrap/{client_id,client_secret}` |

The work directory contains `main.tf.json`, OpenTofu state, and provider
metadata. Generated config is mode `0600` and should contain variable
references rather than secret literals. State remains sensitive runtime data;
do not commit it, publish it, or treat `sensitive = true` as encryption.

Avoid casually running `tofu apply`, `tofu destroy`, or deleting the state
directory as a repair. Manual runs need the same working directory, provider,
credentials, and service user, and can change ownership or live resources.
State loss changes OpenTofu's knowledge of ownership; whether existing objects
can be re-adopted is provider/resource-specific and must be tested, not
assumed. Prefer restoring the service's state backup or fixing and restarting
the reconciler.

## Eval-time provider drift

Provider/schema mismatches intentionally fail before deployment. Typical
messages identify a packaged version that differs from the vendored schema or
a provider resource that is neither modelled nor listed in `unsupported`.
After a provider or nixpkgs bump, run:

```sh
nix run .#update-provider-schemas
nix flake check
```

Review every added, removed, and retyped attribute. Model new resources or
record a non-empty unsupported reason. If an upstream attribute becomes
required, existing configurations may stop evaluating; that is usually useful
signal, with `forceOptional` as the explicit exception. Use the targeted schema
checks in `authoring.md` when the host repo defers heavy VM tests.
