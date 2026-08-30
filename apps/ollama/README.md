# Ollama + Open WebUI

Deploys [Ollama](https://ollama.com/) (via the
[otwld/ollama-helm](https://github.com/otwld/ollama-helm) chart) scheduled
onto a GPU node, and [Open WebUI](https://openwebui.com/) in front of it, so
which model is loaded is a decision made from the browser — not from
Terraform — after this stack is up.

## Independence

This is one of possibly several app stacks under `../` (see `../README.md`
for the general convention). Each is a separate, self-contained Terraform
root, not a module of the platform or of each other:

- its own state, at `/home/yurick/terraform/state/ollama.tfstate`, set in
  `versions.tf` — separate from the platform's `terraform.tfstate` and from
  every other app's state
- its own providers (`helm`, `kubernetes`), configured from a plain,
  absolute kubeconfig file path (`var.kubeconfig_path`), not from anything
  in the platform's state or module outputs
- its own lifecycle: `terraform init`/`plan`/`apply`/`destroy` from inside
  this directory, on its own schedule, independent of the platform and of
  every other app

## What it deploys

- `kubernetes_namespace.ollama` (`ollama`)
- `helm_release.ollama` — the Ollama server, with (when `gpu_enabled`, the
  default) `ollama.gpu.type: nvidia`, a `nodeSelector` on
  `nvidia.com/gpu.present=true`, and `runtimeClassName: nvidia`, so its pod
  only schedules onto — and only ever runs on — a node with a GPU. A
  `persistentVolume` (`ollama_storage_size`, default `15Gi`) stores pulled
  models so they survive pod restarts.
- `kubernetes_storage_class_v1.ollama_models` (`ollama-local`) and
  `kubernetes_persistent_volume_v1.ollama_models` — a no-provisioner
  StorageClass backed by a statically provisioned `local` PV pointed at
  `ollama_storage_path` on the GPU node, used by that PVC instead of the
  platform's `longhorn` default. See "Storage" below for why.
- `helm_release.open_webui` — the chat UI, pointed at the Ollama release
  above via `ollamaUrls` (its own bundled Ollama subchart is disabled),
  exposed as a `LoadBalancer` Service by default since this cluster runs no
  ingress controller (see root README's "Networking" section). It gets its
  own small PVC (`webui_storage_size`, default `2Gi`) for chat history,
  accounts, and uploaded files — separate from Ollama's model storage.

## Choosing a model

Nothing here pulls a model by default (`models_to_pull` defaults to `[]`).
Once both releases are up:

```bash
kubectl -n ollama get svc open-webui   # find the LoadBalancer address
```

Open that address, create the first account (becomes admin), then
**Settings → Admin Settings → Models** to pull any model from Ollama's
library by name (e.g. `llama3.1:8b`, `qwen2.5:14b`) — this calls Ollama's
own `/api/pull` under the hood, no redeploy needed. Switch which model a
chat uses from the model picker at the top of the chat window. `models_to_pull`
still exists for pre-seeding a model at first boot if you'd rather not wait
on the first pull from the UI.

## Storage

This cluster's VM disks default to a small `32Gi` root filesystem
(`var.nodes[*].disk` in the root module), of which Longhorn only ever sees
part as free space. The platform's own `longhorn` StorageClass replicates
every volume 3x on 3 separate nodes, so it needs the *entire* requested size
free on three nodes at once — a `30Gi` PVC fails outright on hardware this
small (`insufficient storage;precheck new replica failed` from Longhorn),
even with nothing else on the cluster yet. Pulled models are re-downloadable
cache, not data worth replicating, or worth Longhorn's iSCSI engine overhead
on top of the same node's disk even at a single replica — so Ollama's PVC
instead uses `ollama-local`: a `local` PV, statically bound to
`ollama_storage_path` (default `/var/lib/ollama-models`) on the GPU node
itself (`gpu_node_selector`), with no Longhorn involved at all.
`webui_storage_size` (small, `2Gi`) stays on the platform default `longhorn`
class, since chat history/accounts are worth actually replicating.

Because it's statically provisioned, that directory has to already exist,
be writable, and persist across reboots on the GPU node *before* `terraform
apply` — Terraform only creates the `PersistentVolume` object, not the
directory it points at. On Talos, a path also generally needs an
`extraMounts` patch on that node's machine config before pods can use it
(see `../../modules/addons/longhorn/patches/longhorn-mounts.patch.yaml` for
the pattern this cluster already uses to expose `/var/lib/longhorn` the same
way).

Set `ollama_storage_class = "longhorn"` to go back to Longhorn-backed
storage instead, and raise `var.nodes[*].disk` on the GPU node in the root
module first if you do — or if you need more room for bigger models than
`ollama_storage_size`'s default leaves space for on the local disk.

## Platform dependency

Beyond the general runtime dependency every app here has on the cluster
being reachable (see `../README.md`), this stack specifically depends on
`../../modules/addons/nvidia-device-plugin` already having run against a
node with `pcigpu` set: that's what creates the `nvidia` RuntimeClass and
the `nvidia.com/gpu.present=true` node label `gpu_node_selector` and
`runtime_class_name` point at. Without it, `helm_release.ollama`'s pod stays
unschedulable. This is a runtime dependency only, checked the same way as
the default StorageClass — no Terraform reference into the platform's state.

Set `gpu_enabled = false` to drop the GPU scheduling entirely and run Ollama
on CPU (works, but slow for anything beyond small models).

## Usage

```bash
cd apps/ollama
terraform init
just apply
```

```bash
kubectl -n ollama get pods
kubectl -n ollama get svc open-webui
```
