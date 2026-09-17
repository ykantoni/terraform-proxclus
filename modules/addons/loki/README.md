# Loki Addon Module

Installs [Loki](https://github.com/grafana/loki/tree/main/production/helm/loki)
(single-binary, filesystem storage) and
[Promtail](https://github.com/grafana/helm-charts/tree/main/charts/promtail)
for centralized log aggregation, queryable from Grafana.

## Responsibilities

This module manages:

- the `logging` namespace (`var.namespace`), labelled
  `pod-security.kubernetes.io/enforce=privileged`
- the `loki` Helm release into that namespace, running Loki as a single
  binary against a filesystem-backed PVC
- the `promtail` Helm release, a DaemonSet that tails every node's container
  logs and ships them to Loki
- (optionally) a ConfigMap that gets Loki auto-added as a Grafana data source

It expects a bootstrapped cluster and the `helm`/`kubernetes` providers to be
configured by the caller. It creates no namespace besides its own and needs
nothing from Talos machine configuration or the image schematic.

## Why the privileged namespace label

Promtail reads every pod's logs by running a DaemonSet with hostPath mounts
of `/var/log/pods` and `/var/lib/docker/containers`, both forbidden under the
restricted Pod Security Standard. Same shape of problem
`modules/addons/prometheus`'s `prometheus-node-exporter` has, solved the same
way: label the whole namespace `privileged` rather than trying to scope it to
just Promtail's pods. Loki itself needs no such privilege; it just inherits
the namespace's label.

## Why single-binary and filesystem storage, not the chart's defaults

The chart defaults to `deploymentMode: SimpleScalable`: separate read, write
and backend Deployments behind an nginx gateway, backed by S3-compatible
object storage (Minio, if nothing else is configured). That shape is built
for query load and log volume this cluster doesn't have, so this module
overrides it to `SingleBinary`: one pod, one PVC (`var.storage_class`,
`var.loki_storage_size`), storing chunks and the TSDB index on the local
filesystem instead of an object store. `gateway`, `minio`, `test`,
`lokiCanary`, `chunksCache` and `resultsCache` are all disabled to match —
each exists to support the distributed shape or the object-storage gateway
this module doesn't use. Promtail pushes straight to Loki's own Service
(`http://loki.<namespace>.svc.cluster.local:3100`) instead of a gateway that
was never created.

## Retention

TSDB retention is enforced by the compactor, not by the older `tableManager`
mechanism the chart's own default `retention_period` comment refers to (that
one only applies to legacy chunk stores). `loki.compactor.retention_enabled`
and `loki.compactor.delete_request_store` turn deletion on;
`loki.limits_config.retention_period` (`var.loki_retention_period`, default
`31d`) sets how long logs live before the compactor removes them.

## Grafana wiring

`enable_grafana_datasource = true` (the default) creates a ConfigMap labelled
`grafana_datasource: "1"`. kube-prometheus-stack's Grafana runs a k8s-sidecar
(`grafana-sc-datasources`) that watches for that label and provisions
matching data sources automatically, across every namespace — but only once
`modules/addons/prometheus`'s `grafana.sidecar.datasources.searchNamespace =
"ALL"` is set, since the sidecar's own chart default scopes it to Grafana's
release namespace only. See that module's README for why. This module needs
no changes to know about `modules/addons/prometheus` beyond that one setting
already being there, and is harmless with `enable_prometheus = false`: the
ConfigMap just sits unused until a Grafana with that sidecar exists.

## Inputs

- `namespace`
- `storage_class`
- `loki_version`
- `loki_storage_size`
- `loki_retention_period`
- `promtail_version`
- `enable_grafana_datasource`
- `loki_extra_values`
- `promtail_extra_values`
- `helm_timeout`

## Outputs

- `loki_version`
- `promtail_version`
- `namespace`

## Notes

`storage_class` defaults to `"longhorn"`, matching
`modules/addons/prometheus`'s own default: it requires `enable_longhorn =
true` on the root module. Without it there is no StorageClass by that name,
Loki's PVC stays `Pending`, and `helm_release.loki` times out under its own
`wait = true`.

Loki has no LoadBalancer exposure of its own: query it through Grafana's
Explore tab (once `enable_grafana_datasource` has wired it in) rather than
its raw API.
