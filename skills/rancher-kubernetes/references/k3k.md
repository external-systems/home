# k3k reference: nested K3s clusters on Kubernetes

> Reference date: 2026-10-17. k3k latest release: **v1.2.0**. The project is still marked experimental; API and behavior can change.

[k3k](https://github.com/rancher/k3k) provisions isolated K3s clusters inside an existing Kubernetes cluster (the *host* cluster), useful for dev/test, CI, K3s feature validation, and edge/control-plane splits. Sources: [SUSE Virtual Clusters architecture](https://documentation.suse.com/cloudnative/suse-virtual-clusters/1.2.0/en/architecture.html), [k3k CRD reference](https://github.com/rancher/k3k/blob/main/docs/crds/crds.md), [k3k CLI reference](https://github.com/rancher/k3k/blob/main/docs/cli/k3kcli.md), [Cilium K3s docs](https://docs.cilium.io/en/stable/installation/k3s/).

## What k3k does

The k3k controller watches `Cluster` CRDs (`k3k.io/v1beta1`) and spins up a nested K3s cluster in a dedicated host namespace (`k3k-<clustername>` by default). The nested cluster is reachable via a generated kubeconfig.

Three provisioning modes exist:

| Mode | What runs in host cluster | Workloads run | Isolation model |
|------|---------------------------|---------------|-----------------|
| `shared` (default) | Agentless K3s control plane + k3k Virtual Kubelet | On the host cluster, in the virtual cluster's namespace | NetworkPolicy + namespace + PSA |
| `virtual` | Full K3s servers and agents as pods | Inside the nested K3s pods | Dedicated K3s control plane and workers; privileged pods |
| `hcp` (experimental) | Agentless K3s control plane only | On external worker nodes you provide | Control plane in host; workers outside it |

See the [architecture overview](https://documentation.suse.com/cloudnative/suse-virtual-clusters/1.2.0/en/architecture.html) and [mode chooser](https://documentation.suse.com/cloudnative/suse-virtual-clusters/1.2.0/en/how-tos-for-admin/choose-mode.html) for the full comparison.

## Host and nested cluster prerequisites

### Host cluster

- An existing Kubernetes cluster. k3k is tested and documented against **RKE2** and **K3s** host clusters; other CNCF-conformant clusters may work.
- A CNI that supports Kubernetes `NetworkPolicy` if you want k3k's shared-mode isolation to be meaningful.
- A default `StorageClass` if you use `persistence.type: dynamic` (the default).
- Helm 3 for controller installation.
- For `virtual` mode: nodes must allow privileged pods; the server/agent pods run privileged by default so the nested kubelet/container runtime can function.
- For `hcp` mode: an externally reachable endpoint for the nested API server (`NodePort`, `LoadBalancer`, or `Ingress`) and a non-loopback entry in `spec.tlsSANs`.

### Nested cluster

- Only **K3s** distributions are supported. Set `spec.version` to a K3s release such as `v1.33.1-k3s1`.
- In `shared` mode the nested cluster inherits the host's CNI and storage classes.
- In `virtual` mode the nested cluster runs its own CNI; you must choose CIDRs that do not conflict with the host (`clusterCIDR` defaults to `10.52.0.0/16`, `serviceCIDR` to `10.53.0.0/16`).

## Install the k3k controller and CLI

### Controller via Helm

```bash
helm repo add k3k https://rancher.github.io/k3k
helm repo update
helm install --namespace k3k-system --create-namespace k3k k3k/k3k
```

The controller watches `Cluster` and `VirtualClusterPolicy` CRDs in `k3k.io/v1beta1` and creates one namespace per virtual cluster.

### k3k CLI

Download the release binary matching your architecture:

```bash
wget -qO k3kcli https://github.com/rancher/k3k/releases/download/v1.2.0/k3kcli-linux-amd64
chmod +x k3kcli
sudo mv k3kcli /usr/local/bin
k3kcli --version
```

The CLI respects the same kubeconfig precedence as `kubectl`: `--kubeconfig` flag, `$KUBECONFIG`, then `~/.kube/config`.

## Create and delete a virtual cluster

### Quick CLI creation

```bash
# shared mode, dynamic persistence, 1 server
k3kcli cluster create mycluster

# virtual mode HA
k3kcli cluster create --mode virtual --servers 3 --agents 3 my-vcluster

# ephemeral, no persistence
k3kcli cluster create --persistence-type ephemeral my-ephemeral

# custom K3s version and storage class
k3kcli cluster create --version v1.33.1-k3s1 --storage-class-name local-path my-cluster
```

### CRD creation

```yaml
apiVersion: k3k.io/v1beta1
kind: Cluster
metadata:
  name: mycluster
  namespace: default
spec:
  mode: shared
  version: v1.33.1-k3s1
  servers: 1
  persistence:
    type: dynamic
    storageClassName: local-path
    storageRequestSize: 30Gi
```

The controller creates resources in a namespace named `k3k-mycluster` by default (or the namespace you specify).

### Delete

```bash
k3kcli cluster delete mycluster
# keep PVCs:
k3kcli cluster delete --keep-data mycluster
```

## Retrieve and use the kubeconfig

The CLI can generate a kubeconfig for the nested cluster. Pass the namespace explicitly; the CLI otherwise defaults to `default`:

```bash
k3kcli kubeconfig generate --namespace k3k-mycluster --name mycluster
ls *kubeconfig*.yaml
export KUBECONFIG=$PWD/<generated-kubeconfig>.yaml
kubectl get nodes
```

For Rancher-managed host clusters, override the server address so the kubeconfig points at the right endpoint:

```bash
k3kcli cluster create --kubeconfig-server https://<host-node-or-lb-ip> mycluster
```

For `hcp` mode, `k3kcli kubeconfig generate` also prints the K3s join command for external workers.

## Server/agent/worker modes

- `servers`: number of K3s control-plane pods. Default `1`. Use an odd number (3, 5) for HA via embedded etcd.
- `agents`: number of K3s worker pods. Default `0`. **Ignored in `shared` mode** because the Virtual Kubelet schedules workloads onto the host cluster.
- `hcp` mode: `agents` is not used. Workers are external machines that join with the standard K3s installer:

  ```bash
  curl -sfL https://get.k3s.io | K3S_URL=https://<apiserver>:<port> K3S_TOKEN=<token> sh -
  ```

  Each external worker needs a unique routable IP and unique hostname; NAT-shared addresses cause multiple workers to register as one node.

## Persistence, storage, and networking

### Persistence

| `persistence.type` | Behavior |
|--------------------|----------|
| `dynamic` (default) | PVC for etcd/server state; requires a default or named `StorageClass`. The generated CRD reference says the default request is `2G`, while the SUSE guide says `1Gi`; verify the target release. |
| `ephemeral` | State in `emptyDir`; lost on pod restart |

Dynamic persistence is configured via:

```yaml
spec:
  persistence:
    type: dynamic
    storageClassName: local-path
    storageRequestSize: 30Gi
```

### Storage in shared mode

- PVCs created inside the virtual cluster are synced to the host cluster and provisioned by the host's storage provider.
- k3k creates a "pseudo" PV inside the virtual cluster so pods can be scheduled immediately.
- If a PVC references a `StorageClass`, that class must already exist on the host. k3k can sync host `StorageClass` objects into the virtual cluster when `spec.sync.storageClasses.enabled: true`.

### Storage in virtual/HCP mode

- `virtual` mode: bring your own storage provider inside the nested K3s cluster.
- `hcp` mode: storage is whatever you configure on the external worker nodes.

### Networking defaults

| Mode | Default `clusterCIDR` | Default `serviceCIDR` | Notes |
|------|----------------------|----------------------|-------|
| `shared` | `10.42.0.0/16` | `10.43.0.0/16` | Must match host `serviceCIDR` to avoid conflicts |
| `virtual` | `10.52.0.0/16` | `10.53.0.0/16` | Must differ from host CIDRs |
| `hcp` | configurable | configurable | Pod/Service CIDRs live on external workers |

Set CIDRs and DNS explicitly if they overlap with the host or with other k3k clusters:

```yaml
spec:
  clusterCIDR: 10.44.0.0/16
  serviceCIDR: 10.45.0.0/16
  clusterDNS: 10.45.0.10
```

## Expose and access the nested API server

By default the API server is exposed only as a `ClusterIP` inside the host cluster. To reach it from outside, use `spec.expose`:

### NodePort

```yaml
spec:
  tlsSANs:
    - 203.0.113.10
  expose:
    nodePort:
      serverPort: 30001
```

### LoadBalancer

```yaml
spec:
  tlsSANs:
    - my-cluster.example.com
  expose:
    loadBalancer:
      serverPort: 443
```

### Ingress (requires TLS passthrough)

The K3s API server uses mTLS, so TLS must **not** be terminated by the ingress controller. Use an ingress controller that supports SSL passthrough (e.g., ingress-nginx with `--enable-ssl-passthrough`).

```yaml
spec:
  tlsSANs:
    - my-cluster.example.com
  expose:
    ingress:
      ingressClassName: nginx
      annotations:
        nginx.ingress.kubernetes.io/ssl-passthrough: "true"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
        nginx.ingress.kubernetes.io/ssl-redirect: "HTTPS"
```

Use an ingress class that supports layer-4 TLS passthrough. If the available ingress implementation cannot do that, use `expose.loadBalancer` or `expose.nodePort` instead.

## Upgrades

Use `k3kcli cluster update` to change the K3s version or scale servers/agents:

```bash
# upgrade the K3s version
k3kcli cluster update --version v1.33.2-k3s1 mycluster

# scale servers (HA)
k3kcli cluster update --servers 3 mycluster

# scale agents in virtual mode
k3kcli cluster update --agents 3 my-vcluster
```

The CLI prompts for confirmation unless you pass `-y/--no-confirm`. Check status with `kubectl describe cluster <cluster>` and controller logs with `kubectl logs -n k3k-system -l app.kubernetes.io/name=k3k`. v1.2.0 fixes a v1.1.0 → v1.2.0 upgrade bug involving an immutable StatefulSet field.

## Observability

k3k does not ship its own metrics stack. Use standard host-cluster tooling: controller logs (`kubectl logs -n k3k-system -l app.kubernetes.io/name=k3k`), cluster logs (`kubectl logs -n k3k-<cluster> -l cluster=<cluster>`), and `kubectl describe cluster <cluster>`. In `shared` mode workloads are host pods and can be scraped by host Prometheus; in `virtual` mode deploy metrics tooling inside the nested cluster.

## Troubleshooting

Common failure modes:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Cluster stuck `Pending` | PVC not bound | Check `kubectl get pvc -n k3k-<cluster>`; ensure a default `StorageClass` exists or set `storageClassName` correctly |
| Server pod `Pending` | Invalid `nodeSelector` or no matching node | Verify node labels and `kubectl describe pod` |
| `ImagePullBackOff` | Air-gapped/missing image | Ensure images are mirrored to the configured registry |
| Shared-mode kubelet `CrashLoopBackOff` | NetworkPolicy blocking host API server (Cilium) | Upgrade to k3k v1.2.0+; verify Cilium NetworkPolicy semantics |
| `too many open files` in k3k pods | Low inotify limits on host | Raise `fs.inotify.max_user_watches`, `max_user_instances`, `max_queued_events` on host nodes |
| HCP workers cannot join | Missing external endpoint or wrong SAN | Add `expose.nodePort`/`loadBalancer`/`ingress` and put the worker-facing host in `spec.tlsSANs` |
| Dual-stack host: NetworkPolicy rejected | IPv6 PodCIDR placed in IPv4 `ipBlock.except` | Track [k3k#1143](https://github.com/rancher/k3k/issues/1143); currently no clean fix |

## Cleanup

Delete clusters before uninstalling the controller to avoid orphaned resources:

```bash
k3kcli cluster delete --all
helm uninstall -n k3k-system k3k
kubectl delete ns k3k-system
```

## Security, isolation, and production caveats

- k3k is **experimental**. Do not run untrusted production multi-tenant workloads without reviewing the isolation model.
- `shared` mode isolation relies on Kubernetes `NetworkPolicy` and is strongest with a CNI whose `ipBlock` semantics match the intended literal CIDR filtering. On **Cilium**, the generated policy's `ipBlock.except` semantics do not provide the intended host/cluster isolation in all configurations (see below).
- `virtual` mode server/agent pods run **privileged** by default. A privileged pod inside the nested cluster therefore has full privileges on the host node. Mitigate with `runtimeClassName: kata-qemu` (experimental) or `securityContext`/`podSecurityContext` overrides where supported.
- Pod Security Admission inside a virtual cluster is controlled by its owner and does not protect the host cluster.
- `hcp` mode exposes the API server externally; protect the join token (a Secret in the virtual cluster namespace) like any cluster credential.
- Use `VirtualClusterPolicy` to enforce mode restrictions, quotas, limit ranges, PSA levels, and network policy defaults per namespace.

Example policy binding:

```yaml
apiVersion: k3k.io/v1beta1
kind: VirtualClusterPolicy
metadata:
  name: shared-only
spec:
  allowedMode: shared
  quota:
    hard:
      cpu: "10"
      memory: 20Gi
      pods: "20"
  podSecurityAdmissionLevel: baseline
---
apiVersion: v1
kind: Namespace
metadata:
  name: dev-clusters
  labels:
    policy.k3k.io/policy-name: shared-only
```

## Cilium interaction

k3k's relationship with Cilium is nuanced and depends on the mode and the Cilium version.

### Verified support

- **Host cluster running Cilium:** k3k shared mode works on Cilium-based RKE2/K3s host clusters starting with k3k v1.2.0, which fixed a NetworkPolicy issue that blocked the k3k-kubelet from reaching the host API server ([k3k#443](https://github.com/rancher/k3k/issues/443), fixed by [#989](https://github.com/rancher/k3k/pull/989)).
- **Nested K3s with Cilium:** In `virtual` mode you can run Cilium inside the nested K3s cluster. Install K3s with `--flannel-backend=none --disable-network-policy`, then install Cilium with a pod CIDR matching the nested cluster's `clusterCIDR` (see [Cilium K3s install docs](https://docs.cilium.io/en/stable/installation/k3s/)).

### Known limitations with Cilium

- **Shared-mode NetworkPolicy semantics:** Cilium translates `ipBlock.cidr: 0.0.0.0/0` to "world/external" identities, not all IP addresses. As a result, the generated `except` list of PodCIDRs may not block traffic to the host API server or other in-cluster destinations the way it does on CNIs that interpret `ipBlock` literally. On multi-pool IPAM setups, the except list may even exclude nonexistent CIDRs, giving no cross-cluster isolation while appearing to work ([k3k#443](https://github.com/rancher/k3k/issues/443), [k3k#1142](https://github.com/rancher/k3k/issues/1142)).
- **Dual-stack hosts:** k3k v1.2.0 can generate an invalid NetworkPolicy on dual-stack clusters by placing IPv6 PodCIDRs into the IPv4 `ipBlock.except` list; the API rejects the policy and the virtual cluster is left unisolated ([k3k#1143](https://github.com/rancher/k3k/issues/1143)).
- **Ingress allow-all:** The generated NetworkPolicy ingress rule is `[{}]` (allow all) as of the current docs/issues, so workloads are not protected from incoming traffic from other host namespaces.

### Experimental suggestions (not verified by k3k docs)

- On Cilium host clusters, you may layer your own `CiliumNetworkPolicy`/`CiliumClusterwideNetworkPolicy` on top of k3k's generated policy for stronger isolation. Not a documented k3k workflow.
- Inside `virtual` mode, install Cilium with `--flannel-backend=none --disable-network-policy --disable-kube-proxy` and a pod CIDR matching `spec.clusterCIDR`, non-overlapping with the host.

## Decision cues

| Goal | Recommended mode | Why |
|------|------------------|-----|
| Fast, low-overhead dev/CI clusters | `shared` | Lightweight, uses host resources, supports GPU passthrough |
| Strong isolation, custom CNI, or API feature testing | `virtual` | Full K3s stack per cluster, but higher overhead and privileged pods |
| Managed control plane with real bare-metal/edge workers | `hcp` (experimental) | Control plane in host, workers outside; requires external API endpoint |
| Untrusted multi-tenant workloads | None without extra safeguards | Shared-mode isolation is policy-based; virtual mode uses privileged pods |

## Version-dependent caveats

- v1.2.0 added `hcp` mode, external datastore support, StorageClass sync, and the shared-mode Cilium NetworkPolicy fix; it also fixes the v1.1.0 → v1.2.0 upgrade path.
- Not all CRD fields have CLI equivalents (e.g., `serverLimit`/`workerLimit`, `nodeSelector`, `storageRequestSize`); use the CRD when the CLI lacks a flag.
- `k3k.io/v1beta1` is the current API version; older `v1alpha1` references are obsolete.

## Uncertainties and follow-up

- NetworkPolicy behavior on Cilium is still evolving; verify with your Cilium version and IPAM mode before relying on shared-mode isolation.
- `hcp` mode is experimental; expect API changes.
- External datastore docs were not reachable in the v1.2.0 tree at writing; the Kata Containers how-to provides a working `secretMounts` pattern.
