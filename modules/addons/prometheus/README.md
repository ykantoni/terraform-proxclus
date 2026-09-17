# Prometheus Addon Module

Installs [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) —
Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics and a set
of default alerting rules/dashboards — for cluster monitoring.

## Responsibilities

This module manages:

- the `monitoring` namespace (`var.namespace`), labelled
  `pod-security.kubernetes.io/enforce=privileged`
- the `kube-prometheus-stack` Helm release into that namespace: Prometheus
  (via the Prometheus Operator the chart also installs), Alertmanager,
  Grafana, the `prometheus-node-exporter` DaemonSet, and `kube-state-metrics`

It expects a bootstrapped cluster and the `helm`/`kubernetes` providers to be
configured by the caller. It creates no namespace besides its own and needs
nothing from Talos machine configuration or the image schematic.

## Why `kubeEtcd`/`kubeScheduler`/`kubeControllerManager`'s `endpoints = var.controlplane_ips`

The chart's `kube-etcd`, `kube-scheduler` and `kube-controller-manager`
dashboards each expect a Kubernetes `Endpoints` object auto-populated by
matching a labelled static pod (kubeadm's convention). Talos runs all three
as host-level processes, not Kubernetes pods, so nothing ever matches those
selectors and every one of those `Endpoints` objects stays permanently
empty — every panel on all three dashboards shows "No data" regardless of
whether the components themselves are healthy. Each has the identical,
chart-documented escape hatch ("If your etcd/scheduler/controller manager is
not deployed as a pod, specify IPs it can be found on"); pointing all three
at the actual control-plane IPs gives Prometheus something to scrape.

## Why the privileged namespace label

`prometheus-node-exporter` reads host-level CPU/memory/disk/network metrics
by running with `hostNetwork: true`, `hostPID: true`, and `hostPath` mounts of
`/proc` and `/sys` — all forbidden under the restricted Pod Security Standard.
This is the same shape of problem `modules/addons/longhorn` has with its
engine and CSI plugin pods, solved the same way: label the whole namespace
`privileged` rather than trying to scope it to just the exporter's pods.

Unlike Longhorn, none of this needs a Talos machine-config patch: `/proc` and
`/sys` are already present in every pod's mount namespace by default, so
nothing extra needs exposing from the host side.

## Why `serviceMonitorSelectorNilUsesHelmValues = false` (and the `podMonitor`/`rule` equivalents)

The chart's own default only lets Prometheus discover `ServiceMonitor`,
`PodMonitor` and `PrometheusRule` objects that carry this Helm release's own
label — meant for multi-tenant clusters where each Prometheus should only
scrape what it's explicitly told to. This cluster runs a single Prometheus
for everything on it, so all three are set to `false` here: any addon or app
that ships a `ServiceMonitor`/`PodMonitor`/`PrometheusRule` gets picked up
automatically, with no release label to remember to add.

## Why `grafana.sidecar.datasources.searchNamespace = "ALL"`

The chart's `grafana-sc-dashboards` sidecar already scans every namespace by
its own default (an empty list selector), but `grafana-sc-datasources`
defaults to the release namespace only (`monitoring`) — an inconsistency
between the two sidecars in the chart itself, not a deliberate restriction.
Left at that default, a data source ConfigMap shipped by an addon in its own
namespace (`modules/addons/loki`, for one) is invisible to Grafana even
though it carries the right `grafana_datasource` label. `ALL` makes the two
sidecars consistent, matching the `serviceMonitorSelectorNilUsesHelmValues`
reasoning above: no addon needs to know Grafana's namespace to be picked up.

## Why `grafana.deploymentStrategy.type = "Recreate"`

Grafana runs as a `Deployment`, not a `StatefulSet`, but its PVC is still
`ReadWriteOnce`. The chart's default `RollingUpdate` strategy starts the
replacement pod before killing the old one; with a single replica and an RWO
volume, the new pod can never attach it (`Multi-Attach error ... Volume is
already used by pod(s)`) and the rollout deadlocks — every subsequent `helm
upgrade` hangs until its own `wait` timeout, whether or not the values change
actually touch Grafana. `Recreate` kills the old pod first, so the new one
can mount the volume once it's free.

## Why `grafana.extraEmptyDirMounts` on `/usr/share/grafana/data/plugins-bundled`

Grafana's container runs with `readOnlyRootFilesystem: true`. Its background
plugin-update pass — on by default, unrelated to the `pluginsAutoUpdate`
feature toggle, which only gates whether it's surfaced in the UI — still
tries to self-update bundled plugins under
`/usr/share/grafana/data/plugins-bundled` on every startup, prometheus and
loki included. It kills the running plugin's process first, then fails to
write the replacement (`unlinkat ...: read-only file system`), which
permanently breaks that plugin for the pod's lifetime: it disappears from
`/api/plugins` and therefore from every datasource picker, Explore's
included, even though the datasource itself is still correctly provisioned.
Alertmanager was the one plugin that happened to have no pending version
bump, which is why it alone kept working. A writable `emptyDir` at just this
one path lets the update pass actually succeed, without loosening
`readOnlyRootFilesystem` anywhere else.

## Inputs

- `kube_prometheus_stack_version`
- `namespace`
- `storage_class`
- `prometheus_storage_size`
- `prometheus_retention`
- `prometheus_service_type`
- `alertmanager_storage_size`
- `enable_grafana`
- `grafana_storage_size`
- `grafana_service_type`
- `grafana_admin_password`
- `controlplane_ips`
- `kube_prometheus_stack_extra_values`
- `helm_timeout`

## Outputs

- `kube_prometheus_stack_version`
- `namespace`
- `prometheus_service_type`
- `grafana_service_type`

## Notes

`storage_class` defaults to `"longhorn"`, matching `apps/postgres-cnpg`'s own
default: it requires `enable_longhorn = true` on the root module. Without it
there is no StorageClass by that name, every PVC (Prometheus's, Alertmanager's
and Grafana's) stays `Pending`, and `helm_release.kube_prometheus_stack` times
out under its own `wait = true`.

`grafana_admin_password` defaults to the chart's own default
(`"prom-operator"`). Change it before leaving `grafana_service_type` at its
default of `LoadBalancer`, which puts Grafana's login page on the LAN.
