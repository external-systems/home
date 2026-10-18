---
name: rancher-kubernetes
description: "Rancher k3s and RKE2 cluster operations: bootstrap, server/agent roles, config files and CLI flags, certificates and join tokens, etcd/Kine datastores, air-gapped installs, Cilium and Multus, Rancher helm-controller, RKE2 CIS and Pod Security, API/supervisor behavior, NixOS modules and VM tests, k3d Docker labs, and k3k nested clusters. Load for configuring, securing, upgrading, or troubleshooting a Rancher Kubernetes cluster, even when the user only says 'Rancher cluster' or names one of those features. Rancher Manager/dashboard workflows belong elsewhere."
---

# rancher-kubernetes

Operational reference for Rancher's Kubernetes distributions:
[k3s](https://docs.k3s.io/) and [RKE2](https://docs.rke2.io/), plus
[k3d](https://k3d.io/) Docker labs and [k3k](https://github.com/rancher/k3k)
nested clusters. Every production cluster described here uses **Cilium 1.20+**
as its CNI.

This skill covers the distributions themselves. Route Rancher Manager,
Fleet, and dashboard-driven provisioning to their own documentation; this
skill starts at a host that will run `k3s` or `rke2`, or at an existing
cluster that needs one of the listed integrations.

## Version rule

k3s, RKE2, Cilium, k3d, k3k, and the NixOS modules all move independently.
Identify the exact distro version and host OS before translating any example
into a command. Prefer version-pinned documentation for the target release;
the references cite official sources and call out version-sensitive behavior
where it matters. A nearby flag name from another release is not evidence
that the same flag, default, or support status applies here.

## Route the task

First identify four things: the distribution (`k3s` or `rke2`), the role
(server/control-plane or agent/worker), the datastore (embedded etcd,
external SQL, or NATS/Kine only after confirming distro support), and the
lifecycle stage (bootstrap, join,
upgrade, certificate/token work, integration, or lab). Then open the branch
reference below. Each reference carries its own primary-source citations.

| Branch | Read |
|---|---|
| k3s bootstrap, roles, config, certs, tokens, datastores, Tailscale, air gap, builds | [references/k3s.md](references/k3s.md) |
| RKE2 bootstrap, roles, config, certs, tokens, CIS, Pod Security, supervisor, air gap, builds | [references/rke2.md](references/rke2.md) |
| Cilium 1.20+, Multus, Rancher helm-controller, embedded charts/images, firewall and networking | [references/integrations.md](references/integrations.md) |
| NixOS packages/modules, k3s or RKE2 on NixOS, hermetic VM tests | [references/nixos.md](references/nixos.md) |
| k3d lifecycle, Docker-host labs, Cilium, Traefik ingress/Gateway on ports 80/443 | [references/k3d.md](references/k3d.md) |
| k3k controller, virtual/nested k3s clusters on an existing Kubernetes cluster | [references/k3k.md](references/k3k.md) |

Source-evidence notes and research decisions:
[references/research/source-map.md](references/research/source-map.md).

For deep Cilium APIs, BGP, LoadBalancer IPAM, Gateway API, network policy,
or Cilium troubleshooting, also load the repo's `cilium` skill. This skill
covers only the distribution-specific seam: making k3s/RKE2 start without a
conflicting default CNI, installing Cilium safely, and validating the result.

## Operating workflow

Use the same loop for every cluster change; the branch reference supplies
the exact flags and file locations.

1. **Profile the cluster.** Record distro and version, node roles,
   datastore, CNI mode, config source, and whether the cluster is air-gapped.
   Keep tokens, CA material, and datastore credentials out of the answer and
   out of git.
2. **Choose the smallest supported seam.** Prefer the distro's documented
   config file or NixOS module over editing generated unit files or copying
   a command from another distribution.
3. **Stage safely.** For control-plane changes, preserve an etcd snapshot or
   documented datastore backup, change one server at a time, and keep quorum.
   Treat certificate, token, datastore, and CNI changes as disruptive.
4. **Validate from the distribution outward.** Check the service and node
   health first, then the datastore, then Cilium, then workload networking.
   A green `kubectl get nodes` alone does not prove pod-to-pod or external
   connectivity.
5. **Report rollback.** State which file, service, snapshot, or Kubernetes
   object restores the previous state, and which evidence confirms recovery.

## Decision cues

- Choose **k3s** when a small footprint, edge deployment, single-node
  development cluster, or simple embedded-etcd HA path is the priority.
- Choose **RKE2** when CIS-oriented hardening, FIPS-oriented builds,
  conventional Kubernetes component layout, or the documented RKE2 security
  posture is the priority.
- Use **embedded etcd** for the standard HA control plane. Use an external
  datastore only when the specific distro reference verifies support for
  that datastore in the target version; k3s and RKE2 do not share every Kine
  capability.
- Bootstrap for **Cilium from the start**: disable only the distribution's
  conflicting default network component, install Cilium before treating the
  cluster as usable, and preserve API-server reachability throughout.
- Use **Multus as an additional-interface manager**, not as a replacement
  for the primary Cilium datapath, unless the workload explicitly needs a
  different chained plugin.
- Use **Rancher helm-controller** for cluster-owned addons declared as
  `HelmChart` resources; use regular Helm/GitOps tooling for user workloads
  when ownership should live outside the distribution's addon loop.
- Use **k3d** for disposable Docker-host labs and **k3k** for a virtual
  control plane nested inside an existing Kubernetes cluster. Neither is a
  substitute for a production multi-host bootstrap test.

## Scope boundaries

Keep these seams explicit so the agent does not silently solve the wrong
problem:

- Rancher Manager, Fleet, hosted provisioning, and dashboard operations are
  separate products and workflows.
- This reference assumes Cilium. Flannel and ServiceLB are not alternative
  design paths here.
- Traefik appears only in the k3d lab reference, where the requested lab
  uses it for ingress/Gateway traffic.
- Containerd is the distributions' runtime; this skill does not replace it
  with another runtime.
- Kubernetes API and workload design stay at the level needed to operate the
  distribution; deep application architecture belongs in Kubernetes docs.

## Core source map

| Project | Primary source |
|---|---|
| k3s docs | https://docs.k3s.io/ |
| k3s source | https://github.com/k3s-io/k3s |
| RKE2 docs | https://docs.rke2.io/ |
| RKE2 source | https://github.com/rancher/rke2 |
| Rancher helm-controller | https://github.com/k3s-io/helm-controller/ |
| Cilium docs | https://docs.cilium.io/ |
| Multus source/docs | https://github.com/k8snetworkplumbingwg/multus-cni |
| k3d docs/source | https://k3d.io/ and https://github.com/k3d-io/k3d |
| k3k source/docs | https://github.com/rancher/k3k |
| NixOS/nixpkgs | https://github.com/NixOS/nixpkgs |
