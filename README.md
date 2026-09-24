# terraform-proxclus

Hardened Ubuntu 26.04 + RKE2 Kubernetes cluster on Proxmox VE.

## Layout

Provisioning is three modules, not the more obvious two, because of one
ordering constraint: a VM's cloud-init content has to exist *before* the VM
is created, while checking that the cluster actually came up can only happen
*after*. One module can't sit on both sides of that dependency.

- `modules/proxmox-vm` — Proxmox VM creation, cloned from the templates
  `packer/` builds; wires in each node's cloud-init snippet by ID
- `modules/rke2-config` — renders and uploads each node's cloud-init
  user-data (hostname, RKE2 role config, the kube-vip manifest on the
  control-plane node) as a Proxmox snippet; generates the shared RKE2 join
  token and the SSH keypair Terraform itself uses afterward. Runs *before*
  `modules/proxmox-vm`, not after.
- `modules/rke2-cluster` — waits for `rke2-server` to come up on the
  bootstrap node (over SSH) and fetches its kubeconfig. Runs *after*
  `modules/proxmox-vm`, keyed off its VM outputs rather than the raw node
  list, so Terraform knows to wait for the VMs to exist first.
- `modules/addons/cilium` — Cilium and its LoadBalancer address pool
- `modules/addons/longhorn` — Longhorn, the default CSI provider for dynamic PVs
- `modules/addons/metrics-server` — metrics-server, for `kubectl top` and the
  HorizontalPodAutoscaler
- `modules/addons/nvidia-device-plugin` — NVIDIA device plugin, so a mapped GPU
  shows up as an `nvidia.com/gpu` resource
- `addons.tf` — where addons are composed
- `packer/` — builds the two Proxmox VM templates (plain and GPU) that
  `modules/proxmox-vm` clones from; see `packer/README.md`
- `vm-templates/import-ubuntu-cloud-image.sh` — one-time import of the stock
  Ubuntu cloud image that `packer/` then clones and provisions
- `apps/` — applications deployed onto this cluster, each its own
  independent Terraform root (own state, own providers, own lifecycle); see
  `apps/README.md` for the convention and `apps/postgres-cnpg` for the
  reference example
- `troubleshooting-agents/` — LangGraph troubleshooting agents (Ollama,
  NVIDIA GPU, Proxmox host) with a small React GUI, independent of
  Terraform entirely; see `troubleshooting-agents/README.md`. Its Talos-
  specific agent/skills (`talosctl`-based) predate this cluster's move off
  Talos and need a follow-up SSH-based rework, tracked separately from this
  Terraform layout.

## Adding an addon

One module per addon under `modules/addons/`, instantiated in `addons.tf` with
its own enable flag. An addon owns everything it needs: its Helm release, its
namespace, and any nested charts for custom resources.

Unlike under Talos, an addon needing something from the node itself (a
package, a host directory, a systemd unit) gets it from `packer/`'s
provisioning scripts or, if it's genuinely per-node, from
`modules/rke2-config`'s cloud-init template — not from a machine-config
patch mechanism, which no longer exists in this repo. `modules/addons/longhorn`
is the example: it used to need a Talos `extraMounts` patch to expose
`/var/lib/longhorn` to the kubelet at all; a normal Ubuntu kubelet already
sees that path, so nothing addon-specific is needed there anymore, only
`packer/scripts/install-longhorn-deps.sh`'s `open-iscsi`/`util-linux`
install, which isn't Longhorn-specific either (any node might run it).

Resist collapsing this into one generic map of charts. Namespace labels, custom
resources ordered after their CRDs, and ordering between addons all need
per-addon code.

## VM image

`packer/` is the single source of truth for what's on every node's disk:
hardening, the RKE2 binary, and (on the GPU template) the NVIDIA driver and
container toolkit are all baked in once, at image-build time — see
`packer/README.md` for the build steps and why Packer instead of doing all
of this in cloud-init on every clone.

Updating the image (a new RKE2 version, a new hardening step) means
rebuilding the templates (`just t-create`, or a subset via `packer build`)
and then replacing each node's VM — there's no in-place "upgrade" command
the way `talosctl upgrade --image ...` was.

