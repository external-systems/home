---
name: declarative-runtime
description: "Declarative NixOS service runtime state with applicative-systems/declarative-runtime and OpenTofu: use existing pairings, author services.SERVICE.runtime modules from provider schemas, generate .tf.json, wire systemd readiness and reconciliation, manage secret files with clan vars or sops-nix, debug applies and state, and assess Kubernetes, Helm, DNS, GitLab, or Technitium scenarios. Load whenever the user mentions declarative-runtime, Terraform/OpenTofu providers for NixOS services, API-managed runtime resources in Nix, or File-suffixed secret options."
---

# declarative-runtime

[applicative-systems/declarative-runtime](https://github.com/applicative-systems/declarative-runtime)
extends a NixOS service with a **pairing**: a NixOS module plus the
service's Terraform provider, executed by OpenTofu. The upstream NixOS module
keeps owning static configuration; the pairing manages runtime objects through
the service API.

This skill covers using, authoring, and debugging pairings. It was researched
at upstream commit
[`0e727d18c6f69f00f9b2786cb09d39d316413847`](https://github.com/applicative-systems/declarative-runtime/tree/0e727d18c6f69f00f9b2786cb09d39d316413847).
Read the same revision of upstream `CLAUDE.md` and `modules/lib/` before
changing an implementation; the contract and provider versions move.

## Decide whether the pattern fits

A pairing is useful when all of these hold:

- The desired state is **admin-declarative runtime state**: API-managed objects
  such as realms, repositories, users, DNS records, or cluster resources.
- A provider can manage that state, and the base NixOS module cannot already
  express it.
- One reconciliation owner and local, per-host OpenTofu state fit the target.
- Run-once reconciliation is acceptable. There is no drift timer.

Stay with the base NixOS module when a config file already covers the surface.
Stay with GitOps or another existing owner when it already manages the same
objects. Two reconcilers fighting over one resource is an ownership design
error, not an integration win. A remote API such as a DNS provider can use the
same mechanism, but it is no longer a local-service pairing; choose one writer
and account for the local-state limitation explicitly.

At the researched revision, **Forgejo and Keycloak are the implemented
pairings**. Grafana appears as a design target, not a working module. Do not
infer that a pairing exists from a service name alone.

## The reconciliation model

For an enabled pairing, Nix evaluation produces typed options and a `.tf.json`
desired-state document. On the host:

1. The primary service and any credential-bootstrap unit start.
2. A `Type=oneshot` unit named `declarative-<svc>.service` orders itself after
   them and probes the live API. `After=` alone only orders process startup; it
   does not prove readiness.
3. systemd loads host-file credentials. OpenTofu runs offline with its provider
   baked in, then applies against the API.
4. State persists under the service's state directory in
   `declarative-terraform/`. A generated-config change restarts the reconciler
   through `restartTriggers`.

A failed apply fails the reconciler unit without stopping the base service.
External drift is not continuously detected or repaired. OpenTofu state can
contain sensitive values even when `main.tf.json` contains only variable
references; protect it as runtime secret material and never commit it.

## Route the task

| Branch | Read |
|---|---|
| Install, declare resources, operate, or debug an existing pairing | [references/using-and-debugging.md](references/using-and-debugging.md) |
| Author a new pairing or change its provider surface | [references/authoring.md](references/authoring.md) |
| Supply credentials, nested secrets, or clan vars files | [references/secrets.md](references/secrets.md) |
| Design Kubernetes, Helm, DNS, GitLab, or Technitium reconciliation | [references/scenarios.md](references/scenarios.md) |

For implementation work, the authoritative upstream contract is
[`CLAUDE.md`](https://github.com/applicative-systems/declarative-runtime/blob/0e727d18c6f69f00f9b2786cb09d39d316413847/CLAUDE.md).
Use `services/forgejo` as the small worked example and `services/keycloak` for
nested resources, multiple credentials, and the sdk/v2 schema dialect.

## Minimal consumer example

```nix
# flake.nix inputs
inputs.declarative-runtime = {
  url = "github:applicative-systems/declarative-runtime";
  inputs.nixpkgs.follows = "nixpkgs";
};

# NixOS host modules
imports = [ inputs.declarative-runtime.nixosModules.forgejo ];

services.forgejo = {
  enable = true;
  runtime = {
    enable = true;
    organizations.acme.description = "ACME Corporation";
    repositories.widgets = {
      owner = "acme"; # managed sibling key, not a hard-coded numeric id
      description = "Widget factory";
    };
  };
};
```

The collection key defaults the resource's name attribute. A managed reference
becomes a Terraform interpolation, which supplies computed IDs and apply
ordering. Provider attributes retain their schema's snake_case names and are
strictly typed.

## Non-negotiable implementation facts

- Generate JSON with `builtins.toJSON`; do not introduce HCL, terranix, or the
  unfree `terraform` executable.
- Vendor and commit the normalized provider schema. Do not use
  import-from-derivation to discover it during evaluation.
- Derive resource options from that schema. Hand-write only collections,
  references, corrections, authentication, and service wiring.
- Use host paths for secrets. A literal secret or a secret store path is
  world-readable once rendered into the Nix store.
- Prove behavior in a NixOS integration test by querying the live API. Eval,
  a successful build, and OpenTofu state inspection are not runtime proof.

In this repo, agents edit and evaluate but never deploy machines or run
`clan vars generate` / `clan vars set`. Report the human commands instead.

## Primary sources

- [Upstream README](https://github.com/applicative-systems/declarative-runtime/blob/0e727d18c6f69f00f9b2786cb09d39d316413847/README.md) — scope, architecture, and development commands.
- [`CLAUDE.md`](https://github.com/applicative-systems/declarative-runtime/blob/0e727d18c6f69f00f9b2786cb09d39d316413847/CLAUDE.md) — the complete new-pairing implementation contract.
- [`modules/lib/`](https://github.com/applicative-systems/declarative-runtime/tree/0e727d18c6f69f00f9b2786cb09d39d316413847/modules/lib) — renderer, schema checks, and reconciler implementation.
- [Forgejo](https://github.com/applicative-systems/declarative-runtime/tree/0e727d18c6f69f00f9b2786cb09d39d316413847/services/forgejo) and [Keycloak](https://github.com/applicative-systems/declarative-runtime/tree/0e727d18c6f69f00f9b2786cb09d39d316413847/services/keycloak) — complete pairings with usage docs and integration tests.
- [`examples/`](https://github.com/applicative-systems/declarative-runtime/tree/0e727d18c6f69f00f9b2786cb09d39d316413847/examples) — runnable NixOS VM configurations.
- [OpenTofu: Sensitive Data in State](https://opentofu.org/docs/language/state/sensitive-data/) — why variable redaction does not make state safe to publish.
