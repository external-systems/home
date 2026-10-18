# k3s/RKE2 Shared Integrations Reference

Scope: Cilium (>=1.20), Multus, and the Rancher helm-controller on k3s and RKE2.
Distro-specific bootstrap, roles, and datastore details are in
[references/k3s.md](k3s.md) and [references/rke2.md](rke2.md).

Primary sources:
[k3s docs](https://docs.k3s.io/),
[RKE2 docs](https://docs.rke2.io/),
[Rancher helm-controller](https://github.com/k3s-io/helm-controller/),
[Cilium docs](https://docs.cilium.io/),
[Cilium source](https://github.com/cilium/cilium),
[Multus source/docs](https://github.com/k8snetworkplumbingwg/multus-cni).

---

## Version assumptions

- All clusters run **Cilium 1.20+** as the primary CNI.
- Examples are current as of the document date; confirm flag/chart values in
  the version-pinned docs for the target release. k3s and RKE2 versions move
  independently.

---

## Replacing default networking with Cilium

### Bootstrap ordering

1. Choose the CNI **before** first server start. Neither distribution supports
   switching the primary CNI on a running cluster without rebuilding.
2. Disable the distribution's conflicting default networking components at
   bootstrap.
3. Ensure API-server reachability throughout.
4. Install Cilium before scheduling workloads.
5. Validate with `cilium status --wait` and `cilium connectivity test`.

### k3s

```yaml
# /etc/rancher/k3s/config.yaml
flannel-backend: none
disable-network-policy: true
# add only if Cilium replaces kube-proxy:
# disable-kube-proxy: true
```

Install Cilium after the server is up, matching the default k3s pod CIDR:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cilium install --set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16"
```

For full kube-proxy replacement, also pass
`--set kubeProxyReplacement=true --set k8sServiceHost=<API_IP> --set k8sServicePort=6443`.

([k3s Basic Network Options](https://docs.k3s.io/networking/basic-network-options),
[Cilium Installation Using K3s](https://docs.cilium.io/en/stable/installation/k3s/))

### RKE2

```yaml
# /etc/rancher/rke2/config.yaml
cni: cilium
# add only if Cilium replaces kube-proxy:
# disable-kube-proxy: true
```

Place a `HelmChartConfig` in `/var/lib/rancher/rke2/server/manifests/` **before**
first start:

```yaml
# /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: true
    k8sServiceHost: <KUBE_API_SERVER_IP>
    k8sServicePort: <KUBE_API_SERVER_PORT>
```

Use a stable endpoint for `k8sServiceHost` (LB VIP in HA, fixed first-server
IP, or `127.0.0.1` only for single-node labs). Alternatively, set `cni: none`
and install the upstream Cilium Helm chart; this requires mirroring upstream
images in air-gapped environments.

([RKE2 Basic Network Options](https://docs.rke2.io/networking/basic_network_options),
[RKE2 Networking Services](https://docs.rke2.io/networking/networking_services),
[Cilium RKE/RKE2 Installation](https://docs.cilium.io/en/stable/installation/k8s-install-rke/))

### kube-proxy replacement

| Goal | k3s flags | RKE2 config |
|------|-----------|-------------|
| Cilium CNI only | `--flannel-backend=none --disable-network-policy` | `cni: cilium` |
| Cilium replaces kube-proxy | add `--disable-kube-proxy` | add `disable-kube-proxy: true` and `kubeProxyReplacement: true` |

Do not run `kubeProxyReplacement: true` alongside the distribution's kube-proxy
long-term; they compete for service datapath ownership.

### API-server reachability

- k3s agents tunnel to the server on TCP 6443; agents do not need inbound 10250.
  On agentless k3s servers with Cilium, set `--egress-selector-mode=pod` or
  `cluster` so the API server can reach services and webhooks.
- RKE2 agents connect to the supervisor API on TCP 9345 and Kubernetes API on
  TCP 6443.
- In kube-proxy-free mode, `k8sServiceHost`/`k8sServicePort` must point at a
  stable, reachable API endpoint, not a ClusterIP.

### Validation

```bash
cilium status --wait
cilium connectivity test
kubectl get nodes
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n kube-system -l name=cilium-operator
```

---

## Multus alongside Cilium

Multus is a CNI multiplexer. Cilium remains the default network (`eth0`);
Multus attaches extra interfaces via `NetworkAttachmentDefinition` resources.

### k3s

Deploy Multus with the `rke2-multus` chart, overriding CNI paths for k3s:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: multus
  namespace: kube-system
spec:
  repo: https://rke2-charts.rancher.io
  chart: rke2-multus
  targetNamespace: kube-system
  valuesContent: |-
    config:
      fullnameOverride: multus
      cni_conf:
        confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
        binDir: /var/lib/rancher/k3s/data/cni/
        kubeconfig: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
        multusAutoconfigDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
```

`multusAutoconfigDir` is for rke2-multus >= v4.2.202; comment it for older
chart versions.

([k3s Multus and IPAM Plugins](https://docs.k3s.io/networking/multus-ipams))

### RKE2

```yaml
# /etc/rancher/rke2/config.yaml
cni:
  - multus
  - cilium
```

On older releases, disable Cilium's `cni.exclusive` mode:

```yaml
# /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    cni:
      exclusive: false
```

Version gate: `exclusive: false` is **not required** starting with
November 2025 releases (`v1.31.14+rke2r1`, `v1.32.10+rke2r1`, `v1.33.6+rke2r1`,
`v1.34.2+rke2r1`).

([RKE2 Multus/SR-IOV](https://docs.rke2.io/networking/multus_sriov))

### NetworkAttachmentDefinitions

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-whereabouts
spec:
  config: '{
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "ipam": { "type": "whereabouts", "range": "192.168.10.0/24" }
    }'
```

Reference from a pod:

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: macvlan-whereabouts@eth1
```

([Multus Quickstart](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md))

### Validation and common failure modes

| Check | Command / observation |
|-------|----------------------|
| Multus pods running | `kubectl get pods -A -l app=multus` |
| CNI config generated | `ls /etc/cni/net.d/00-multus.conf` on a node |
| Extra interface present | `kubectl exec <pod> -- ip addr` |
| Network status recorded | `kubectl describe pod <pod>` -> `k8s.v1.cni.cncf.io/network-status` |

Common failures: RKE2 `cni.exclusive: true` on older releases (set `false`);
wrong k3s `binDir`/`confDir`; missing secondary CNI binary; `host-local` IPAM
on multi-node clusters; pod stuck `ContainerCreating` (check `kubectl describe
pod` and Multus pod logs).

---

## Rancher helm-controller

Both distributions embed the
[Rancher helm-controller](https://github.com/k3s-io/helm-controller/), which
reconciles `HelmChart` and `HelmChartConfig` resources (`helm.cattle.io/v1`).

### HelmChart and HelmChartConfig behavior

- `HelmChart` declares a chart to install, upgrade, or uninstall.
- `HelmChartConfig` overrides values for an existing `HelmChart`; `name` and
  `namespace` must match the target chart.
- Values precedence (lowest to highest): chart defaults, HelmChart
  `valuesContent`, HelmChart `valuesSecrets`, HelmChartConfig `valuesContent`,
  HelmChartConfig `valuesSecrets`, HelmChart `set`.

Key `HelmChart` fields:

| Field | Purpose |
|-------|---------|
| `spec.chart` | Chart name, HTTPS URL to `.tgz`, or `%{KUBERNETES_API}%` path |
| `spec.repo` / `spec.version` | Helm repository URL and chart version |
| `spec.targetNamespace` / `spec.createNamespace` | Target namespace |
| `spec.valuesContent` / `spec.valuesSecrets` / `spec.set` | Values overrides |
| `spec.chartContent` | Base64-encoded chart tarball (air-gap) |
| `spec.bootstrap` | Mark chart as cluster-critical (CNI, CCM) |
| `spec.failurePolicy` | `abort`, `reinstall` (default), or `retry` |
| `spec.timeout` / `spec.backOffLimit` | Helm job timeout and retries |
| `spec.jobImage` | Helm job image (default `rancher/klipper-helm`) |

([k3s Helm AddOns](https://docs.k3s.io/add-ons/helm),
[RKE2 Helm AddOns](https://docs.rke2.io/add-ons/helm),
[helm-controller API Reference](https://github.com/k3s-io/helm-controller/blob/master/doc/helmchart.md))

### RBAC and repository credentials

- Basic auth repo credentials: Secret type `kubernetes.io/basic-auth`,
  referenced by `spec.authSecret`.
- OCI registry credentials for chart repos: Secret type
  `kubernetes.io/dockerconfigjson`, referenced by `spec.dockerRegistrySecret`.
- Repo TLS CA: `spec.repoCA` (PEM string) or `spec.repoCAConfigMap`.
- All referenced Secrets must live in the **same namespace as the HelmChart**.

### Bootstrap vs add-on semantics

- Manifests dropped in `/var/lib/rancher/{k3s,rke2}/server/manifests/` are
  tracked as `AddOn` resources (`kubectl get addon -A`).
- Deleting a manifest file **does not** delete the deployed resources.
- `spec.bootstrap: true` marks infrastructure-critical charts (CNI, CCM) for
  cluster bring-up. Do not set it on user workloads.
- Disable packaged components via `--disable` / `disable:` rather than deleting
  manifests.

### Failure inspection

```bash
kubectl get helmchart -A
kubectl describe helmchart <name> -n kube-system
kubectl get jobs -n kube-system -l helmcharts.cattle.io/chart=<name>
kubectl logs -n kube-system job/<helm-chart-job-name>
kubectl get addon -A
kubectl describe addon <name> -n kube-system
```

### Safe changes

- Set `failurePolicy: abort` for critical infrastructure charts. The default
  `reinstall` can uninstall and reinstall on failure, tearing down networking
  or deleting CRDs.
- Change one value at a time in production; CNI upgrades can restart DaemonSets.
- Stage `HelmChartConfig` for CNI charts before first start.
- Keep chart versions matched to the distribution's Kubernetes version.

---

## Fetching or inspecting embedded charts and image lists

### Embedded chart locations

| Distribution | Manifests (AddOns) | Packaged chart tarballs |
|--------------|-------------------|-------------------------|
| k3s | `/var/lib/rancher/k3s/server/manifests/` | `/var/lib/rancher/k3s/server/static/charts/` |
| RKE2 | `/var/lib/rancher/rke2/server/manifests/` | `/var/lib/rancher/rke2/server/static/charts/` |

k3s serves static charts via `%{KUBERNETES_API}%`, e.g.
`https://%{KUBERNETES_API}%/static/charts/<chart>-<version>.tgz`.

Inspect packaged values:

```bash
ls /var/lib/rancher/{k3s,rke2}/server/static/charts/
tar -xzf /var/lib/rancher/k3s/server/static/charts/<chart>-<version>.tgz -C /tmp/
cat /tmp/<chart>/values.yaml
```

RKE2 charts repo: https://github.com/rancher/rke2-charts.

### Image lists from release artifacts

- **k3s**: `k3s-airgap-images-<arch>.tar.zst` from the
  [k3s releases](https://github.com/k3s-io/k3s/releases). Inspect contents with
  `tar --list -f k3s-airgap-images-amd64.tar.zst`.
- **RKE2**: component tarballs from the
  [RKE2 releases](https://github.com/rancher/rke2/releases):
  `rke2-images-core.<arch>.tar.zst`, `rke2-images-cilium.<arch>.tar.zst`,
  `rke2-images-multus.<arch>.tar.zst`, `rke2-images-all.<arch>.tar.zst`.
  Corresponding `.txt` files list images.

```bash
curl -LO https://github.com/rancher/rke2/releases/download/v1.34.3%2Brke2r1/rke2-images-cilium.linux-amd64.txt
```

---

## Host firewall and networking constraints

### k3s node ports

| Protocol | Port | Scope | Purpose |
|----------|------|-------|---------|
| TCP | 6443 | Agents → servers | Supervisor and Kubernetes API |
| TCP | 6443 | All nodes ↔ all nodes | Embedded registry mirror (Spegel) |
| TCP | 2379-2380 | Servers ↔ servers | Embedded etcd |
| TCP | 10250 | All nodes ↔ all nodes | Kubelet metrics/API |
| UDP | 8472 | All nodes ↔ all nodes | Flannel VXLAN; **not needed with Cilium** |
| UDP | 51820/51821 | All nodes ↔ all nodes | Flannel WireGuard; **not needed with Cilium** |
| TCP | 5001 | All nodes ↔ all nodes | Spegel peer index |

([k3s Requirements](https://docs.k3s.io/installation/requirements))

### RKE2 node ports

| Protocol | Port | Scope | Purpose |
|----------|------|-------|---------|
| TCP | 6443 | All nodes → servers | Kubernetes API |
| TCP | 9345 | All nodes → servers | RKE2 supervisor API |
| TCP | 10250 | All nodes ↔ all nodes | Kubelet metrics |
| TCP | 2379/2380/2381 | Servers ↔ servers | etcd client/peer/metrics |
| TCP | 30000-32767 | All nodes ↔ all nodes | NodePort range |

([RKE2 Requirements](https://docs.rke2.io/install/requirements))

### Cilium-specific ports (configuration-dependent)

Only open ports matching the active Cilium datapath and features.

| Protocol | Port | Required when | Purpose |
|----------|------|---------------|---------|
| UDP | 8472 | VXLAN overlay mode | Pod-to-pod VXLAN encapsulation |
| UDP | 6081 | Geneve overlay mode | Pod-to-pod Geneve encapsulation |
| TCP | 4240 | Recommended | `cilium-health` node checks |
| ICMP | 8/0 | Recommended | `cilium-health` ping checks |
| UDP | 51871 | WireGuard enabled | WireGuard tunnel endpoint |
| TCP | 4244/4245 | Hubble/Relay enabled | Hubble server / Relay |
| TCP | 9962/9963/9964 | Prometheus enabled | Agent/operator/envoy metrics |

In direct routing / native mode, UDP 8472/6081 are not needed; the underlay must
route pod IPs.

([Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/))

---

## Air-gap considerations

### Image sources

- **k3s**: place `k3s-airgap-images-<arch>.tar.zst` in
  `/var/lib/rancher/k3s/agent/images/` before start, or retag images into a
  private registry via `registries.yaml`.
- **RKE2**: place tarballs in `/var/lib/rancher/rke2/agent/images/` before
  start. Minimum: `rke2-images-core.<arch>.tar.zst`. Add
  `rke2-images-cilium.<arch>.tar.zst` for integrated Cilium, or
  `rke2-images-multus.<arch>.tar.zst` for Multus.

([k3s Air-Gap Install](https://docs.k3s.io/installation/airgap),
[RKE2 Air-Gap Install](https://docs.rke2.io/install/airgap))

### Cilium and Multus images

- **RKE2 integrated Cilium**: images are in `rke2-images-cilium.<arch>.tar.zst`.
- **Upstream Cilium chart on k3s / `cni: none` RKE2**: mirror
  `quay.io/cilium/cilium`, `quay.io/cilium/operator-*`, etc. to a private
  registry and configure `registries.yaml`.
- **Multus**: RKE2 provides `rke2-images-multus.<arch>.tar.zst`; k3s pulls the
  `rke2-multus` chart from `rke2-charts.rancher.io` unless mirrored.

### helm-controller in air-gapped environments

- `rancher/klipper-helm` is included in the k3s/RKE2 air-gap tarballs.
- External chart repos need a mirror or `spec.chartContent` with a base64
  tarball baked into the manifest.
- k3s packaged components using `%{KUBERNETES_API}%` work offline because they
  reference embedded static charts.

---

## Uncertainties and follow-ups

- **RKE2 static chart path**: verify `/var/lib/rancher/rke2/server/static/charts/`
  on the target node; extraction paths can vary by release.
- **Helm-controller bootstrap ordering**: `bootstrap` is a cluster-critical
  marker, but the precise reconciliation order is not documented. Treat it as
  a best-effort bring-up hint.
- **RKE2 Cilium image registry**: the `rke2-cilium` chart may use Rancher-mirrored
  image names. Confirm the exact list from `rke2-images-cilium.<arch>.txt` in
  air-gapped environments.
- **Kernel feature availability**: Cilium 1.20+ requires kernel >= 5.10 (or
  RHEL 8.10 equivalent). Specific features need newer kernels; check
  [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/).
