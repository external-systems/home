# Scenario design notes

These are design branches, not additional implemented upstream pairings. At
researched declarative-runtime commit `0e727d18…`, only Forgejo and Keycloak
ship as modules. Provider availability and NixOS unit facts below were checked
against nixpkgs revision `319e4cebef10`; recheck the consumer's pin.

## Kubernetes API resources

The Kubernetes and Helm providers are packaged in nixpkgs as
`pkgs.terraform-providers.hashicorp_kubernetes` and
`pkgs.terraform-providers.hashicorp_helm`. They can reconcile API-managed
cluster state after the control plane becomes ready. That is a technical fit,
but first check for an existing owner: kubenix/server-side apply, a Rancher
helm-controller, or GitOps may already manage the same objects.

Run reconciliation on a selected control-plane/server host, not on every
agent. Local per-host OpenTofu state and an HA cluster do not by themselves
provide a safe multi-writer design; elect one owner or partition resource
ownership explicitly.

### Unit and kubeconfig selection

| NixOS service | Control-plane unit to order after | Local admin kubeconfig |
|---|---|---|
| k3s server | `k3s.service` | `/etc/rancher/k3s/k3s.yaml` |
| RKE2 server | `rke2-server.service` | `/etc/rancher/rke2/rke2.yaml` |
| RKE2 agent | `rke2-agent.service` | none: no local API server |

The distro kubeconfigs point at the local/loopback API endpoint. Use that for a
host-local readiness probe rather than an HAProxy/VIP endpoint, so the probe
measures the unit this host just started. A non-root reconciler or least
privilege requires a purpose-built RBAC kubeconfig supplied as a runtime secret
file; do not copy its contents into Nix.

NixOS `services.kubernetes` is **not kubeadm**: it wires individual
`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `kubelet`, and
other components with cfssl-based PKI. There is no nixpkgs `kubeadm init/join`
module behind that option. For this service, order after
`kube-apiserver.service` and derive authentication from that module's actual
kubeconfig/PKI options instead of copying Rancher paths.

Primary sources: nixpkgs
`nixos/modules/services/cluster/rancher/{default,k3s,rke2}.nix` and
`nixos/modules/services/cluster/kubernetes/`.

### Readiness is an authenticated API check

The shared declarative-runtime `healthUrl` probe is anonymous `curl`; a normal
Kubernetes API needs authentication. Specialize the reconciler with `kubectl`
or an authenticated TLS probe. The following is the ordering/probe shape used
by this repo's clanServices, with a final failure instead of falling through to
apply:

```nix
systemd.services.declarative-k3s = {
  wantedBy = [ "multi-user.target" ];
  after = [ "k3s.service" ];       # RKE2: rke2-server.service
  requires = [ "k3s.service" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  path = [ pkgs.kubectl pkgs.coreutils ];
  script = ''
    set -euo pipefail
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    i=0
    until kubectl get --raw=/readyz >/dev/null 2>&1; do
      i=$((i + 1))
      if [ "$i" -ge 120 ]; then
        echo "Kubernetes API did not become ready" >&2
        exit 1
      fi
      sleep 5
    done
    # Run the OpenTofu apply only after this authenticated probe succeeds.
  '';
};
```

`/readyz` is preferred over deprecated `/healthz`. Add `Restart=on-failure`,
`RestartSec`, and `StartLimitIntervalSec=0` only when the desired behavior is
persistent retry; upstream declarative-runtime instead leaves a failed oneshot
visible for operator recovery. CRDs created asynchronously by an operator may
require retry or explicit dependency ordering even after `/readyz` succeeds.

Local proven pattern:
`external-systems/clanServices/lib/kube-cluster/bootstrap.nix:95-148`.

## Helm releases

The Helm provider can manage chart releases through the same kubeconfig and
readiness boundary, so a specialized cluster-runtime pairing is possible. Helm
is not itself a NixOS systemd service, so frame this as a Kubernetes runtime
extension rather than inventing `services.helm.runtime`.

Before choosing it, compare the distro's native chart mechanism and the
fleet's GitOps owner. This repo's k3s/RKE2 services deliberately use a
kubenix-rendered bootstrap bundle and reserve day-2 chart ownership for
GitOps; adding Helm-provider state for the same releases would duplicate that
control plane.

## External DNS records

A DNS provider such as Cloudflare manages runtime records through an API and
can reuse the `.tf.json` + run-once + `LoadCredential` design. Cloudflare is
packaged as `pkgs.terraform-providers.cloudflare_cloudflare`; its API token can
come from a clan vars `File` path just like a local service token.

The differences are architectural:

- there is no local primary service unit—order after `network-online.target`
  and probe the provider/API as appropriate;
- state remains local to the reconciler host, with no remote backend in the
  upstream model, so designate one writer for a zone or record set;
- node addresses must come from eval-known host/cluster facts or an explicit
  runtime-discovery step, not from reading a host during pure Nix evaluation;
- API drift still is not repaired until the next trigger.

For DNS specifically served by a NixOS daemon, compare provider-managed API
state with the daemon's existing declarative zone-file options first.

## GitLab and Technitium DNS

- **GitLab** is a strong candidate pattern: `services.gitlab` exists and
  nixpkgs packages `gitlabhq_gitlab`. Groups, projects, and variables are
  runtime API state. Authentication/bootstrap and a live-API VM test still need
  to be implemented; no completed pairing is implied.
- **Technitium DNS Server** has a NixOS module but no provider in the
  researched nixpkgs provider set. Community providers exist, so a pairing
  would require selecting one deliberately, auditing its schema/license, and
  vendoring it with `terraform-providers.mkProvider` as Forgejo does.

For either candidate, follow `authoring.md` rather than treating the service
name as evidence of provider coverage.
