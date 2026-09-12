# talos-proxmox — Ansible

Ansible re-implementation of the Terraform project one level up
(`../modules`, `../apps`, `../vm-templates`, `../proxmox-host`): a Proxmox VE
+ Talos Linux + Kubernetes homelab platform, its addons, and its
applications. Same separation of concerns, same node/addon/app set, no
Terraform required from here on.

**This directory was generated as a from-scratch rewrite. Nothing here has
been run yet.** Read this whole file, review every role/playbook, and work
through the checklist below before pointing it at anything real — especially
the "Adopting an already-running cluster" section if `../terraform.tfvars`
already describes a live cluster.

## How this maps to the Terraform project

| Terraform | Ansible |
|---|---|
| `modules/proxmox-talos-vm` | `roles/proxmox_vm` |
| `modules/talos-cluster` + `schematic.tf` | `roles/talos_bootstrap` + `roles/talos_schematic` |
| `modules/addons/cilium` | `roles/addon_cilium` |
| `modules/addons/longhorn` | `roles/addon_longhorn` |
| `modules/addons/metrics-server` | `roles/addon_metrics_server` |
| `modules/addons/nvidia-device-plugin` | `roles/addon_nvidia_device_plugin` |
| `modules/addons/prometheus` | `roles/addon_prometheus` |
| `apps/ollama` | `roles/app_ollama` |
| `apps/postgres-cnpg` | `roles/app_postgres_cnpg` |
| `apps/postgres` (plain `kubectl apply`) | `roles/app_postgres_plain` |
| `vm-templates/*.sh` (never Terraform) | `roles/proxmox_vm_template` |
| `proxmox-host/` (never Terraform) | `roles/proxmox_host_prep` |
| `.tfvars` / `variables.tf` defaults | `inventory/production/group_vars/`, `host_vars/` |
| `terraform.tfstate` | *(none — see "How this differs from Terraform" below)* |

## What has and hasn't been done yet

This directory was generated file-by-file from the Terraform project's
actual resources/values (`../terraform.tfvars`, `../modules/**/*.tf`,
`../apps/**/*.tf`, the vendored Helm charts and Talos patch files) — nothing
was invented or left as a `TODO` placeholder. What was **not** done, by
design, because it requires contacting real infrastructure:

- No tool was installed anywhere (not even on this Proxmox host).
- No command was run against the Proxmox API, Talos, or Kubernetes.
- No existing host config, VM, or cluster was touched.
- `vault.yml` was **not** created or encrypted — only the plaintext
  `vault.yml.example` placeholder exists; you create and encrypt the real
  one yourself (see "Vault setup" below).

So before the first real run, budget time to: install the prerequisites,
create and encrypt `vault.yml`, and — per the module-name caveats called out
inline in `roles/proxmox_vm/tasks/main.yml` and the `talos_bootstrap` task
files — sanity-check the exact collection/CLI versions you end up with
against what's written there.

## What must be installed before any of this works

