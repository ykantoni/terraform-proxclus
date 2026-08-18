# terraform-proxclus

Talos Linux Kubernetes cluster on Proxmox VE.

## Layout

- `modules/proxmox-talos-vm` — Proxmox VMs
- `modules/talos-cluster` — Talos machine configuration and cluster bootstrap
- `modules/addons/cilium` — Cilium and its LoadBalancer address pool
- `addons.tf` — where addons are composed
- `schematic.tf` — Talos image schematic, derived from `customization.yaml`

## Adding an addon

One module per addon under `modules/addons/`, instantiated in `addons.tf` with
its own enable flag. An addon owns everything it needs: its Helm release, its
namespace, any nested charts for custom resources, and its Talos patches.

Most addons are more than a Helm chart. Longhorn, for example, needs
`iscsi-tools` and `util-linux-tools` in the image schematic, a
`/var/lib/longhorn` kubelet mount in the machine configuration, a
`longhorn-system` namespace labelled `pod-security.kubernetes.io/enforce=privileged`,
and only then the chart. The machine-config half goes in
`modules/addons/<name>/patches/` and is passed to `module.talos_cluster` through
its `*_config_patches` inputs; keep those files static, or the cluster ends up
depending on its own addons.

Resist collapsing this into one generic map of charts. Namespace labels, custom
resources ordered after their CRDs, machine-config patches and ordering between
addons all need per-addon code.

## Talos image

`customization.yaml` is the single source of truth for the image. Terraform
derives the installer schematic from it, and `vm-templates` builds the boot image
from the same file, so the two cannot disagree. Adding an extension is one line
there.

Extensions only activate on install or upgrade, so adding one to a running
cluster is a `talosctl upgrade --image ...` — a rolling reboot — not just an
apply.

## Usage

```bash
make apply
make generate   # writes ~/talosconfig and ~/.kube/config
```

`terraform apply` also writes a kubeconfig to `.kube/config` inside this
directory, because the `helm` provider needs one to reach the cluster.

## Networking

`cni = "cilium"` makes Talos deploy neither Flannel nor kube-proxy, and the
addons module installs Cilium to cover both roles. Set `cni = "flannel"` to fall
back to the Talos defaults.

LoadBalancer services get an address from `load_balancer_ip_range`, announced on
the LAN over ARP by Cilium L2 announcements. The range has to be free on the
node subnet: outside any DHCP scope, clear of the node addresses and of
`controlplane_vip`.

| Setting                  | Value                         |
| ------------------------ | ----------------------------- |
| Nodes                    | 192.168.1.201-192.168.1.204   |
| Control-plane VIP        | 192.168.1.99                  |
| LoadBalancer pool        | 192.168.1.60-192.168.1.98     |

## Ordering

Bootstrapping only means Talos accepted the call, so `data.talos_cluster_health`
gates the addons on the cluster actually being up. Cilium is installed only
after it passes.

The Kubernetes-level checks stay enabled deliberately, because they are the only
ones that prove the API server answers requests. Talos skips the two that cannot
pass without a CNI — node readiness and coredns — as soon as the machine config
says `cni: none`, and the kube-proxy check skips itself when the DaemonSet is
gone. `skip_kubernetes_checks = true` would leave only Talos-level checks, none
of which touch Kubernetes.

`wait_for_health = false` disables the gate, which is also how you plan against
a cluster that is powered off.

### Known issue: nodes stuck at stage "booting"

`wait_for_health` is currently off. `customization.yaml` bakes the NVIDIA
extensions into the image used by every node, but only `worker1` has a GPU. On
the others `ext-nvidia-persistenced` waits forever for
`/sys/bus/pci/drivers/nvidia`, so the boot sequence never completes and Talos
reports stage `booting` even though every service is healthy:

```bash
talosctl -n 192.168.1.201 get machinestatus   # stage: booting, ready: true
talosctl -n 192.168.1.201 service             # ext-nvidia-persistenced Waiting
```

Kubernetes is unaffected — all nodes report `Ready`. What it does break is
anything that waits on Talos boot stage, including `talosctl health` and this
health check. Fixing it means giving GPU-less nodes an image without the NVIDIA
extensions, which is a separate schematic and a node upgrade.

The `helm` provider reads `.kube/config`, a file Terraform writes itself.
Because the provider is configured from the resource attribute rather than a
literal path, it is set up only after the file exists, and a single
`terraform apply` covers a cluster built from scratch.

## Migrating an existing cluster off Flannel

Talos stops rendering the Flannel and kube-proxy manifests once the new machine
configuration is applied, but it does not delete what it already created. After
`terraform apply`, remove the leftovers and restart everything that still holds
a Flannel address:

```bash
# Confirm Talos no longer manages either component.
talosctl -n 192.168.1.201 get manifests

kubectl -n kube-system delete daemonset kube-flannel kube-proxy
kubectl -n kube-system delete configmap kube-flannel-cfg kube-proxy

# Clear the iptables rules kube-proxy left behind, and give pods Cilium IPs.
talosctl -n 192.168.1.201,192.168.1.202,192.168.1.203,192.168.1.204 reboot
```

Then check that Cilium owns service routing:

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -E 'KubeProxyReplacement|L2'
```

Expect `KubeProxyReplacement: True` and L2 announcements enabled. Pod networking
is down between the reboot and Cilium becoming ready.
