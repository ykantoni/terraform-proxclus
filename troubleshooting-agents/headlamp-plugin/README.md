# Cluster Chat (Headlamp plugin)

Read-only chatbot inside Headlamp Desktop. The plugin gathers a small live
Kubernetes snapshot (nodes, unhealthy pods, warning events, optional current
resource) through Headlamp’s authenticated client, then asks `gemma4:26b` on
the LAN Ollama (`http://192.168.1.63:11434`) to write the answer.

It cannot run `talosctl`, SSH, or mutate the cluster. OS / GPU-driver /
Proxmox questions belong in the standalone [troubleshooting-agents](../README.md)
GUI.

## Develop

Headlamp Desktop must already be installed and connected to this cluster’s
kubeconfig (the repo’s `.kube/config`).

```bash
cd troubleshooting-agents/headlamp-plugin
npm install
npm start
```

`npm start` writes into Headlamp’s **dev-plugins** directory. Leave
`%APPDATA%\Headlamp\Config\plugins` empty during development so a stale
packaged copy does not win.

Open Headlamp → sidebar **Cluster Chat**, or the chat icon in the app bar.
Resource details for Pod / Node / Deployment / DaemonSet / StatefulSet /
ReplicaSet get an **Ask about this** section that prefills `?kind=&name=&namespace=`.

## Settings

Plugin Settings (or defaults):

- Base URL `http://192.168.1.63:11434`
- Model `gemma4:26b`
- Timeout `300` seconds, `keep_alive` `30m`
- Transport `auto` — LAN first, kube service proxy
  (`/api/v1/namespaces/ollama/services/http:ollama:11434/proxy/...`) if the
  browser cannot reach Ollama

A LAN probe on 2026-09-06 showed this cluster’s Ollama reflecting `Origin`
(`Access-Control-Allow-Origin`) on `/api/version` and `/api/ps`, so **direct**
should work from Headlamp Desktop on the same LAN.

## Tests

```bash
npm test
node scripts/manual-scenarios.mjs   # live kubectl + one Ollama call per scenario
```

Manual scenarios: healthy cluster, injected CrashLoop/OOMKilled pod, and the
`ext-nvidia-persistenced` known quirk. Answers must cite snapshot facts and
must not suggest `ssh` or `talosctl`. If `kubectl` cannot reach the cluster
(wrong `KUBECONFIG`), the script falls back to a four-node Ready fixture and
still calls the live model.

## Package for this machine

```bash
npm run build
npm run package
# extract the tarball into %APPDATA%\Headlamp\Config\plugins\
```
