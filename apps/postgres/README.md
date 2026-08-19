# Postgres (primary + standby)

Deploys a two-instance PostgreSQL cluster — one primary, one
streaming-replication standby — onto an existing Kubernetes cluster, via the
[CloudNativePG](https://cloudnative-pg.io/) (CNPG) operator.

## Independence

This is one of possibly several app stacks under `../` (see `../README.md`
for the general convention). Each is a separate, self-contained Terraform
root, not a module of the platform or of each other:

- its own state, at `/home/yurick/terraform/state/postgres.tfstate`, set in
  `versions.tf` — separate from the platform's `terraform.tfstate` and from
  every other app's state
- its own providers (`helm`, `kubernetes`), configured from a plain,
  absolute kubeconfig file path (`var.kubeconfig_path`), not from anything
  in the platform's state or module outputs
- its own lifecycle: `terraform init`/`plan`/`apply`/`destroy` from inside
  this directory, on its own schedule, independent of the platform and of
  every other app

So there's no state or module coupling to the platform, or to any other app,
at all — only a *runtime* one: the cluster at `kubeconfig_path` has to exist
and be reachable, and it needs a working default StorageClass (the platform
sets up Longhorn for that; see `../../modules/addons/longhorn`). Point
`kubeconfig_path` at a kubeconfig for any other cluster and this stack works
the same way.

## What it deploys

- `kubernetes_namespace.operator` (`cnpg-system`) and the CNPG operator
  itself, via `helm_release.cnpg_operator` — installs the `Cluster` CRD (and
  others) plus the operator Deployment. The operator watches every namespace,
  so this is a one-time install regardless of how many Postgres clusters you
  later add.
- `kubernetes_namespace.postgres` (`postgres`) and one CNPG `Cluster` inside
  it, via `helm_release.postgres_cluster` — a tiny local chart
  (`charts/postgres-cluster`) templating a single `Cluster` manifest. See
  `main.tf` for why this is a Helm release rather than a
  `kubernetes_manifest` resource.

`var.instances` (default `2`) is the whole cluster shape: CNPG turns instance
1 into the primary and streams WAL to every instance after it, promoting a
standby automatically if the primary goes down. Nothing here hand-configures
`primary_conninfo`, replication slots, or `pg_basebackup` — that's the
operator's job.

## Credentials

Terraform never touches a database password. CNPG generates and manages two
Secrets per cluster, both readable with `kubectl -n <namespace> get secret
<name> -o yaml`:

- `<cluster_name>-superuser` — the `postgres` superuser
- `<cluster_name>-app` — `database_owner`'s password, plus a ready-to-use
  `uri` key for `database_name`

Both names are exposed as outputs (`superuser_secret`, `app_secret`) so
scripts can look them up without hardcoding the `<cluster_name>-*` pattern.

## Storage

The default `storage_class = "longhorn"` gives every instance's PVC 3x
Longhorn-level replication (see `../../modules/addons/longhorn`'s
`replica_count`) *on top of* Postgres's own primary/standby replication
between instances — two independent redundancy layers stacked, which costs
extra disk and write I/O for redundancy this setup arguably already has at
the application layer. Worth trimming once this is more than a smoke test:
create a second Longhorn StorageClass with `numberOfReplicas: "1"` and point
`storage_class` at it, so Longhorn stores exactly one copy per instance and
lets CNPG's own replication be the only redundancy.

## Usage

```bash
cd apps/postgres
terraform init
just apply
```

Verify replication came up:

```bash
kubectl -n postgres get cluster
kubectl -n postgres get pods -l cnpg.io/cluster=postgres
kubectl cnpg status postgres -n postgres   # needs the kubectl-cnpg plugin
```

`instances: 2/2` and one pod reporting `role: primary` with the other
`role: replica` means the standby is caught up and streaming.
