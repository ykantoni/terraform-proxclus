# Apps

Applications deployed onto the cluster that `../` builds, each as its own
independent Terraform root. `postgres/` is the first and the reference
example; more get added the same way as they show up.

## The convention

Every app under here is a **separate Terraform root**, not a module —
Terraform can't parameterize root-only concerns like `backend` or `provider`
blocks through a `module` call, so there's no way to make this DRY without
giving up the isolation it exists for. Copy `postgres/`'s shape for a new
one:

- **Directory**: `apps/<name>/`
- **State**: its own `backend "local" { path = "/home/yurick/terraform/state/<name>.tfstate" }`
  in `versions.tf` — never the platform's `terraform.tfstate`, never another
  app's
- **Providers**: `helm`/`kubernetes` (or whatever the app needs), configured
  from a `kubeconfig_path` variable — an absolute path, defaulting to
  `/home/yurick/terraform/talos-proxmox/.kube/config` — never from a
  reference into `../`'s state or outputs
- **A dedicated namespace**, named after the app, created by the app's own
  `main.tf`. Beyond keeping Kubernetes objects tidy, it makes the blast
  radius visible from `kubectl` too, not just from Terraform state.
- **Its own `Justfile`** (`apply`/`destroy`/`fmt`) and **`README.md`**
  documenting what it deploys and repeating this independence contract, so
  each app is fully understandable without reading `postgres/`'s docs first.

Directory name, state file name, and primary namespace name should all match
the app name — that's what makes "which state owns what" traceable at a
glance instead of something you have to go read code to answer.

## What this guarantees, and what it doesn't

**Guaranteed, by the state separation:** `terraform destroy` inside
`apps/<name>` can only touch resources recorded in `<name>.tfstate`. It
cannot reach the platform's VMs or Talos configuration — those live in a
state file this directory never references — and it cannot reach another
app's resources for the same reason. This is enforced by convention (no app
here should ever have a `module` block pointing at `../modules/*` or at a
sibling app) rather than by tooling, so it's a rule to hold the line on when
adding new apps, not something Terraform stops you from breaking.

**Not guaranteed:** runtime isolation between apps. Kubernetes does not wall
namespaces off from each other by default — no NetworkPolicy, no RBAC
boundary, no resource quota, unless something adds one. Every app here also
shares the same underlying node CPU/RAM/disk and the same default
StorageClass, so a noisy or storage-hungry app is a real risk to its
neighbors even though its Terraform state is fully separate from theirs. If
that matters for a given app (say, something that shouldn't be reachable
from Postgres), that's a deliberate addition to make in that app's own
config — a `CiliumNetworkPolicy`, a `ResourceQuota` — not something this
directory structure hands you for free.

## Platform dependency

Every app here has a runtime dependency on the platform being up — the
cluster at `kubeconfig_path` has to exist and answer, and most will lean on
the default StorageClass Longhorn provides (`../modules/addons/longhorn`).
None of that is a Terraform dependency: nothing here is wired into
`../addons.tf` or gated on `../`'s apply, so an app can be created or torn
down at any time without touching, or being blocked by, the platform's own
lifecycle.
