# RKE2 Operational Reference

> Scope: actionable operating notes for RKE2 Linux clusters. Assumes Cilium >= 1.20 is the intended CNI. Does not cover Rancher Manager, Flannel, ServiceLB deep configuration, Traefik, containerd replacement, or generic Kubernetes administration.
> Sources: [docs.rke2.io](https://docs.rke2.io) and the [rancher/rke2](https://github.com/rancher/rke2) repo (docs, `charts/`, `BUILDING.md`).

---

## 1. Server/agent roles and bootstrap

RKE2 is a single statically-linked binary. A node boots as either a `server` (control plane + etcd by default) or an `agent` (worker).

- **Server** runs the Kubernetes control plane as static pods: `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, and `etcd`. It also runs the embedded Helm controller to apply charts found in `/var/lib/rancher/rke2/server/manifests` ([architecture](https://docs.rke2.io/architecture)).
- **Agent** runs `containerd`, `kubelet`, and `kube-proxy` ([architecture](https://docs.rke2.io/architecture)).
- The first server generates the cluster CA and the server token. Additional servers/agents register against a **fixed registration address** (layer-4 LB, round-robin DNS, or VIP) using that token ([HA install](https://docs.rke2.io/install/ha)).
- Use an **odd number of server nodes** for embedded-etcd quorum ([HA install](https://docs.rke2.io/install/ha)).

### Dedicated roles

You can split etcd and control plane ([server roles](https://docs.rke2.io/install/server_roles)):

```yaml
# etcd-only node
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true

# control-plane-only node joining an existing etcd node
# server: https://<etcd-only-node>:9345
# disable-etcd: true
```

A dedicated control-plane node cannot be the first server.

### Critical values that must match across servers

`agent-token`, `cluster-cidr`, `cluster-dns`, `cluster-domain`, `disable-cloud-controller`, `disable-kube-proxy`, `egress-selector-mode`, `service-cidr` ([server config reference](https://docs.rke2.io/reference/server_config)).

---

## 2. Configuration: CLI flags vs `/etc/rancher/rke2/config.yaml` vs drop-ins

Primary configuration lives in `/etc/rancher/rke2/config.yaml`. CLI flags, env vars (`RKE2_*`), and config-file keys map to each other ([configuration](https://docs.rke2.io/install/configuration)).

```yaml
# /etc/rancher/rke2/config.yaml example (server)
token: <TOKEN>
tls-san:
  - my-kubernetes-domain.com
  - 10.0.0.10
write-kubeconfig-mode: "0644"
cni: cilium
```

- **Multiple config files**: `/etc/rancher/rke2/config.yaml` and `/etc/rancher/rke2/config.yaml.d/*.yaml` are read in alphabetical order; the last value wins. Append `+` to a key to merge list values instead of replacing them ([configuration](https://docs.rke2.io/install/configuration)).
- **Precedence**: CLI args override config-file values. For repeatable args (e.g. `--node-label`), CLI values replace the entire list ([configuration](https://docs.rke2.io/install/configuration)).
- **Kubelet config** (recommended): drop files in `/var/lib/rancher/rke2/agent/etc/kubelet.conf.d/`. Avoid passing a huge number of `--kubelet-arg` flags ([configuration](https://docs.rke2.io/install/configuration)).
- **Proxy**: set `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` in the systemd env file (`/etc/default/rke2-server` or `/etc/default/rke2-agent`). Use `CONTAINERD_*` prefixes to set proxy for containerd only ([advanced](https://docs.rke2.io/advanced)).

---

## 3. Join token and node-password lifecycle

RKE2 uses tokens for node join and to encrypt bootstrap data persisted to the datastore ([token management](https://docs.rke2.io/security/token)).

### Token formats

- **Secure/full token**: `K10<cluster CA hash>::<credentials>`. The joining node validates the server's CA hash before sending credentials.
- **Short token**: only the password. Vulnerable to MITM because the node trusts whatever CA the server presents ([token management](https://docs.rke2.io/security/token)).

### Token types

- **Server** (`--token`, file `/var/lib/rancher/rke2/server/token`): joins servers and agents; also encrypts bootstrap data. Back it up with etcd snapshots.
- **Agent** (`--agent-token`, file `/var/lib/rancher/rke2/server/agent-token`): optional separate token for agents; links to the server token if unset.
- **Bootstrap** (`rke2 token create`): short-lived Kubernetes bootstrap tokens (default TTL 24h).

Rotate the server token with `rke2 token rotate` ([token management](https://docs.rke2.io/security/token)).

### Node password

Agents register with the server token plus a randomly generated node-specific password stored at `/etc/rancher/node/password`. The server persists it as a Secret named `<host>.node-password.rke2` in `kube-system`. The Secret is deleted when the Kubernetes Node object is deleted ([advanced](https://docs.rke2.io/advanced)).

**Recovery**: if `/etc/rancher/node` is removed, either recreate the password file from the server's Secret or delete the node/password entry and restart the agent ([advanced](https://docs.rke2.io/advanced)).

---

## 4. Certificate lifecycle and rotation

RKE2 generates self-signed PKI on the first server start ([certificates](https://docs.rke2.io/security/certificates)).

- **Leaf (client/server) certificates**: valid 365 days. Certificates expired or within **120 days** of expiry are auto-renewed on RKE2 start (changed from 90 days in May 2025 releases). A Kubernetes `CertificateExpirationWarning` event is raised when within that window ([certificates](https://docs.rke2.io/security/certificates)).
- **CA certificates**: valid 10 years, **not** auto-renewed. The authoritative CA bundle is stored encrypted in the datastore bootstrap key (PBKDF2 of the server token + AES256-GCM) and extracted to `/var/lib/rancher/rke2/server/tls` on server start ([certificates](https://docs.rke2.io/security/certificates)).

### Check and rotate leaf certificates

```bash
rke2 certificate check --output table

systemctl stop rke2-server
rke2 certificate rotate              # or --service api-server,etcd,...
systemctl start rke2-server
```

Agent certificates are renewed each time `rke2-agent` starts ([certificates](https://docs.rke2.io/security/certificates), [advanced](https://docs.rke2.io/advanced)).

### Rotate CA certificates

Use `rke2 certificate rotate-ca` with a **staging directory**; never overwrite the in-use `/var/lib/rancher/rke2/server/tls`.

- For clusters started with the default self-signed CA, rotation is disruptive: nodes joined with a secure token need the new token, and pods must be restarted to trust the new root unless you cross-sign the new CA with the old one. Use the K3s `rotate-default-ca-certs.sh` example script to cross-sign ([certificates](https://docs.rke2.io/security/certificates)).
- For custom CA, non-disruptive rotation is possible as long as the same root CA signs the new intermediates. Use the K3s `generate-custom-ca-certs.sh` example script ([certificates](https://docs.rke2.io/security/certificates)).

### Custom CA at install time

Place the required CA files in `/var/lib/rancher/rke2/server/tls` **before first start**: `server-ca.crt/key`, `client-ca.crt/key`, `request-header-ca.crt/key`, `etcd/peer-ca.crt/key`, `etcd/server-ca.crt/key`, and `service.key` (the service-account token signing key). RKE2 will use them instead of generating self-signed CAs ([certificates](https://docs.rke2.io/security/certificates)).

---

## 5. Embedded etcd and external datastore support

### Embedded (default)

- **Embedded etcd** is the default datastore and the only embedded option that supports HA. One etcd pod runs per server unless disabled ([embedded datastore](https://docs.rke2.io/datastore/embedded)).
- **Embedded SQLite** is experimental and only for single-server, short-lived clusters. Enable with `disable-etcd: true` and no `server` parameter ([embedded datastore](https://docs.rke2.io/datastore/embedded)).

### External datastore

RKE2 supports external datastores via [kine](https://github.com/k3s-io/kine) for SQL databases and native etcd ([external datastore](https://docs.rke2.io/datastore/external)):

| Backend | Certified example | Endpoint prefix |
|---------|-------------------|-----------------|
| etcd | 3.6.7 | `https://etcd-1:2379,https://etcd-2:2379,...` |
| MySQL | 8.4.8 | `mysql://user:pass@tcp(host:3306)/db` |
| MariaDB | 11.4.10 | `mysql://user:pass@tcp(host:3306)/db` |
| PostgreSQL | 18.3 | `postgres://user:pass@host:port/db` |

- **PostgreSQL is supported.** RKE2 requires prepared-statement support; connection poolers like PgBouncer may need extra configuration ([external datastore](https://docs.rke2.io/datastore/external)).
> **NATS boundary:** RKE2's CLI help mentions NATS, but the official RKE2 external-datastore documentation lists only etcd, MySQL, MariaDB, and PostgreSQL. Treat NATS as unsupported for RKE2 production clusters unless SUSE/Rancher support confirms the target release.
- TLS client auth is supported via `datastore-cafile`, `datastore-certfile`, `datastore-keyfile` ([external datastore](https://docs.rke2.io/datastore/external)).
- With an external datastore, HA is provided by the database; you still need two or more servers. Network-related flags and `secrets-encryption` must match across servers ([external datastore](https://docs.rke2.io/datastore/external)).

---

## 6. Air-gapped installs and image artifacts

Air-gap artifacts are downloaded from the [GitHub releases](https://github.com/rancher/rke2/releases) page ([airgap install](https://docs.rke2.io/install/airgap)).

### Required artifacts

- The all-in-one `rke2-images.linux-amd64.tar.zst` when published, or the release's per-component tarballs.
- `rke2-images-core.linux-amd64.tar.zst` + `rke2-images-cilium.linux-amd64.tar.zst` when using integrated Cilium.
- `rke2-images-vsphere.linux-amd64.tar.zst` if enabling vSphere CPI/CSI.
- `rke2.linux-amd64.tar.gz` and `sha256sum-amd64.txt` if using `install.sh`.

For RKE2 v1.36+, the default ingress images are in `rke2-images-core`; a standalone `rke2-images-traefik` tarball may also be published. Verify the target release's artifact list rather than assuming the older tarball layout.

### Image-loading methods

1. **Private registry**: load the tar with `docker image load`, retag/push to an OCI registry, set `system-default-registry: registry.example.com:5000` and configure `registries.yaml` ([airgap install](https://docs.rke2.io/install/airgap)).
2. **Manual tarball copy**: copy the appropriate `rke2-images.*.tar.zst` into `/var/lib/rancher/rke2/agent/images/` on every node ([airgap install](https://docs.rke2.io/install/airgap)).
3. **Hauler**: aggregate artifacts in a Hauler store, save to `haul.tar.zst`, then load/extract on the air-gapped host ([airgap install](https://docs.rke2.io/install/airgap)).
4. **Embedded registry mirror**: enabled with `embedded-registry: true`; cluster nodes can mirror images to each other without external registry ([airgap install](https://docs.rke2.io/install/airgap)).

### Conditional image imports (since May 2025 releases)

Create `/var/lib/rancher/rke2/agent/images/.cache.json` so RKE2 skips re-importing unchanged tarballs across restarts. If images are pruned, clear the cache or re-touch the tarball ([airgap install](https://docs.rke2.io/install/airgap)).

### Scripted install offline

```bash
INSTALL_RKE2_ARTIFACT_PATH=/root/rke2-artifacts sh install.sh
```

The directory must contain `install.sh`, the binary tarball, the images tarball, and the checksum file ([airgap install](https://docs.rke2.io/install/airgap)).

### SELinux note

On air-gapped nodes with SELinux enforcing, manually stage and install `rke2-selinux` plus dependencies (`container-selinux`, `selinux-policy-base`, `selinux-policy`, `policycoreutils`, `iptables-nft`, `libnftnl`) before starting RKE2 ([airgap install](https://docs.rke2.io/install/airgap)).

---

## 7. Packaged components / HelmChart mechanism

RKE2 deploys built-in components as **AddOns** from `/var/lib/rancher/rke2/server/manifests`. Any YAML/HelmChart manifest placed there is applied continuously (like `kubectl apply`) and tracked as an `AddOn` in `kube-system` ([packaged components](https://docs.rke2.io/install/packaged_components), [Helm](https://docs.rke2.io/add-ons/helm)).

### Default packaged charts

The runtime image extracts HelmChart manifests such as:

- `rke2-cilium.yaml`, `rke2-canal.yaml`, `rke2-calico.yaml`, `rke2-flannel.yaml`, `rke2-multus.yaml`
- `rke2-coredns.yaml`
- `rke2-ingress-nginx.yaml`, `rke2-traefik.yaml`, `rke2-traefik-crd.yaml`
- `rke2-metrics-server.yaml`
- `rke2-snapshot-controller*.yaml`, `rke2-runtimeclasses.yaml`, `rke2-security-responder.yaml`, `rke2-gateway-api-crd.yaml`

([architecture](https://docs.rke2.io/architecture), [chart_versions.yaml](https://github.com/rancher/rke2/blob/master/charts/chart_versions.yaml))

### Customizing packaged charts

Use a `HelmChartConfig` in the same namespace/name as the chart:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      tag: v1.14.3-build20260506
```

`spec.set` values override `valuesContent` from both `HelmChart` and `HelmChartConfig` ([Helm](https://docs.rke2.io/add-ons/helm)).

### Disabling AddOns

- `--disable: rke2-<name>` actively uninstalls the chart and deletes the manifest file.
- A `.skip` file next to a manifest (e.g. `rke2-coredns.yaml.skip`) simply prevents RKE2 from applying it; existing resources are left intact ([packaged components](https://docs.rke2.io/install/packaged_components)).

### Fetching included charts

1. **Release notes**: each RKE2 release lists chart versions and direct tarball URLs, e.g. `https://github.com/rancher/rke2-charts/raw/main/assets/rke2-cilium/rke2-cilium-1.20.300.tgz` ([v1.36 release notes](https://docs.rke2.io/release-notes/v1.36.X)).
2. **rke2-charts repo**: source packages and released assets live in [rancher/rke2-charts](https://github.com/rancher/rke2-charts). The build script constructs URLs of the form `https://rke2-charts.rancher.io/assets/<package>/<chart>-<version>.tgz` ([build-chart.sh](https://github.com/rancher/rke2/blob/master/charts/build-chart.sh)).
3. **Runtime image**: the `rancher/rke2-runtime` image contains the packaged chart manifests; extract them from the image or from a running server's `/var/lib/rancher/rke2/server/manifests`.

---

## 8. API / supervisor behavior and ports

- The **RKE2 supervisor API** listens on **TCP 9345** and is used for node registration and serving the `/cacerts` bundle ([HA install](https://docs.rke2.io/install/ha), [requirements](https://docs.rke2.io/install/requirements)).
- The **Kubernetes API server** listens on **TCP 6443** ([HA install](https://docs.rke2.io/install/ha), [requirements](https://docs.rke2.io/install/requirements)).
- Agents open a **websocket** to the supervisor and maintain it through a client-side load balancer inside the `rke2 agent` process. The kubelet then talks to the API server through that same client-side LB ([advanced](https://docs.rke2.io/advanced)).

### Required inbound ports (Linux)

| Port | Protocol | Source → Destination | Purpose |
|------|----------|----------------------|---------|
| 6443 | TCP | all nodes → servers | Kubernetes API |
| 9345 | TCP | all nodes → servers | RKE2 supervisor API |
| 10250 | TCP | all nodes → all nodes | kubelet metrics |
| 2379 | TCP | servers → servers | etcd client |
| 2380 | TCP | servers → servers | etcd peer |
| 2381 | TCP | servers → servers | etcd metrics |
| 30000-32767 | TCP | all nodes → all nodes | NodePort range |

([requirements](https://docs.rke2.io/install/requirements))

### Cilium-specific ports

| Port/Type | Protocol | Purpose |
|-----------|----------|---------|
| ICMP type 0, 8 | ICMP | Cilium health checks |
| 4240 | TCP | Cilium health checks |
| 8472 | UDP | Cilium VXLAN |
| 51871 | UDP | Cilium WireGuard |

([requirements](https://docs.rke2.io/install/requirements))

---

## 9. Preparing RKE2 for Cilium (>= 1.20)

RKE2's default CNI is Canal. Choose the primary CNI before first start; changing the primary CNI or pod CIDRs on a running cluster is not a supported in-place operation ([basic network options](https://docs.rke2.io/networking/basic_network_options)).

### Integrated RKE2 Cilium chart

Use the distribution-managed Cilium chart:

```yaml
# /etc/rancher/rke2/config.yaml
cni: cilium
# add only when Cilium replaces kube-proxy:
# disable-kube-proxy: true
```

Place a `HelmChartConfig` for `rke2-cilium` in `/var/lib/rancher/rke2/server/manifests/` before starting the server. Example starting point:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: true
    k8sServiceHost: 10.0.0.10
    k8sServicePort: 6443
    localRedirectPolicy: true
```

Use a stable API endpoint for `k8sServiceHost` in kube-proxy-free mode.

### Upstream Cilium chart

Set `cni: none` only when you will install and maintain the upstream Cilium chart yourself. Mirror the upstream Cilium images for air-gapped clusters; the integrated `rke2-cilium` chart uses the `rke2-images-cilium.<arch>` artifacts instead.

For NodeLocal DNSCache with Cilium kube-proxy replacement, also set `nodelocal.use_cilium_lrp: true` in the `rke2-coredns` chart values ([networking services](https://docs.rke2.io/networking/networking_services)).

---

## 10. CIS profile hardening and audit playbook

RKE2 is designed to pass the CIS Kubernetes Benchmark with minimal extra work. Set the `profile` flag before first start ([hardening guide](https://docs.rke2.io/security/hardening_guide)).

Choose the `profile` value from the RKE2 release, not from the CIS guide name:

| RKE2 version | Profile value |
|--------------|---------------|
| v1.29+ | `profile: cis` |
| v1.25 - v1.28 | `profile: cis-1.23` |
| v1.24 and older | `profile: cis-1.6` or `cis-1.5`, per the versioned guide |

Use the matching self-assessment guide when auditing:

| RKE2 version | Self-assessment guide |
|--------------|-----------------------|
| v1.35+ | CIS 2.0 ([cis_self_assessment20](https://docs.rke2.io/security/cis_self_assessment20)) |
| v1.33 - v1.34 | CIS 1.12 ([cis_self_assessment112](https://docs.rke2.io/security/cis_self_assessment112)) |
| v1.29 - v1.32 | CIS 1.11 ([cis_self_assessment111](https://docs.rke2.io/security/cis_self_assessment111)) |
| v1.28 - v1.31 | CIS 1.10 ([cis_self_assessment110](https://docs.rke2.io/security/cis_self_assessment110)) |

([hardening guide](https://docs.rke2.io/security/hardening_guide))

### Host-level prerequisites

```bash
# CIS sysctl
sudo cp /usr/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
sudo systemctl restart systemd-sysctl

# etcd user/group must exist in /etc/passwd and /etc/group (no NSS/systemd-userdb)
sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
```

([hardening guide](https://docs.rke2.io/security/hardening_guide))

### What `profile: cis` does automatically

- Verifies host requirements and exits if unmet.
- Sets `protect-kernel-defaults: true` for the kubelet.
- Runs the etcd static pod as `etcd:etcd`.
- Applies restrictive file permissions (600) to agent manifests and configs.
- Deploys default `NetworkPolicies` in `kube-system`, `kube-public`, and `default`.
- Configures Pod Security Admission to enforce `restricted` cluster-wide, except `kube-system`, `compliance-operator-system`, and `tigera-operator` ([hardening guide](https://docs.rke2.io/security/hardening_guide)).
- Enables hardened API-server audit-log flags and writes a default audit policy to `/etc/rancher/rke2/audit-policy.yaml` with `level: None` ([hardening guide](https://docs.rke2.io/security/hardening_guide)).

### Operator-required remediations

1. **Patch `default` service accounts** in every user namespace to set `automountServiceAccountToken: false`. RKE2 already does this for `kube-system`, `kube-node-lease`, `compliance-operator-system`, and `tigera-operator` ([hardening guide](https://docs.rke2.io/security/hardening_guide)).
2. **Write a real audit policy** if you need audit logs; restart `rke2-server` after editing `/etc/rancher/rke2/audit-policy.yaml` ([hardening guide](https://docs.rke2.io/security/hardening_guide)).
3. **Create NetworkPolicies** for any additional namespaces; the built-in policies only cover built-in namespaces ([hardening guide](https://docs.rke2.io/security/hardening_guide)).
4. **Ingress in CIS mode**: default `NetworkPolicies` block ingress-nginx from reaching pods. Add an explicit policy allowing ingress from `kube-system` pods labeled `app.kubernetes.io/name: rke2-ingress-nginx` ([known issues](https://docs.rke2.io/known_issues)).

### Quick audit playbook

Run these on a hardened cluster and compare against the appropriate CIS self-assessment guide:

```bash
# Profile, sysctls, static-pod manifests, etcd data dir, network policies,
# default SA automount, and certificate expiration
grep profile /etc/rancher/rke2/config.yaml
sudo sysctl -a | grep -E 'net.ipv4.ip_forward|net.ipv6.conf.all.forwarding|vm.overcommit_memory|kernel.panic'
stat -c '%U:%G %a' /var/lib/rancher/rke2/agent/pod-manifests/kube-apiserver.yaml
stat -c '%U:%G %a' /var/lib/rancher/rke2/server/db
kubectl get networkpolicies -n kube-system -n kube-public -n default
kubectl get sa -A -o json | jq '.items[] | select(.metadata.name=="default") | {ns: .metadata.namespace, auto: .automountServiceAccountToken}'
rke2 certificate check --output table
```

---

## 11. Pod Security Admission and version-specific defaults

- **RKE2 v1.25+** uses Pod Security Admission (PSA). **v1.24 and older** use PodSecurityPolicies (PSP) ([pod security standards](https://docs.rke2.io/security/pod_security_standards), [pod security policies](https://docs.rke2.io/security/pod_security_policies)).
- With `profile: cis`, RKE2 writes `/etc/rancher/rke2/rke2-pss.yaml` enforcing `restricted` everywhere except `kube-system`, `compliance-operator-system`, and `tigera-operator` ([pod security standards](https://docs.rke2.io/security/pod_security_standards)).
- Without a `profile`, RKE2 writes a PSA config enforcing `privileged` cluster-wide ([pod security standards](https://docs.rke2.io/security/pod_security_standards)).
- Override the file with `pod-security-admission-config-file: /path/to/custom-pss.yaml` ([server config](https://docs.rke2.io/reference/server_config)).

### Upgrading hardened clusters from v1.24 → v1.25+

1. Set `profile: cis-1.23` on all nodes **before** upgrading, but do not restart yet.
2. Label the `system-upgrade` namespace (or wherever system-upgrade-controller runs) as `pod-security.kubernetes.io/enforce: privileged`.
3. Perform the upgrade ([known issues](https://docs.rke2.io/known_issues)).

---

## 12. Build from source

RKE2 builds in a Docker environment by default. See `go.mod` for the required Go series ([BUILDING.md](https://github.com/rancher/rke2/blob/master/BUILDING.md)).

### Prerequisites

- bash, docker, containerd, gcc, go, make
- Docker containerd image store enabled (`{"features":{"containerd-snapshotter":true}}` in `/etc/docker/daemon.json`) so buildx can export the runtime tarball ([BUILDING.md](https://github.com/rancher/rke2/blob/master/BUILDING.md)).

### Build and run locally

```bash
make        # container build
make build  # host-local build
make dev-shell
```

To run the built binary on another host, copy `./bin/rke2` to `/usr/local/bin/rke2`, copy the needed image tarballs (`rke2-runtime.tar`, plus `rke2-kubernetes.tar` or `rke2-airgap.tar`) to `/var/lib/rancher/rke2/agent/images/`, and start with `rke2 server --token=test`.

---

## 13. Versioning and upgrade compatibility

RKE2 versions follow `v<k8s>.<patch>+rke2r<release>` (e.g. `v1.36.5+rke2r1`). The `+rke2rN` suffix allows Rancher to re-release the same Kubernetes patch ([README](https://github.com/rancher/rke2/blob/master/README.md)).

### Upgrade rules

- Obey the Kubernetes version skew policy: **do not skip minor versions** ([manual upgrades](https://docs.rke2.io/upgrades/manual), [automated upgrades](https://docs.rke2.io/upgrades/automated)).
- Upgrade **server nodes first, one at a time**, then agents ([manual upgrades](https://docs.rke2.io/upgrades/manual)).
- Channels: `stable` (default), `latest`, and per-minor channels like `v1.36`. Query the [channel API](https://update.rke2.io/v1-release/channels) for the current list ([manual upgrades](https://docs.rke2.io/upgrades/manual)).

### Manual upgrade methods ([manual upgrades](https://docs.rke2.io/upgrades/manual))

```bash
# Install script
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.36.5+rke2r1 sh -
systemctl restart rke2-server

# RPM
yum update rke2-server
systemctl restart rke2-server

# Binary: replace /usr/local/bin/rke2 (tar) or /usr/bin/rke2 (RPM), then restart
```

### Automated upgrades with system-upgrade-controller ([automated upgrades](https://docs.rke2.io/upgrades/automated))

```yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: server-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - {key: node-role.kubernetes.io/control-plane, operator: In, values: ["true"]}
  serviceAccountName: system-upgrade
  upgrade: {image: rancher/rke2-upgrade}
  channel: https://update.rke2.io/v1-release/channels/stable
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: agent-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - {key: node-role.kubernetes.io/control-plane, operator: DoesNotExist}
  prepare:
    args: [prepare, server-plan]
    image: rancher/rke2-upgrade
  serviceAccountName: system-upgrade
  upgrade: {image: rancher/rke2-upgrade}
  channel: https://update.rke2.io/v1-release/channels/stable
```

The agent plan's `prepare` step waits for the server plan to complete. Use `version: v1.36.5+rke2r1` instead of `channel` to pin a release.

### Air-gap automated upgrades

Push these images into your private registry:

- `rancher/rke2-upgrade:<version>` (replace `+` with `-`, e.g. `v1.36.5-rke2r1`)
- `rancher/system-upgrade-controller:<version>`
- `rancher/kubectl:<version>` from the SUC manifest you deploy

([airgap install](https://docs.rke2.io/install/airgap))

### Downgrades and rollbacks

Kubernetes does not support control-plane downgrades. Rolling back requires restoring an etcd snapshot taken with the target Kubernetes version ([automated upgrades](https://docs.rke2.io/upgrades/automated)).

---

## 14. Important uncertainties and caveats

- **NATS datastore**: The RKE2 CLI help / server-config table mentions NATS alongside etcd/SQL, but the official external-datastore docs list only etcd, MySQL, MariaDB, and PostgreSQL. NATS should not be treated as a supported production backend without explicit vendor confirmation.
- **Latest version**: This reference was researched on 2026-10-17 against docs and repos current at that time. Do not assert "latest" without checking the [RKE2 releases](https://github.com/rancher/rke2/releases) page.
- **Ingress NGINX default**: Ingress NGINX reached end-of-life in March 2026; Traefik is the default ingress controller for RKE2 v1.36+ new clusters ([networking services](https://docs.rke2.io/networking/networking_services)). This reference intentionally does not detail Traefik configuration.
- **CNI changes on running clusters**: RKE2 explicitly warns that switching the primary CNI or CIDRs on a running cluster is untested; rebuild if required ([basic network options](https://docs.rke2.io/networking/basic_network_options)).
