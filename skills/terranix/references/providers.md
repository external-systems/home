# Providers

Provider schemas belong to the provider, not terranix. Keep the provider's
official resource documentation open and translate its HCL arguments to Nix
attrsets without renaming `snake_case` arguments. Declare every provider under
`terraform.required_providers`, including providers bundled with `withPlugins`.

The version constraints below match the researched major versions on
2026-10-28. Check the consumer's lockfile and the provider upgrade guide before
copying them into an existing stack or upgrading a major version.

| Platform | Source | Authentication from the environment |
|---|---|---|
| Hetzner Cloud | `hetznercloud/hcloud` | `HCLOUD_TOKEN` |
| AWS | `hashicorp/aws` | Standard AWS credential chain, including `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, shared config, and workload identity |
| Google Cloud | `hashicorp/google` | Application Default Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or `GOOGLE_CREDENTIALS` |
| Azure | `hashicorp/azurerm` | Azure CLI, workload identity, or `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` |
| Cloudflare | `cloudflare/cloudflare` | Scoped `CLOUDFLARE_API_TOKEN` |
| Proxmox VE | `bpg/proxmox` | `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN` |

Environment authentication keeps credentials out of generated JSON and the Nix
store. A provider block can be empty when the environment supplies all required
settings. If using a `TF_VAR_<name>` variable instead, declare
`variable.<name>.sensitive = true`; this redacts normal UI output but does not
keep the value out of state.

## Hetzner Cloud

```nix
{
  terraform.required_providers.hcloud = {
    source = "hetznercloud/hcloud";
    version = "~> 1.70";
  };

  provider.hcloud = {};

  resource.hcloud_server.node1 = {
    name = "node1";
    image = "debian-13";
    server_type = "cx23";
    location = "nbg1";
    public_net = {
      ipv4_enabled = true;
      ipv6_enabled = true;
    };
  };
}
```

Use a Read & Write API token. Prefer `location`; `datacenter` is deprecated.
If API rate limits appear, investigate the provider's `poll_interval` and
`poll_function` settings rather than retrying applies in a loop.

Sources: [provider configuration](https://github.com/hetznercloud/terraform-provider-hcloud/blob/main/docs/index.md),
[server resource](https://github.com/hetznercloud/terraform-provider-hcloud/blob/main/docs/resources/server.md).

## AWS

```nix
{
  terraform.required_providers.aws = {
    source = "hashicorp/aws";
    version = "~> 6.0";
  };

  provider.aws.region = "eu-central-1";
}
```

Prefer the normal AWS credential chain or an assumed role over long-lived
access keys. For multiple regions, represent repeated provider blocks as a
list and select an alias in the resource:

```nix
{
  provider.aws = [
    {region = "us-east-1";}
    {
      region = "eu-central-1";
      alias = "eu";
    }
  ];

  resource.aws_s3_bucket.eu_state = {
    bucket = "my-unique-example-bucket";
    provider = "\${aws.eu}";
  };
}
```

Sources: [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs),
[provider source and upgrade guides](https://github.com/hashicorp/terraform-provider-aws).

## Google Cloud

```nix
{
  terraform.required_providers.google = {
    source = "hashicorp/google";
    version = "~> 8.0";
  };

  provider.google = {
    project = "my-gcp-project";
    region = "europe-west3";
    zone = "europe-west3-a";
  };
}
```

Use Application Default Credentials or workload identity. Beta resources need
the separate `hashicorp/google-beta` provider declaration, a `google-beta`
provider block, and `provider = "\${google-beta}"` on the resource.

Sources: [provider reference](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference),
[Google provider repository](https://github.com/hashicorp/terraform-provider-google).

## Azure

```nix
{
  terraform.required_providers.azurerm = {
    source = "hashicorp/azurerm";
    version = "~> 5.0";
  };

  provider.azurerm = {
    features = {};
    subscription_id = "00000000-0000-0000-0000-000000000000";
  };

  resource.azurerm_resource_group.example = {
    name = "example-resources";
    location = "West Europe";
  };
}
```

`features = {};` is required even when empty. Supply the real subscription ID
through `ARM_SUBSCRIPTION_ID` and omit the example `subscription_id` when that
better fits the environment. Since provider v4, validation can succeed without
a subscription while plan/apply still needs one.

Sources: [AzureRM provider configuration](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/index.html.markdown),
[authentication guides](https://github.com/hashicorp/terraform-provider-azurerm/tree/main/website/docs/guides).

## Cloudflare

```nix
{lib, ...}: {
  terraform.required_providers.cloudflare = {
    source = "cloudflare/cloudflare";
    version = "~> 5.0";
  };

  variable.cloudflare_api_token.sensitive = true;
  provider.cloudflare.api_token = lib.tf.ref "var.cloudflare_api_token";

  resource.cloudflare_dns_record.www = {
    zone_id = "023e105f4ecef8ad9ca31a8372d0c353";
    name = "www.example.com";
    type = "A";
    content = "192.0.2.1";
    ttl = 3600;
  };
}
```

Export `TF_VAR_cloudflare_api_token` from a secret source for this example, or
omit `api_token` and use `CLOUDFLARE_API_TOKEN` directly. Cloudflare v5 is a
major rewrite: `cloudflare_dns_record` replaces the v4 `cloudflare_record`
shape, so do not mix v4 examples into a v5 configuration. Prefer a scoped API
token over the legacy global key.

Sources: [Cloudflare provider](https://github.com/cloudflare/terraform-provider-cloudflare/blob/main/docs/index.md),
[DNS record resource](https://github.com/cloudflare/terraform-provider-cloudflare/blob/main/docs/resources/dns_record.md),
[v5 upgrade guide](https://github.com/cloudflare/terraform-provider-cloudflare/blob/main/docs/guides/version-5-upgrade.md).

## Proxmox VE

For new `bpg/proxmox` configurations:

```nix
{
  terraform.required_providers.proxmox = {
    source = "bpg/proxmox";
    version = "0.118.1";
  };

  provider.proxmox.endpoint = "https://pve.example.com:8006/";
}
```

Set `PROXMOX_VE_API_TOKEN` to `user@realm!tokenid=secret`. The bpg endpoint
excludes `/api2/json`. Pin the exact 0.x release and review each upgrade; minor
releases can change the schema. Some operations need additional Proxmox
privileges or SSH, so read the specific resource documentation before adding
snippets, disk imports, passthrough, or container ID mappings.

`Telmate/proxmox` is an incompatible alternative, not a drop-in replacement. It
uses `pm_api_url` with `/api2/json`, `PM_*` environment variables, and resources
such as `proxmox_vm_qemu`. Preserve the existing provider when maintaining a
Telmate stack; switching providers means rewriting resources and planning state
migration.

Sources: [bpg provider and requirements](https://github.com/bpg/terraform-provider-proxmox),
[bpg documentation](https://bpg.sh), [Telmate provider](https://github.com/Telmate/terraform-provider-proxmox).

## Registry and plugin installation

By default, `init` resolves `required_providers` from the registry and writes
`.terraform.lock.hcl` in the configuration workdir. Commit that lockfile. Use
`withPlugins` only when offline or pre-baked provider execution is worth the
extra Nix packaging:

```nix
terraformWrapper.package = pkgs.opentofu.withPlugins (p: [
  p.aws
  p.null
  p.external
]);
```

The available `p.*` names come from nixpkgs, not from the provider registry;
check that the required provider and version are actually packaged there.