## Usage

Task running is [`just`](https://github.com/casey/just), not Make; see
`Justfile` for the full recipe list (`just --list`).

```bash
just t-create   # once, builds the Proxmox templates (see packer/README.md)
just apply
just generate   # writes ~/.kube/config and ~/.ssh/rke2_admin
```

`terraform apply` also writes a kubeconfig to `.kube/config` inside this
directory, because the `helm` provider needs one to reach the cluster.

## Networking

`cni = "cilium"` (the default) sets `cni: none` and `disable-kube-proxy: true`
in every node's RKE2 config (`modules/rke2-config`), and the addons module
installs Cilium to cover both roles. Set `cni = "flannel"` to leave RKE2's
own bundled Canal + kube-proxy running instead, and leave `module.cilium`
disabled.

LoadBalancer services get an address from `load_balancer_ip_range`, announced on
the LAN over ARP by Cilium L2 announcements. The range has to be free on the
node subnet: outside any DHCP scope, clear of the node addresses and of
`controlplane_vip`.

| Setting                  | Value                         |
| ------------------------ | ----------------------------- |
| Nodes                    | 192.168.1.201-192.168.1.206   |
| Control-plane VIP        | 192.168.1.99                  |
| LoadBalancer pool        | 192.168.1.60-192.168.1.98     |

The control-plane VIP is advertised by **kube-vip**, run as an RKE2
auto-deployed manifest (`/var/lib/rancher/rke2/server/manifests/kube-vip.yaml`,
written by `modules/rke2-config`) on the control-plane node — the RKE2-world
replacement for Talos's `Layer2VIPConfig` patch. It's a `hostNetwork` pod
using ARP, so it's reachable even before Cilium brings up pod networking.
With only one control-plane node today, this mainly buys a stable address
independent of that node's own IP; a second control-plane node later would
get automatic failover via kube-vip's leader election with no client
reconfiguration.

Setting `external_ip` to a public IP or hostname adds it as a SAN on the
control-plane's RKE2 `tls-san`, so a client outside the LAN validates TLS
once it reaches the cluster. It doesn't configure the router: forwarding
that public IP's port 6443 to `controlplane_vip` is a manual NAT/port-forward
rule you set up separately, and the external client needs its own
kubeconfig with the endpoint changed to `external_ip`.

`enable_hubble_ui = true` (the default) installs Hubble Relay and Hubble UI
alongside Cilium: a web dashboard of the CNI's live traffic (service map,
L3/L4/L7 flows, DNS, policy verdicts). It gets its own LoadBalancer address
from the same pool, controlled by `hubble_ui_service_type`. See
`modules/addons/cilium/README.md`'s "Hubble" section for what the module sets.

## Storage

`enable_longhorn = true` installs Longhorn and makes its `longhorn`
StorageClass the cluster default, so PVCs provision dynamically without naming
`storageClassName`. Unlike under Talos, turning this on needs no machine-config
change and no reboot: a normal Ubuntu kubelet already sees `/var/lib/longhorn`
with no extra mount configuration. `open-iscsi`/`util-linux`/`nfs-common`,
which Longhorn's engine needs on the host, are baked into every node's image
by `packer/scripts/install-longhorn-deps.sh` regardless of this flag.

`longhorn_version` and `longhorn_replica_count` (default 3, matching the
worker count) tune the release; see `modules/addons/longhorn/README.md` for
what else the module sets and why.

## Metrics

`enable_metrics_server = true` (the default) installs metrics-server, giving
`kubectl top node`/`kubectl top pod` and the HorizontalPodAutoscaler resource
metrics to read. Touches no node provisioning and needs no reboot to turn on
or off.

`metrics_server_version` tunes the chart version; see
`modules/addons/metrics-server/README.md` for the flags it sets
(`--kubelet-insecure-tls` and `--kubelet-preferred-address-types`) — standard
self-managed-kubelet workarounds, not specific to any one distro.

## Monitoring

`enable_prometheus = true` (default `false`) installs
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack):
Prometheus, Alertmanager, Grafana, node-exporter, and kube-state-metrics, with
default alerting rules and Kubernetes dashboards. Its PVCs default to the
`longhorn` StorageClass, so it also needs `enable_longhorn = true`.

