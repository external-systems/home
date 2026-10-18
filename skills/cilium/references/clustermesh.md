# Cilium 1.20 Cluster Mesh

Cluster Mesh extends Cilium networking across multiple Kubernetes
clusters, providing pod-to-pod connectivity, cluster-aware policy
enforcement, cross-cluster service discovery/load-balancing, and
service affinity.

## Architecture

- Per-cluster control plane runs as `clustermesh-apiserver` pods
  containing:
  - `etcd` (embedded, no persistent storage)
  - `apiserver` (syncs local state)
  - `kvstoremesh` (syncs remote state)
- Pod-to-pod traffic is forwarded directly between nodes; no extra
  proxy/gateway.
- In kvstore mode, Cluster Mesh extends the existing etcd instead of
  deploying a new one.
- All connected clusters form a single trust domain. Cilium
  sanity-checks remote state but cannot fully prevent a compromised
  cluster from propagating malicious information.

## Requirements

- Same datapath mode in all clusters.
- Cilium versions may differ by **no more than one minor release**.
- Unique, non-conflicting PodCIDR ranges across all clusters/nodes.
- Node InternalIP connectivity between clusters (peering/VPN).
- Firewall rules must allow inter-cluster traffic on the documented
  ports.
- Native-routed mode: `ipv4NativeRoutingCIDR` must cover all PodCIDRs;
  pods must have IP connectivity across clusters.
- `maxConnectedClusters`: default `255` (max local identities 65535);
  can be `511` (max local identities 32767). Must be the same in all
  clusters and set at install time; changing it live can disrupt
  connectivity/policy enforcement.
- Unique cluster name (≤32 chars, lowercase alnum/dash) and numeric
  cluster ID (1–255). Changing either requires restarting all
  workloads.

## TLS configuration

- Control-plane connections use mTLS. Auto options: certgen CronJob,
  cert-manager, or Helm. Every cluster must trust the others; use a
  common CA or `tls.caBundle`.
- Certgen default validity is 1 year; cronJob mode regenerates every 4
  months in Cilium 1.20.
- Helm-generated certs are only renewed when the chart is re-rendered
  (typically during upgrade); upgrade at least annually or set a longer
  `certValidityDuration`.
- In Cilium 1.20, `clustermesh.apiserver.tls.server.{extraDnsNames,extraIpAddresses}`
  are replaced by `clustermesh.apiserver.tls.auto.server.*` (old values
  still fall back).
- `clustermesh-apiserver.cilium.io` DNS name is no longer included by
  default.

## Service discovery and load balancing

- **Global Services**: identical Service name/namespace in each cluster
  + annotation `service.cilium.io/global: "true"`.
  - `service.cilium.io/shared: "true"` is the default.
  - `shared: "false"` exports remote backends without sharing local
    ones.
- **Service affinity**: `service.cilium.io/affinity: "none|local|remote"`.
- **EndpointSlice synchronization** (beta):
  `clustermesh.enableEndpointSliceSynchronization=true`; default off
  for non-headless Global Services, default on for headless. Needed for
  some third-party controllers/ingress controllers that read
  EndpointSlices.
- **MCS-API**: Kubernetes SIG-Multicluster standard using
  `ServiceExport`/`ServiceImport`. Enable with
  `clustermesh.mcsapi.enabled=true`; CoreDNS 1.12.2+ required. Cilium
  can auto-configure CoreDNS with
  `clustermesh.mcsapi.corednsAutoConfigure.enabled=true`.
- `clustermesh.cacheTTL` (default `0s`) revokes cached remote-cluster
  data after a duration of unreachable-ness; `0s` means never revoke.

## Network policy across clusters

- Policy enforcement automatically spans clusters, but K8s policies are
  **not** automatically distributed; apply `CiliumNetworkPolicy` /
  `NetworkPolicy` in every cluster.
- Use label `io.cilium.k8s.policy.cluster` to target specific clusters.
- `policy-default-local-cluster` (introduced 1.18, default in 1.19)
  restricts endpoint selection to the local cluster by default; set
  `clustermesh.policyDefaultLocalCluster` to migrate.

## Limitations

- Global NodePort Services load-balance across local+remote backends
  only with `kubeProxyReplacement=true`.
- Node/host-network access to global services needs SocketLB
  host-namespace support (`socketLB.enabled=true`,
  `socketLB.hostNamespaceOnly=true`); otherwise only local backends are
  used.

## Verification and troubleshooting entry points

```bash
# control-plane health
cilium clustermesh status --wait
kubectl -n kube-system exec ds/cilium -- cilium-dbg troubleshoot clustermesh
kubectl -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh \
  -- clustermesh-apiserver kvstoremesh-dbg troubleshoot

# state propagation
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --all-clusters
kubectl -n kube-system exec ds/cilium -- cilium-dbg node list
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show backends

# peer config files mounted in agents
kubectl -n kube-system exec ds/cilium -c cilium-agent -- ls /var/lib/cilium/clustermesh
```

## References

- [Cluster Mesh intro](https://docs.cilium.io/en/v1.20/network/clustermesh/intro/)
- [Cluster Mesh setup](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/)
- [Load-balancing & Service Discovery](https://docs.cilium.io/en/v1.20/network/clustermesh/load-balancing/)
- [Global Services](https://docs.cilium.io/en/v1.20/network/clustermesh/global-services/)
- [Service Affinity](https://docs.cilium.io/en/v1.20/network/clustermesh/affinity/)
- [MCS-API](https://docs.cilium.io/en/v1.20/network/clustermesh/mcsapi/)
- [Cluster Mesh policy](https://docs.cilium.io/en/v1.20/network/clustermesh/policy/)
- [Upgrade guide](https://docs.cilium.io/en/v1.20/operations/upgrade/)
