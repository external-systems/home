# k3s / RKE2 / k3d on NixOS

Reference for AI agents working with Rancher Kubernetes distributions on NixOS.
Assumes **Cilium >= 1.20** when a CNI is required.
Verified against NixOS/nixpkgs master commit
[`8317f1b78740a43418f55754ef82817604d436b6`](https://github.com/NixOS/nixpkgs/commit/8317f1b78740a43418f55754ef82817604d436b6)
and the upstream k3s/RKE2/Cilium docs cited in each section.

---

## Packages in nixpkgs

| Package | Unstable default | Stable default | Versioned attributes | Source |
|---|---|---|---|---|
| `k3s` | 1.36.5+k3s1 | 1.35.8+k3s1 | `k3s_1_34`, `k3s_1_35`, `k3s_1_36`, `k3s_1_37` | [`pkgs/applications/networking/cluster/k3s/default.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/pkgs/applications/networking/cluster/k3s/default.nix) |
| `rke2` | 1.35.8+rke2r1 | 1.34.11+rke2r1 | `rke2_1_34`, `rke2_1_35`, `rke2_1_36`, `rke2_stable`, `rke2_latest` | [`pkgs/applications/networking/cluster/rke2/default.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/pkgs/applications/networking/cluster/rke2/default.nix) |
| `k3d` | 5.9.0 | 5.8.3 | — | [`pkgs/by-name/k3/k3d/package.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/pkgs/by-name/k3/k3d/package.nix) |
| `k3sup` | 0.13.13 | 0.13.12 | — | [`pkgs/by-name/k3/k3sup/package.nix`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/k3/k3sup/package.nix) |
| `cni-plugins` | 1.9.1 | — | — | [`pkgs/applications/networking/cluster/cni/plugins.nix`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/cni/plugins.nix) |

`pkgs.k3s` is an alias to the current default versioned attribute (`k3s_1_36` in
unstable, `k3s_1_35` in stable). `pkgs.rke2` points to `rke2_1_35` in unstable
and `rke2_1_34` in stable.

The k3s package exposes an `airgap-images` output (`k3s_1_*.airgap-images`) for
air-gapped installs. The rke2 package exposes per-CNI image archives such as
`images-core-linux-amd64-tar-zst` and `images-cilium-linux-amd64-tar-zst`
([`1_35/images-versions.json`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/pkgs/applications/networking/cluster/rke2/1_35/images-versions.json)).

---

## Native NixOS modules: `services.k3s` and `services.rke2`

Both modules are generated from a shared Rancher module in
[`nixos/modules/services/cluster/rancher/default.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/modules/services/cluster/rancher/default.nix)
and then specialised in
[`k3s.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/modules/services/cluster/rancher/k3s.nix)
and
[`rke2.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/modules/services/cluster/rancher/rke2.nix).

### Common important options

| Option | k3s | rke2 | Notes |
|---|---|---|---|
| `enable` | yes | yes | `services.<name>.enable = true;` |
| `package` | yes | yes | Pin to a versioned attribute, e.g. `pkgs.k3s_1_37`. |
| `role` | `"server"` / `"agent"` | `"server"` / `"agent"` | Default `"server"`. |
| `serverAddr` | yes | yes | URL for agents/HA servers to join, e.g. `https://10.0.0.10:6443`. |
| `token` / `tokenFile` | yes | yes | Join token. **Do not use `token`** for real secrets; it lands in the world-readable Nix store. Use `tokenFile`. |
| `agentToken` / `agentTokenFile` | yes | yes | Server-only token used by agents. |
| `extraFlags` | yes | yes | Extra CLI flags passed to `k3s` / `rke2`. |
| `configPath` | yes | yes | Absolute path to a YAML config file. Passed as `--config`. |
| `environmentFile` | yes | yes | `EnvironmentFile=` for the systemd service. |
| `disable` | yes | yes | List of packaged components to disable (`--disable=<x>`). |
| `manifests` | yes | yes | Auto-deployed manifests in `/var/lib/rancher/<name>/server/manifests`. RKE2 serialises these as JSON. |
| `charts` | yes | yes | Pre-staged Helm chart `.tgz` files served to the in-cluster Helm controller. |
| `autoDeployCharts` | yes | yes | Declarative Helm charts; module fetches the chart at build time and generates a `HelmChart` CR. |
| `images` | yes | yes | Container images linked into `/var/lib/rancher/<name>/agent/images/nixos/` before start. |
| `containerdConfigTemplate` | yes | yes | Template rendered to `/var/lib/rancher/<name>/agent/etc/containerd/config.toml.tmpl`. |
| `extraKubeletConfig` / `extraKubeProxyConfig` | yes | yes | Merged into generated kubelet/kube-proxy config files. |
| `gracefulNodeShutdown.*` | yes | yes | Kubelet graceful shutdown settings. |

### k3s-specific options

* `clusterInit` — use embedded etcd instead of sqlite; must be `true` on the
  first server in an HA cluster.
* `disableAgent` — run a control-plane-only server (`--disable-agent`).

Source: [`k3s.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/modules/services/cluster/rancher/k3s.nix).

### RKE2-specific options

* `cni` — one of `"none"`, `"canal"`, `"cilium"`, `"calico"`, `"flannel"`.
  Default `null` means upstream default (Canal). Passed as `--cni=<x>`.
* `cisHardening` — creates the `etcd` user/group and passes `--profile=cis`.

The module also sets `vm.panic_on_oom`, `vm.overcommit_memory`,
`kernel.panic`, and `kernel.panic_on_oops` through `boot.kernel.sysctl`
whenever `services.rke2.enable` is true, independently of `cisHardening`.

Source: [`rke2.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/modules/services/cluster/rancher/rke2.nix).

### Roles and required fields

* **k3s server** — standalone by default; set `clusterInit = true` for embedded
  etcd HA. Other servers join with `serverAddr`.
* **k3s agent** — `serverAddr` required.
* **rke2 server** — all options allowed; `cni`, `disable`, `agentToken` only
  make sense here.
* **rke2 agent** — `serverAddr` and `token`/`tokenFile` required;
  `agentToken`, `agentTokenFile`, `disable`, `cni` should not be set.

---

## How module-generated config interacts with distro config

The module does **not** write to `/etc/rancher/<name>/config.yaml`. Instead it
builds a systemd `ExecStart` line from the declared options and uses
`systemd-tmpfiles` to link manifests, images and charts into
`/var/lib/rancher/<name>/` before the service starts.

Key files the distro binary reads/writes:

* k3s default config: `/etc/rancher/k3s/config.yaml` and
  `/etc/rancher/k3s/config.yaml.d/*.yaml`
  ([k3s docs](https://docs.k3s.io/installation/configuration)).
* RKE2 default config: `/etc/rancher/rke2/config.yaml` and
  `/etc/rancher/rke2/config.yaml.d/*.yaml`
  ([RKE2 docs](https://docs.rke2.io/install/configuration)).
* k3s manifests dir: `/var/lib/rancher/k3s/server/manifests`
* RKE2 manifests dir: `/var/lib/rancher/rke2/server/manifests`
* k3s airgap image dir: `/var/lib/rancher/k3s/agent/images/nixos/`
* RKE2 airgap image dir: `/var/lib/rancher/rke2/agent/images/nixos/`

If you set `configPath`, the module passes `--config <path>` and that file is
loaded instead of the default `/etc/rancher/<name>/config.yaml`. If you do not
set `configPath` but place a file at the default path, k3s/RKE2 loads it
**and** the module's CLI flags; CLI flags take precedence
([k3s docs](https://docs.k3s.io/installation/configuration),
[RKE2 docs](https://docs.rke2.io/install/configuration)).

Use `extraFlags` for one-off flags, `configPath` for a complete external config,
and `environmentFile` for environment variables (e.g. HTTP proxy, `K3S_*`,
`RKE2_*`).

---

## Secrets and token handling

Never set `token`, `agentToken`, or secret chart `values` directly in a Nix
expression — they are written to the world-readable `/nix/store`.

Safe patterns:

* `tokenFile` / `agentTokenFile` — point to files deployed by sops-nix,
  `clan.core.vars`, agenix, or another secret manager outside the store.
* `environmentFile` — systemd `EnvironmentFile=` path for `K3S_TOKEN`,
  `RKE2_TOKEN`, proxy variables, etc.
* For chart values that contain secrets, pass a `path` to a file generated by
  your secret tooling instead of an attribute set.

In NixOS VM tests, fake tokens can be `pkgs.writeText "token" "..."` because
the test closure is intentionally public.

---

## NixOS firewall options and required rules

Use standard NixOS firewall options:

* `networking.firewall.allowedTCPPorts`
* `networking.firewall.allowedUDPPorts`
* `networking.firewall.trustedInterfaces`

### k3s ports

From [k3s networking requirements](https://docs.k3s.io/installation/requirements#networking):

| Protocol | Port | Scope | Notes |
|---|---|---|---|
| TCP | 6443 | agents → servers | Kubernetes API / k3s supervisor |
| TCP | 10250 | all nodes | kubelet metrics/API |
| TCP | 2379-2380 | servers | embedded etcd HA only |
| UDP | 8472 | all nodes | Flannel VXLAN (not needed with Cilium unless using VXLAN) |
| UDP | 51820 / 51821 | all nodes | Flannel WireGuard IPv4 / IPv6 |
| TCP | 5001 / 6443 | all nodes | embedded distributed registry (Spegel) |

### RKE2 ports

From [RKE2 networking requirements](https://docs.rke2.io/install/requirements#networking):

| Protocol | Port | Scope | Notes |
|---|---|---|---|
| TCP | 6443 | all nodes → servers | Kubernetes API |
| TCP | 9345 | all nodes → servers | RKE2 supervisor API |
| TCP | 10250 | all nodes | kubelet metrics/API |
| TCP | 2379-2381 | servers | etcd client/peer/metrics |
| TCP | 30000-32767 | all nodes | NodePort range |
| UDP | 8472 | all nodes | Canal/Flannel VXLAN; Cilium also uses 8472 for VXLAN overlay |
| TCP | 9099 | all nodes | Canal health checks only |

### Cilium ports

From [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/):

| Protocol | Port | Notes |
|---|---|---|
| UDP | 8472 | VXLAN overlay default |
| UDP | 6081 | Geneve overlay |
| UDP | 51871 | WireGuard encryption |
| TCP | 4240 | `cilium-health` |
| TCP | 4244 / 4245 | Hubble server / Relay |
| TCP | 9962 / 9963 / 9964 | Prometheus metrics |
| ICMP | type 8/0 | health probes |

### Example NixOS firewall snippet

```nix
{
  networking.firewall = {
    allowedTCPPorts = [
      6443        # K8s API
      10250       # kubelet
      2379 2380   # etcd HA
      4240        # cilium-health
    ] ++ lib.optionals config.services.rke2.enable [ 9345 ];
    allowedUDPPorts = [ 8472 ];   # Cilium/Canal/Flannel VXLAN
  };
}
```

The upstream multi-node NixOS test sets
`networking.firewall.enable = false` for simplicity
([`multi-node.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/multi-node.nix));
that is **not** a production pattern.

---

## Running k3s / RKE2 with Cilium on NixOS

### k3s + Cilium

1. Disable the built-in Flannel CNI and network-policy enforcer:

```nix
services.k3s = {
  enable = true;
  role = "server";
  package = pkgs.k3s_1_37;
  extraFlags = [
    "--flannel-backend=none"
    "--disable-network-policy"
    "--cluster-cidr=10.42.0.0/16"
    "--service-cidr=10.43.0.0/16"
  ];
};
```

2. Install Cilium. Options:

   * Place a `HelmChart` manifest in `services.k3s.manifests`.
   * Use `services.k3s.autoDeployCharts` to fetch the Cilium chart at build
     time:

```nix
services.k3s.autoDeployCharts.cilium = {
  repo = "https://helm.cilium.io/";
  name = "cilium";
  version = "1.20.3";
  hash = "<run nix-prefetch-url and paste the sha256>";
  values = {
    ipam.operator.clusterPoolIPv4PodCIDRList = [ "10.42.0.0/16" ];
  };
};
```

   * Or install later with the `cilium` CLI; set
     `--set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16"` to match
     the k3s default pod CIDR
     ([Cilium k3s guide](https://docs.cilium.io/en/stable/installation/k3s/)).

### RKE2 + Cilium

1. Select Cilium as the bundled CNI and import the corresponding airgap images
   if the node is offline:

```nix
services.rke2 = {
  enable = true;
  role = "server";
  package = pkgs.rke2_1_36;
  cni = "cilium";
  images = [
    config.services.rke2.package.images-core-linux-amd64-tar-zst
    config.services.rke2.package.images-cilium-linux-amd64-tar-zst
  ];
};
```

2. Customise the bundled chart with a `HelmChartConfig` manifest. Because the
   RKE2 module uses JSON manifests, write the content as a Nix attribute set
   and the module serialises it:

```nix
services.rke2.manifests.rke2-cilium-config = {
  content = {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChartConfig";
    metadata = {
      name = "rke2-cilium";
      namespace = "kube-system";
    };
    spec.valuesContent = builtins.toJSON {
      encryption = {
        enabled = true;
        type = "wireguard";
      };
    };
  };
};
```

For kube-proxy replacement, set `disable-kube-proxy: true` in a config file
pointed to by `configPath` (or place it at `/etc/rancher/rke2/config.yaml`) and
use the HelmChartConfig values shown in the
[RKE2 Cilium docs](https://docs.rke2.io/networking/basic_network_options).

### Kernel / sysctl / mount / cgroup requirements

Cilium host requirements from
[Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/):

* Kernel >= 5.10 (>= 4.18 on RHEL 8.10).
* Required kernel config: `CONFIG_BPF`, `CONFIG_BPF_SYSCALL`,
  `CONFIG_NET_CLS_BPF`, `CONFIG_BPF_JIT`, `CONFIG_CGROUP_BPF`,
  `CONFIG_DEBUG_INFO_BTF`, `CONFIG_VXLAN`, `CONFIG_GENEVE`,
  `CONFIG_FIB_RULES`, plus iptables/nftables modules as needed.
  The NixOS default kernel ships with these; verify if you use a custom
  kernel config.
* `/sys/fs/bpf` should be mounted as `bpffs`. Cilium can auto-mount it, but
  for persistence across agent restarts add:

```nix
fileSystems."/sys/fs/bpf" = {
  device = "bpffs";
  fsType = "bpf";
  options = [ "defaults" ];
};
```

* NixOS uses the unified cgroup v2 hierarchy by default. kubelet/containerd
  need the relevant controllers; do **not** boot with
  `systemd.unified_cgroup_hierarchy=0`.
* For rootless k3s, pure cgroup v2 is required
  ([k3s advanced docs](https://docs.k3s.io/advanced)).
* Useful sysctls (set via `boot.kernel.sysctl`):

```nix
boot.kernel.sysctl = {
  "vm.overcommit_memory" = 1;
  "fs.inotify.max_user_instances" = 8192;
  "fs.inotify.max_user_watches" = 524288;
  # only if your IPv6 default route comes from router advertisements:
  # "net.ipv6.conf.all.accept_ra" = 2;
};
```

The RKE2 module already sets `vm.panic_on_oom`, `vm.overcommit_memory`,
`kernel.panic`, and `kernel.panic_on_oops` whenever the service is enabled.

---

## Hermetic NixOS VM testing

### Upstream NixOS tests (primary examples)

The upstream test suite is
[`nixos/tests/rancher/`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/default.nix).
It parameterises a `runTest` module over distro and package and runs:

* [`single-node.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/single-node.nix) — boots one node, checks `kubectl cluster-info`, runs a pod.
* [`multi-node.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/multi-node.nix) — HA-ish server+server+agent, sets tokens, opens firewall ports, tests pod-to-pod networking.
* [`etcd.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/etcd.nix) — external `services.etcd` datastore.
* [`configuration.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/configuration.nix) — containerd/kubelet config templates and graceful shutdown.
* [`auto-deploy.nix`](https://github.com/NixOS/nixpkgs/blob/8317f1b78740a43418f55754ef82817604d436b6/nixos/tests/rancher/auto-deploy.nix) — manifests, charts and image imports.

Key patterns from the tests:

* Disable non-essential packaged components (`coredns`, `metrics-server`,
  `traefik`/`rke2-ingress-nginx`, etc.) to reduce resource use.
* Pre-build test images with `pkgs.dockerTools.buildImage` / `buildLayeredImage`
  and add them to `services.<name>.images`.
* Set `environment.sessionVariables.KUBECONFIG = "/etc/rancher/<name>/<name>.yaml"`.
* Use `machine.wait_for_unit("<service>")` and
  `machine.wait_until_succeeds("kubectl ...", timeout=...)`.
* For rke2, import `images-core-*` plus the CNI archive; for k3s, import
  `package.airgap-images` if offline.

### This repo's VM-test conventions

From [`skills/vm-tests/SKILL.md`](../../vm-tests/SKILL.md) and
[`flake-parts/tests.nix`](../../flake-parts/tests.nix):

* Test files live in `vm-tests/*.nix`.
* Each file is a `nixosLib.runTest` module taking `{ self, inputs, pkgs, lib,
  size, sizeCfg }`.
* `flake-parts/tests.nix` auto-discovers files and exposes three size variants
  as `legacyPackages.vmTests.<name>-{sm,md,lg}`:
  * sm: 2 cores / 4096 MiB / 30 GiB disk, global timeout 1200 s
  * md: 2× sm, global timeout 2400 s
  * lg: 3× sm, global timeout 5400 s
* Runner: `nix run .#vm-test -- <name>-sm`.
* CI resource caps: `virtualisation.memorySize` ≤ 16384 MiB, `virtualisation.cores` ≤ 8.
* Tests must be hermetic: no network inside the VM; pre-bake all images and
  charts in the Nix closure.

### Adapting upstream tests for Cilium

The upstream tests use Canal (k3s) or the rke2 default CNI. To test Cilium:

* For k3s, add `--flannel-backend=none --disable-network-policy` to
  `extraFlags` and deploy a Cilium `HelmChart`/`HelmChartConfig` via
  `manifests` or `autoDeployCharts`.
* For rke2, set `cni = "cilium"` and import
  `images-cilium-linux-amd64-tar-zst` (or arm64 equivalent).
* Pre-import Cilium container images into the VM closure with `images`, or
  point to a Cilium airgap archive.

Do not run VM tests or heavy builds in the agent sandbox; defer to CI or a
KVM-capable host.

---
## k3d on a Docker-enabled NixOS host

`k3d` is not a NixOS service; it is a Go CLI wrapper that launches k3s inside
Docker containers ([k3d docs](https://k3d.io/v5.9.0/)).

High-level usage on NixOS:

```nix
{
  virtualisation.docker.enable = true;
  users.users.myuser.extraGroups = [ "docker" ];
  environment.systemPackages = [ pkgs.k3d pkgs.kubectl ];
}
```

```bash
k3d cluster create mycluster
k3d kubeconfig merge mycluster --kubeconfig-switch-context
kubectl get nodes
```

k3d pulls the k3s Docker image from the internet; it is not hermetic and is
unsuitable for the repo's NixOS VM-test hermeticity rules.

---

## Version caveats

* Package defaults change with nixpkgs revisions. Pin with versioned
  attributes (`k3s_1_37`, `rke2_1_36`) for reproducible configs.
* The NixOS module interface is the same across versions, but available
  components in `disable` and valid `cni` values depend on the upstream
  release.
* RKE2 bundled Cilium chart version depends on the rke2 release; check
  [`rke2-charts`](https://github.com/rancher/rke2-charts) or the
  `rke2-cilium` HelmChart in a running cluster.
* Cilium >= 1.20 features may require newer kernels; see
  [Cilium required kernel versions](https://docs.cilium.io/en/stable/operations/system_requirements/#required-kernel-versions-for-advanced-features).