`kube_prometheus_stack_version` tunes the chart version, and
`grafana_admin_password` sets Grafana's login (defaults to the chart's own
`"prom-operator"` — change it before relying on the default LoadBalancer
exposure, which puts Grafana's login page on the LAN). See
`modules/addons/prometheus/README.md` for the rest of the module's inputs, the
privileged-namespace label node-exporter needs, and why
`serviceMonitorSelectorNilUsesHelmValues` (and its `podMonitor`/`rule`
equivalents) are turned off.

## GPU

Setting `pcigpu` on a node in `var.nodes` passes that PCI device through to
the VM (see `modules/proxmox-vm`) and clones it from the GPU template
instead of the common one (`template_vm_id_gpu`, built by
`packer/ubuntu-gpu.pkr.hcl` with the NVIDIA driver, container toolkit, and
containerd runtime registration already baked in). Nothing else needs
flipping: as soon as any node sets `pcigpu`, `module.nvidia_device_plugin`
installs the NVIDIA device plugin so that node's GPU shows up as an
`nvidia.com/gpu` resource for Kubernetes to schedule against, and creates
the `nvidia` `RuntimeClass` GPU pods must set via `spec.runtimeClassName` to
actually reach the GPU. See `modules/addons/nvidia-device-plugin/README.md`
for what the module sets and why, including the pod-spec shape a GPU
workload needs.

`nvidia_device_plugin_version` tunes the chart version; there's no matching
enable flag; unlike `enable_longhorn`, presence is derived entirely from
`pcigpu`, which is already the single source of truth this repo uses to
decide the VM template and image provisioning, so a second, independently
toggled flag would only be one more thing to keep in sync.

## Hardening

Every node's image (`packer/scripts/harden.sh`) gets a practical baseline:
SSH key-only auth with root login disabled, `ufw` default-deny with only the
ports RKE2/SSH/Longhorn/Cilium/kube-vip actually need open,
`unattended-upgrades` for security patches, `auditd`, a standard hardening
sysctl set layered on top of RKE2's own, swap disabled, and AppArmor
confirmed enforcing (Ubuntu's default). This is a deliberately lighter
baseline than a full CIS Level 1 pass via Canonical's Ubuntu Security Guide
(`usg`) — less compliance-grade, but lower risk of needing tuning against
RKE2/Longhorn/Cilium's actual runtime requirements.

RKE2 itself runs with `profile: cis` in every node's config
(`modules/rke2-config`), independent of the OS-level baseline above — its
prerequisites (the `etcd` user/group, RKE2's own shipped CIS sysctls) are
applied in `packer/scripts/install-rke2.sh`, right after the RKE2 binary
installs so it can read what that install shipped.

## Ordering

Cloud-init + RKE2's own startup are asynchronous after a VM boots (unlike
Talos's `talos_machine_bootstrap`, a synchronous API call), so addons need
something to gate on before the cluster is reachable. `modules/rke2-cluster`
provides exactly one gate, `wait_for_api` (on by default): poll the
bootstrap node over SSH until `rke2-server` is active, then fetch its
kubeconfig. There's no Kubernetes-level health check the way Talos's
`data.talos_cluster_health` was — no equivalent RKE2 Terraform data source
exists to skip node-readiness/coredns checks the way Talos could once it
knew `cni: none` — so this only proves the API server exists, exactly as
much as `wait_for_api` proved under Talos.

Cilium, Longhorn, metrics-server, Prometheus, and the NVIDIA device plugin
all depend on `module.rke2_cluster` for that guarantee. Anything needing
real pod networking (Longhorn, metrics-server, Prometheus, the NVIDIA device
plugin) additionally depends on `module.cilium`'s `helm_release` directly,
since RKE2 never brings up pod networking itself when `cni` is `cilium`.
Prometheus additionally depends on `module.longhorn` directly, since its
PVCs need Longhorn's CSI controller actually running to provision.

`wait_for_api = false` disables the gate, which is also how you plan against
a cluster that is powered off.
