# State, maintenance, and debugging

## Own the runtime boundary

Terranix evaluation produces `config.tf.json`; Terraform or OpenTofu owns
providers, plans, state, and API changes. Keep generated configuration,
credentials, and state as separate concerns:

- Commit Nix sources, `flake.lock`, and each workdir's `.terraform.lock.hcl`.
- Ignore `config.tf.json`, `.terraform/`, `*.tfstate*`, plan files, crash logs,
  and secret-bearing backend override files.
- Treat state and plan files as sensitive even when every input variable is
  marked `sensitive`. Sensitive display redaction is not state encryption.
- Give each configuration its own state key and workdir. Split stacks at
  ownership, lifecycle, or blast-radius boundaries rather than by file count.

The flake-parts scripts enter `workdir` themselves. Stay at the directory from
which `nix run`/`nix develop` was invoked when calling the wrapped `tofu` or
`terraform`; changing into the workdir first makes the wrapper enter it again.

## Review changes before applying

For a configuration named `prod` using OpenTofu:

```sh
nix develop .#prod
tofu init
tofu validate
tofu plan -out=tfplan
tofu show tfplan
```

Review the plan and expected state owner. After approval, apply that exact
artifact rather than generating a second plan:

```sh
tofu apply tfplan
```

`nix run .#prod.plan` is convenient for disposable development stacks, but its
script does not save a reviewed plan artifact. `nix run .#prod` runs init and
apply directly, so it is not the production approval path.

For destruction, show the complete deletion set first, including dependent
resources:

```sh
tofu plan -destroy -out=destroy.tfplan
tofu show destroy.tfplan
```

Obtain explicit approval, then apply `destroy.tfplan`. Do not use
`-auto-approve`, and do not treat deleting state as a repair: state loss changes
ownership knowledge while leaving live infrastructure behind.

## Hetzner Object Storage: path-style S3 backend

Use the S3 backend with the location-specific endpoint and path-style addressing:

```nix
{
  terraform.backend.s3 = {
    bucket = "my-tfstate-bucket";
    key = "prod/network/terraform.tfstate";
    region = "eu-central";
    endpoints.s3 = "https://nbg1.your-objectstorage.com";
    use_path_style = true;
    skip_credentials_validation = true;
    skip_requesting_account_id = true;
    skip_metadata_api_check = true;
    skip_region_validation = true;
    use_lockfile = true;
  };
}
```

`use_lockfile` requires Terraform or OpenTofu 1.10+ and uses native S3
conditional writes. Older Terraform releases instead use DynamoDB locking,
which Hetzner Object Storage does not provide. Native locking with an
S3-compatible service is best-effort: test lock acquisition and release against
the target bucket before relying on it, and prevent concurrent writers through
execution policy when locking is unavailable.

Use `endpoints.s3` and `use_path_style`, not the deprecated top-level
`endpoint` or `force_path_style` spellings. Other Hetzner locations are `fsn1`
and `hel1`. The four skip flags disable AWS-only STS, IAM account, EC2
metadata, and region checks.

Export the S3 credentials at runtime. With the flake-parts wrapper, secret
files can be read without putting their contents in Nix or generated JSON:

```nix
terraformWrapper.prefixText = ''
  export AWS_ACCESS_KEY_ID="$(< /run/secrets/hetzner-s3-access-key)"
  export AWS_SECRET_ACCESS_KEY="$(< /run/secrets/hetzner-s3-secret-key)"
'';
```

The invoking user needs read access to those files. Keep backend values static
in the generated JSON for compatibility with both runtimes: Terraform backend
blocks cannot refer to variables, locals, or resources. Nix interpolation is
fine because it produces literal JSON before Terraform starts. OpenTofu 1.8+
can evaluate some static backend expressions, but using that feature makes the
configuration runtime-specific.

For partial backend configuration, pass
`tofu init -backend-config=backend.tfbackend` or repeated
`-backend-config='KEY=VALUE'` arguments through the init script. Prefer
environment credentials: merged backend configuration can be persisted in
plaintext under `.terraform/`, including values supplied in override files.

Sources: [OpenTofu S3 backend](https://opentofu.org/docs/language/settings/backends/s3/),
[backend configuration](https://opentofu.org/docs/language/settings/backends/configuration/),
[Terraform S3 backend and locking](https://developer.hashicorp.com/terraform/language/backend/s3),
[Terraform backend rules](https://developer.hashicorp.com/terraform/language/backend),
[Hetzner Object Storage overview](https://docs.hetzner.com/storage/object-storage/overview/),
[Hetzner's S3 backend tutorial](https://community.hetzner.com/tutorials/howto-hcloud-s3-terraform-backend/).

## Maintain pins deliberately

1. Record the current runtime, provider lockfile, backend, execution path, and
   environment criticality before changing a stack.
2. Update terranix with `nix flake update terranix` and read its changelog.
   Review generated JSON and run a plan; keep this separate from provider
   upgrades when possible.
3. Review provider upgrade guides, change `required_providers`, then run
   `tofu init -upgrade` through the wrapper. Inspect the lockfile diff and plan.
4. Run validation and a fresh plan in CI from the same locked flake and provider
   pins. Apply the reviewed plan artifact instead of replanning in the apply job.
5. Back up state before backend or state migration. Use `moved`, `import`, and
   `removed` blocks to make ownership changes reviewable; check runtime floors
   in [modules.md](modules.md).

A second plan after an unchanged successful apply should normally be empty. A
non-empty plan means drift, provider behavior, or changed inputs; identify the
cause before applying.

## Debug in evaluation order

| Symptom | What to inspect |
|---|---|
| Nix `variable not found`, infinite recursion, or type error | The generated Nix module, not providers. Inspect the reported option path and escape Terraform `${...}` references as described in [modules.md](modules.md). |
| Generated JSON looks wrong | Build the configuration's `.config` passthru output and inspect it with `jq`. Evaluate `lib.evalTerranixConfiguration` in `nix repl` when an attrset is easier to inspect. |
| `nix run` changes nothing | Check the selected configuration name and its workdir. Re-evaluate the flake; confirm the generated `config.tf.json` symlink points to the new store path. |
| A devShell uses an old configuration | Re-enter `nix develop .#<name>`. Its scripts contain the previous generation's store paths. |
| `tofu validate` reports unsupported arguments or missing blocks | Compare the generated JSON with the locked provider's documentation. Validation checks provider schemas; Nix evaluation does not. |
| Authentication fails only during plan/apply | Check the wrapper's environment and secret-file readability without printing credentials. `validate` does not prove API authentication. |
| Backend change is ignored or init requests migration | Re-run init and review the migration prompt. Keep a state backup; do not switch backends by editing state files. |
| Hetzner state upload reports checksum errors | Add `skip_s3_checksum = true` to the S3 backend for S3-compatible services that do not implement the newer AWS checksum behavior. |
| State is locked | Identify the live operation and lock owner. Follow the runtime's lock documentation and preserve evidence; forced unlock is appropriate only after confirming no operation is active. |
| Resource already exists | Decide whether to import the existing object or change the desired name. Do not delete state or create a duplicate to make the error disappear. |
| Plan contains secrets | Restrict plan artifact access and retention just like state. Remove artifacts after the reviewed workflow finishes. |

Useful read-only commands from the configuration's caller directory:

```sh
tofu show
tofu state list
tofu output
tofu providers
tofu version
```

Use `TF_LOG=DEBUG` or `TF_LOG=TRACE` only for a focused reproduction: provider
logs can include sensitive requests and responses. Store logs with the same
care as state, and return logging to the normal level afterwards.
