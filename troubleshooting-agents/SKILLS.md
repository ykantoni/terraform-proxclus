# Skills format

A **skill** is one read-only diagnostic action an agent can call as a tool:
"run `talosctl service` on a node", "tail the ollama pod's logs", "read
`nvidia-smi` from inside the GPU pod", "ssh in and check `journalctl` on the
Proxmox host". Skills are declarative — each one is a single Markdown file
under [backend/skills/catalog/](backend/skills/catalog/) with YAML
frontmatter that `backend/skills/loader.py` turns into a LangChain tool.
Nothing about a skill is Python; adding one is adding a file.

This mirrors the Claude Skill shape already used elsewhere in this
environment (frontmatter for the machine, body for the human), simplified to
what a shell/HTTP diagnostic call needs.

## Why declarative

An agent only needs a short, well-written **description** to decide whether
a tool is relevant — that's the whole interface between "the model" and "the
skill". Everything else (which binary, which host, which flags, which
params) is bookkeeping the loader can do generically. Keeping that
bookkeeping as data instead of one Python function per command is what makes
"add a diagnostic" a five-minute, no-code change: copy a similar file in
`catalog/`, edit the frontmatter, done. See "Adding a skill" below.

## File shape

```markdown
---
name: talos-service-status          # unique id, kebab-case; matches the filename stem by convention
description: >
  Show the status of Talos-managed services on a node (talosctl service).
  Use this to see which services are running, stopped, or crash-looping.
agents: [talos]                     # agent id(s) allowed to use this skill, or ["*"] for all
target: local                       # local | ssh | kubectl | http
safe: true                          # true = read-only, runs without confirmation (see "Safety" below)
timeout: 20                         # seconds

command: ["talosctl", "-n", "{node}", "service", "{service}"]

params:
  node:
    type: string
    description: Node IP to query
    default: "${TALOS_VIP}"         # "${VAR}" pulls a default from backend/config.py at load time
  service:
    type: string
    description: Specific service name, or empty for all services
    default: ""
---

Human documentation goes here: when to reach for this skill, how to read its
output, known gotchas. This body is **not** sent to the model — it's for
whoever is maintaining the catalog. Keep the frontmatter `description` the
place where anything the *agent* needs to know actually lives.
```

## Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | Unique id. Becomes the LangChain tool name. |
| `description` | yes | Sent to the LLM verbatim as the tool description — the only thing the model sees when deciding to call this skill. Be specific about what it shows and when to use it. |
| `agents` | yes | List of agent ids that get this tool, or `["*"]` for every agent. A skill attaches itself to agents — agent files don't enumerate skills — so dropping a new file into `catalog/` is enough to wire it up. |
| `target` | yes | One of `local`, `ssh`, `kubectl`, `http` — see below. |
| `safe` | no (default `true`) | `true` = executes immediately. `false` = the generated tool gains a required `confirm: bool` parameter and refuses to run unless the caller passes `confirm=true`. Everything shipped in this repo is `safe: true`; the flag exists for whoever extends this catalog with something mutating (a restart, a cordon) later. |
| `timeout` | no (default `30`) | Seconds before the underlying process/request is killed. |
| `params` | no | Named parameters the tool exposes, each with `type` (`string` \| `integer` \| `enum`), `description`, optional `default`, and (for `enum`) `choices`. A param with no `default` is required — the model must supply it. |

### `target: local` / `target: ssh`

```yaml
target: local
command: ["kubectl", "get", "pods", "-n", "{namespace}", "-o", "wide"]
```

```yaml
target: ssh
connection: proxmox                 # name of a connection profile in backend/config.py
command: ["journalctl", "-u", "pveproxy", "-n", "{lines}", "--no-pager"]
```

`command` is an argv list, not a shell string — `{param}` placeholders are
substituted per-token and the process is always run without a shell
(`shell=False`), so a parameter value can never be interpreted as a second
command. For `ssh`, each token is additionally `shlex.quote`d before being
joined for the remote shell, which is where the equivalent risk would
otherwise reappear (OpenSSH re-joins argv into one string before handing it
to the remote shell).

### `target: kubectl`

A thin, structured wrapper around the four read-only kubectl verbs this
project needs, so catalog entries don't have to hand-build kubectl argv:

```yaml
target: kubectl
mode: logs                          # exec | logs | get | describe | top
namespace: ollama
selector: "app.kubernetes.io/name=ollama"   # or a literal `pod:` template
container: ollama                   # optional
tail: 200
```