Run everything from the Proxmox host itself (`jupiter`) — that's what
`inventory/production/hosts.yml` assumes (`ansible_connection: local` for
every host in this inventory; see "Why every host is `ansible_connection:
local`" below).

- **Ansible core ≥ 2.16** (`pipx install ansible-core` or your distro package)
- **Python 3.10+** with the packages in `requirements.txt`:
  ```bash
  python3 -m venv .venv && . .venv/bin/activate   # optional but recommended
  pip install -r requirements.txt
  ```
- **Ansible collections** in `requirements.yml`:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  # or: just collections
  ```
- **External CLIs**, installed on the same host, on `$PATH`:
  - `helm` v3 — `kubernetes.core.helm` shells out to it
  - `talosctl`, matching `talos_version` in `group_vars/all/vars.yml` (`v1.13.8`) — no Python equivalent exists, every Talos step shells out to it
  - `kubectl` — used by a couple of raw checks (e.g. `teardown-addons.yml`'s reachability probe); handy for troubleshooting regardless
  - `qm` / `pvesh` — already present on any Proxmox VE host

## Why every host is `ansible_connection: local`

- `jupiter` (the `proxmox_hosts` group): this project assumes Ansible runs
  *on* the Proxmox host, the same way the Terraform project's `just t-create`
  ran `qm`/`wget`/`curl` locally as root. No SSH trust to set up.
- `cp1`, `w1`–`w5` (the `talos_nodes` group): **Talos Linux runs no SSH
  daemon at all** — it's an immutable, API-only OS. Every task targeting
  these hosts actually runs on the control node and talks to the node over
  the Talos API (`talosctl -n <ip> -e <ip> ...`) or the Kubernetes API
  (`kubeconfig`), never SSH. Do **not** add `ansible_user`/SSH keys to these
  hosts' `host_vars` — it would have no effect on how anything here connects
  to them.

## Proxmox authentication

Reuse (or regenerate) the same Proxmox API token the Terraform project used
(`PROXMOX_VE_API_TOKEN`, currently a plaintext export in `~/.bashrc`) — but
store it in `ansible-vault` here instead of a shell profile.

## Vault setup (secrets)

Every secret (Proxmox API token, Grafana admin password, plain-Postgres
credentials) lives in `ansible-vault`-encrypted YAML, never in plaintext
`group_vars`.

```bash
mkdir -p ~/.ansible
echo -n 'a strong, unique passphrase' > ~/.ansible/talos-proxmox-vault-pass
chmod 600 ~/.ansible/talos-proxmox-vault-pass
```

`ansible.cfg` already points `vault_password_file` at that path, so
`ansible-playbook`/`ansible-vault` pick it up automatically. (You can still
use `--ask-vault-pass` instead if you'd rather not keep a password file —
just don't pass both.)

Then create the real secrets file from the committed placeholder template:

```bash
cd inventory/production/group_vars/all
cp vault.yml.example vault.yml
$EDITOR vault.yml        # fill in real values — see the comments in the file
ansible-vault encrypt vault.yml
```

From then on, **never edit `vault.yml` directly** — use:

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

`vault.yml` is gitignored; `vault.yml.example` (placeholders only) is meant
to be committed.

## Inventory

Static, hand-maintained (`inventory/production/hosts.yml` +
`group_vars/`/`host_vars/`) — six fixed nodes, no dynamic inventory plugin.
`host_vars/*.yml` were copied 1:1 from `../terraform.tfvars`' `nodes` map; if
you change a node's IP/MAC/cores/memory/disk/`pcigpu` there in the future,
edit the matching `host_vars/<node>.yml` here instead (there's no single
shared source of truth between the two projects — see "How this differs
from Terraform" below).

There is deliberately **no separate `gpu_nodes` group**: GPU presence is
derived from whichever hosts have `pcigpu` set in their `host_vars`, the
same single-source-of-truth design `addons.tf` used.

## Usage

All commands assume `cd ansible/` first. `just` recipes are thin wrappers
around the equivalent `ansible-playbook` command shown next to each.

```bash
# First-time bootstrap of a brand-new cluster, end to end
just apply
# = ansible-playbook -i inventory/production/hosts.yml playbooks/site.yml

# Addons only
just addons
# = ansible-playbook -i inventory/production/hosts.yml playbooks/40-addons.yml

# One app only
just app ollama          # or postgres-cnpg / postgres-plain
# = ansible-playbook -i inventory/production/hosts.yml playbooks/50-apps.yml --tags ollama

# Dry-run / idempotency check (Helm and Kubernetes-module steps only — see caveat below)
just plan

# Tear down one piece
ansible-playbook -i inventory/production/hosts.yml playbooks/teardown-addons.yml --tags prometheus

# Full teardown: apps -> addons (Longhorn delete-protection patch first) -> VMs
just destroy
```

**`--check`/`--diff` caveat**: `talosctl`- and `qm`-backed `command` tasks
(machine-config apply, cluster bootstrap, VM template builds) don't have a
meaningful dry-run mode — they rely on their own `creates:`/`changed_when`
guards for idempotency instead (see "Idempotency" below). `--check --diff`
is fully accurate only for the Helm/`kubernetes.core.k8s`-backed addon and
app plays.

**GPU host reboot**: `roles/proxmox_host_prep` never reboots the Proxmox
host on its own — `vfio.conf` changes need a reboot to take effect, and
rebooting a hypervisor is destructive to whatever it's currently running.
Pass `-e allow_host_reboot=true` only when you're actually ready for that.

## Idempotency, without a state file

Ansible has no `.tfstate` — most modules here (Helm, `kubernetes.core.k8s`,
`community.proxmox.proxmox_kvm`) re-query live state on every run and are
naturally idempotent the same way Terraform's providers are. A few steps
that Terraform tracked via state instead use an explicit guard:

| Step | Guard |
|---|---|
| VM template build | `creates: /etc/pve/qemu-server/<vmid>.conf` |
| Talos secrets generation | `creates:` on the secrets bundle path — **never regenerate this against a live cluster**, see below |
| Base talosconfig/machine-config generation | `creates:` on `talosconfig` |
| Per-node machine-config apply | only runs when the freshly-rendered config differs from the last rendered copy |
| Cluster bootstrap | tolerates `AlreadyExists`/"etcd data directory is not empty" |
| Kubeconfig fetch | `creates:` — delete the file by hand to force a refresh |

## Adopting an already-running cluster

If `../terraform.tfvars` currently describes a **live** cluster, do not just
run `just apply` and hope — read the migration plan this project was
designed against (ask whoever generated this repo for it, or see git log
around this commit) before touching anything. The single highest-risk step:

**Never run `talosctl gen secrets` against a node that already has a machine
config applied.** It mints a brand-new cluster CA incompatible with every
already-issued certificate. Before the first real run against a live
cluster, extract the existing secrets from Terraform's own state
(`terraform state show module.talos_cluster.talos_machine_secrets.this`, run
from `..`) and pre-seed them at the exact path
`talos_secrets_path` resolves to (`group_vars/all/vars.yml`,
`~/.talos/<cluster_name>/secrets.yaml` by default) *before* running
`playbooks/30-bootstrap-talos.yml` for the first time, so its `creates:`
guard sees the file already present.

Similarly, before adopting the already-running `apps/postgres` (plain), seed
`vault.yml`'s `vault_postgres_plain_*` values with the **exact current live
passwords** (read them out of the existing Kubernetes Secrets) so the first
templated apply is byte-identical — rotate to genuinely new credentials only
afterward, as a separate step.

## How this differs from Terraform (know these going in)

- **No plan/state.** Nothing here shows you a diff before applying (outside
  the `--check` caveat above), and there's no `.tfstate` recording what
  exists. `host_vars`/`group_vars` are the only source of truth for desired
  state; actual state lives in Proxmox/Talos/Kubernetes themselves, queried
  fresh on every run.
- **Module names/params may need adjusting.** `community.proxmox` is a
  younger collection than the Terraform `bpg/proxmox` provider this was
  ported from — `roles/proxmox_vm/tasks/main.yml` and
  `roles/talos_bootstrap`'s `talosctl` invocations carry inline comments
  flagging exactly what to double-check (`ansible-doc
  community.proxmox.proxmox_kvm`, `talosctl machineconfig patch --help`)
  before the first real run.
- **`../terraform.tfvars` and this project's `host_vars`/`group_vars` are
  two independent copies of the same facts**, not one shared source. Once
  you're running this in production, update Ansible's copy going forward and
  retire the Terraform code (see the migration plan) rather than maintaining
  both.
