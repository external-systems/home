# Secret files and clan vars

The pairing's secret boundary is a **target-host file path**. Nix evaluation
may carry that path as a string, but never the file's plaintext. At unit start,
systemd `LoadCredential=` reads the file and exposes it under
`$CREDENTIALS_DIRECTORY`; the reconciler exports it as `TF_VAR_<id>`. Generated
`.tf.json` contains only `${var.<id>}` and `sensitive = true` declarations.

Evidence: upstream `modules/lib/default.nix:226-309,477-569` at commit
`0e727d18c6f69f00f9b2786cb09d39d316413847`.

## Resource and admin credentials

Use the admin credential's `File` option, such as `tokenFile`,
`bootstrapAdminPasswordFile`, or `clientSecretFile`. Every schema-sensitive
resource attribute also has an `<attr>File` sibling, including inside nested
submodules and list elements:

```nix
services.keycloak.runtime = {
  enable = true;
  bootstrapAdminPasswordFile = "/run/secrets/keycloak-admin-password";

  realms.staff.smtp_server.auth = {
    username = "noreply";
    passwordFile = "/run/secrets/staff-smtp-password";
  };

  users.alice = {
    realm = "staff";
    username = "alice";
    initial_password = {
      valueFile = "/run/secrets/staff-alice-initial-password";
      temporary = true;
    };
  };
};
```

The literal attribute and its `File` sibling are mutually exclusive; setting
both is a generation error. A required secret can be satisfied by either form,
but the literal form renders into the world-readable Nix store and is only for
non-secret test values.

A `File` value is a runtime path string, **not** `pkgs.writeText`,
`builtins.toFile`, a store symlink, or the contents read with
`builtins.readFile`.

## Wire a clan vars generator

Clan vars fit this contract directly. Declare the generator next to the NixOS
consumer, use a deployed secret in the `services` phase, and pass its `.path`
to the pairing:

```nix
{
  config,
  ...
}:
{
  clan.core.vars.generators.example-runtime = {
    # An operator prompt is appropriate for an externally issued API token.
    # persist stores the answer as the generator's secret file.
    prompts.api-token.persist = true;

    files.api-token = {
      neededFor = "services";
      restartUnits = [ "declarative-example.service" ];
    };
  };

  services.example.runtime = {
    enable = true;
    tokenFile =
      config.clan.core.vars.generators.example-runtime.files.api-token.path;
  };
}
```

`neededFor = "services"` is the default, shown here to make the lifecycle
explicit. `secret = true` and `deploy = true` are also the defaults and are
required for this use. Use `share = true` only when several machines genuinely
share one credential; host-scoped credentials should stay per-machine.

With clan's sops backend, a deployed service secret's `.path` resolves to its
runtime `/run/secrets/vars/...` location, not a Nix store path. systemd PID 1
loads the credential before dropping to the reconciler's service user, so the
usual root-owned `0400` source file works without granting that user direct
access to the sops tree.

`restartUnits` matters for rotation: the generated `.tf.json` still contains
the same variable reference when only the file contents change. Restarting the
reconciler is what makes systemd read the new value and OpenTofu apply it.

Before the human runs `clan vars generate`, clan's sops mapping can produce the
placeholder `/no-such-path`; the reconciler then fails at credential loading
rather than at Nix evaluation. Generate and deploy vars before expecting the
unit to converge. In this repo those generation/rotation commands are
human-only agent boundaries.

Evidence: clan-core `nixosModules/clanCore/vars/secret/sops/default.nix` and
`generators-to-sops.nix`; this repo's `flake-parts/nixosModules/git.nix` and
`ssh.nix` for generator/consumer patterns.

## Lifecycle choices

- Use `neededFor = "services"` for pairing credentials.
- `users`, `activation`, and `partitioning` secrets serve earlier provisioning
  phases and different paths; they are not interchangeable runtime inputs.
- Operator-supplied tokens and resource secrets are natural clan vars.
- Credentials minted by a pairing's own bootstrap unit are host runtime state,
  usually under `/var/lib/declarative-*`; leave them there rather than moving
  them into clan vars.
- sops-nix and agenix host paths satisfy the same `File` contract. The pairing
  does not care which tool provisioned the file.

## Protect state and diagnostics

Sensitive input variables keep secrets out of `.tf.json`, **not necessarily out
of OpenTofu state**. [State and plan/show output can contain sensitive
values](https://opentofu.org/docs/language/state/sensitive-data/).
Keep the `0700` `declarative-terraform` directory with the service's protected
runtime data, include it in the service's backup policy, and never commit or
paste state contents into public logs.

For debugging, prefer unit status, provider errors in the journal, and a live
API query that proves the desired value took effect. Do not print credential
files, `TF_VAR_*` environments, state, or a plan merely to make diagnosis
easier.