`exec` additionally takes `command: [...]` (the argv run inside the
container). `get`/`describe`/`top` take `resource` (`pods`, `nodes`, `events`,
...) and optional `resource_name`/`extra_args` (`resource_name` rather than
`name`, since `name` is already the skill's own id field above — a YAML
mapping can't repeat a key, so the frontmatter can't reuse it for a second
purpose). Exactly one of `selector` or `pod` resolves the target pod;
`selector` picks the first match.

### `target: http`

```yaml
target: http
method: GET
url: "${OLLAMA_BASE_URL}/api/ps"
```

`url`/`json` bodies are templated the same way as `command`; `${VAR}`
resolves once from `backend/config.py` at catalog-load time, `{param}`
resolves per-call from the tool's arguments.

## Safety

Every skill in this catalog is a **read**: `get`, `describe`, `logs`,
`service` (status), `nvidia-smi`, `journalctl`, `pveversion`, `/api/tags`.
Nothing here restarts a pod, reboots a node, or changes configuration. That's
a deliberate scope limit, not a limitation of the format — the `safe: false`
+ `confirm` mechanism above exists precisely so a future mutating skill (say,
`talosctl restart <service>`) can be added without weakening what's already
here. Treat adding a `safe: false` skill as something to design deliberately
(what confirms it, who can trigger it, what it logs), not a checkbox.

## Adding a skill

1. Copy the closest existing file in `backend/skills/catalog/`.
2. Change `name`, `description`, `agents`, and the command/params.
3. Restart the backend (`loader.py` reads the catalog at process start).
4. It shows up as a tool on every agent listed in `agents:` — no other file
   needs to change.

See [backend/skills/catalog/](backend/skills/catalog/) for the full shipped
set, grouped by agent in the table below.

## Shipped catalog

| Skill | Agent | Target | What it shows |
| --- | --- | --- | --- |
| `talos-service-status` | talos | local | `talosctl service` — per-service state on a node |
| `talos-health` | talos | local | `talosctl health` — cluster-wide health gate |
| `talos-dmesg` | talos | local | `talosctl dmesg` — kernel ring buffer on a node |
| `talos-members` | talos | local | `talosctl get members` — cluster membership/discovery |
| `k8s-get-nodes` | talos | kubectl | `kubectl get nodes -o wide` |
| `k8s-get-pods` | talos, ollama | kubectl | `kubectl get pods` in a namespace (or `-A`) |
| `k8s-describe-pod` | talos, ollama | kubectl | `kubectl describe pod` |
| `k8s-pod-logs` | talos, ollama | kubectl | Tail a pod's logs, by name or label selector |
| `k8s-events` | talos | kubectl | `kubectl get events --sort-by=.lastTimestamp -A` |
| `k8s-top-nodes` | talos | kubectl | `kubectl top nodes` (needs metrics-server) |
| `k8s-top-pods` | talos, ollama | kubectl | `kubectl top pods` in a namespace (or `-A`) |
| `ollama-api-tags` | ollama | http | `GET /api/tags` — models the server actually has pulled |
| `ollama-api-ps` | ollama | http | `GET /api/ps` — models currently resident in memory/VRAM |
| `ollama-api-version` | ollama | http | `GET /api/version` |
| `ollama-helm-status` | ollama | local | `helm status ollama -n ollama` |
| `nvidia-smi` | nvidia | kubectl | `nvidia-smi` executed inside the GPU-scheduled pod |
| `nvidia-device-plugin-logs` | nvidia | kubectl | Logs of the `nvidia-device-plugin` DaemonSet pod |
| `nvidia-dmesg` | nvidia | local | `talosctl dmesg` on the GPU node (search for `NVRM`/`Xid`) |
| `nvidia-pci-devices` | nvidia | local | `talosctl get pciDevices` on the GPU node |
| `proxmox-pve-version` | proxmox | ssh | `pveversion -v` |
| `proxmox-node-status` | proxmox | ssh | `pvesh get /nodes/<node>/status` (load, uptime, memory) |
| `proxmox-vm-list` | proxmox | ssh | `qm list` — VM inventory and running/stopped state |
| `proxmox-journal` | proxmox | ssh | `journalctl -u <unit> -n <lines> --no-pager` |
| `proxmox-disk-usage` | proxmox | ssh | `df -h` |
| `proxmox-systemd-failed` | proxmox | ssh | `systemctl --failed` |
| `proxmox-dmesg` | proxmox | ssh | `dmesg --ctime` |

See [AGENTS.md](AGENTS.md) for how these skills get bundled into an agent.
