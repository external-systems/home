# Rancher Kubernetes source research

Research date: 2026-10-17.
Scope: k3s, RKE2, Rancher helm-controller, Cilium 1.20+, Multus,
NixOS/nixpkgs, k3d, and k3k. This file records the primary-source map and
research decisions behind the operational references. The operational files
are the maintained skill prose; keep this as evidence and update it when a
claim changes.

Source policy: official project documentation, source repositories, release
artifacts, NixOS/nixpkgs source, and first-party SUSE/Rancher docs. The one
secondary source supplied for the k3d lab was used only as an idea and its
technical claims were checked against k3d, k3s, Cilium, Traefik, and Gateway
API documentation.

## Canonical source map

| Topic | Primary sources |
|---|---|
| k3s architecture, roles, networking | https://docs.k3s.io/architecture and https://docs.k3s.io/networking/basic-network-options |
| k3s configuration | https://docs.k3s.io/installation/configuration |
| k3s datastores | https://docs.k3s.io/datastore and https://github.com/k3s-io/kine |
| k3s tokens and certificates | https://docs.k3s.io/cli/token and https://docs.k3s.io/cli/certificate |
| k3s air gap and registries | https://docs.k3s.io/installation/airgap, https://docs.k3s.io/installation/private-registry, https://docs.k3s.io/installation/registry-mirror |
| k3s Tailscale | https://docs.k3s.io/networking/distributed-multicloud |
| k3s builds and releases | https://github.com/k3s-io/k3s/blob/master/BUILDING.md and https://github.com/k3s-io/k3s/releases |
| RKE2 architecture, HA, roles | https://docs.rke2.io/architecture, https://docs.rke2.io/install/ha, https://docs.rke2.io/install/server_roles |
| RKE2 configuration | https://docs.rke2.io/install/configuration and https://docs.rke2.io/reference/server_config |
| RKE2 datastores | https://docs.rke2.io/datastore/embedded and https://docs.rke2.io/datastore/external |
| RKE2 tokens and certificates | https://docs.rke2.io/security/token and https://docs.rke2.io/security/certificates |
| RKE2 air gap | https://docs.rke2.io/install/airgap and https://github.com/rancher/rke2/releases |
| RKE2 CIS and Pod Security | https://docs.rke2.io/security/hardening_guide, https://docs.rke2.io/security/pod_security_standards, and the versioned CIS self-assessment pages |
| RKE2 supervisor/network requirements | https://docs.rke2.io/install/requirements and https://docs.rke2.io/advanced |
| RKE2 builds and releases | https://github.com/rancher/rke2/blob/master/BUILDING.md and https://github.com/rancher/rke2/releases |
| Helm controller | https://github.com/k3s-io/helm-controller/ plus the k3s/RKE2 Helm AddOn pages |
| Cilium | https://docs.cilium.io/ and https://github.com/cilium/cilium |
| Multus | https://github.com/k8snetworkplumbingwg/multus-cni and the k3s/RKE2 Multus pages |
| NixOS modules/packages/tests | https://github.com/NixOS/nixpkgs, `nixos/modules/services/cluster/rancher/`, `pkgs/applications/networking/cluster/{k3s,rke2}/`, and `nixos/tests/rancher/` |
| k3d | https://k3d.io/ and https://github.com/k3d-io/k3d |
| k3k | https://github.com/rancher/k3k and https://documentation.suse.com/cloudnative/suse-virtual-clusters/1.2.0/en/architecture.html |

## Research decisions

- **One CNI assumption.** All production paths use Cilium 1.20+. k3s uses
  `flannel-backend: none` plus `disable-network-policy`; RKE2 uses its
  integrated `cni: cilium` path unless the operator deliberately chooses
  `cni: none` and an upstream Cilium chart.
- **Datastore support is distro-specific.** The official k3s datastore page
  certifies SQL and external etcd; NATS works through Kine but is not listed
  as a certified k3s backend. The official RKE2 external-datastore page
  certifies etcd, MySQL, MariaDB, and PostgreSQL; it does not list NATS, so
  the RKE2 reference treats NATS as unsupported unless the vendor confirms it.
- **RKE2 has two Cilium seams.** `cni: cilium` selects the packaged
  `rke2-cilium` chart and its matching air-gap images. `cni: none` is the
  upstream-chart path and requires separate image/chart mirroring.
- **Node IPAM is not port publishing.** In the k3d lab, Cilium Node IPAM
  places node IPs in LoadBalancer status; k3d's `@loadbalancer` port mapping
  publishes host ports 80/443. They are separate mechanisms that compose.
- **NixOS evidence is source-pinned.** The NixOS reference names the exact
  nixpkgs commit used for package/module/test claims. Package defaults are
  time-dependent; use versioned attributes for reproducibility.
- **k3k mode determines Cilium behavior.** Shared mode inherits the host
  datapath and has documented Cilium NetworkPolicy caveats; virtual mode can
  run Cilium inside the nested K3s cluster with non-overlapping CIDRs.

## Exclusion handling

Excluded technologies appear only where necessary to prevent a wrong action:

- Flannel ports are mentioned as rules that are not needed for the chosen
  Cilium design.
- ServiceLB appears only in the k3d lab, where it is disabled so Cilium Node
  IPAM owns LoadBalancer status.
- Traefik is detailed only in the requested k3d ingress/Gateway lab.
- RKE2 packaged-chart inventories may name excluded components because the
  inventory is needed for air-gap and `--disable` decisions.
- Containerd remains the distro runtime; no replacement path is provided.

## Operational references produced

- [../k3s.md](../k3s.md)
- [../rke2.md](../rke2.md)
- [../integrations.md](../integrations.md)
- [../nixos.md](../nixos.md)
- [../k3d.md](../k3d.md)
- [../k3k.md](../k3k.md)
