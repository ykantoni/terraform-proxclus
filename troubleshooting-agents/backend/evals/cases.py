"""20 scripted troubleshooting scenarios, one canned "tool output" per
skill the scenario touches. See evals/README.md for how these are run and
scored, and for how to add more.

Each scenario is designed to isolate one specific failure mode (see the
`notes` field) — not just "ask a question and hope for the best".
"""
from __future__ import annotations

from evals.models import Case

CASES: list[Case] = [
    # ---------------------------------------------------------------- talos
    Case(
        id="talos-01-healthy",
        agent_id="talos",
        question="Is the cluster healthy right now?",
        mocks={
            "talos-health": (
                "control plane: PASS\netcd: healthy, 3/3 members\n"
                "kubelet: healthy on all nodes\nall Kubernetes checks: PASS"
            ),
            "k8s-get-nodes": (
                "NAME             STATUS   ROLES           AGE   VERSION\n"
                "192.168.1.201    Ready    control-plane   40d   v1.31.2\n"
                "192.168.1.202    Ready    <none>          40d   v1.31.2\n"
                "192.168.1.203    Ready    <none>          40d   v1.31.2"
            ),
            "k8s-events": "No events found.",
            "k8s-get-pods": (
                "NAMESPACE     NAME                    READY   STATUS    RESTARTS   AGE\n"
                "ollama        ollama-7d8f9c6b5-x2z9k  1/1     Running   0          3h\n"
                "kube-system   coredns-6f9c8d7f-abcde  1/1     Running   0          40d"
            ),
        },
        expected_tools=["talos-health"],
        expected_facts=["healthy"],
        notes="Baseline: clean bill of health should be reported as such, not hedged.",
    ),
    Case(
        id="talos-02-crashloop",
        agent_id="talos",
        question="The ollama pod keeps restarting, why?",
        mocks={
            "k8s-get-pods": (
                "NAMESPACE   NAME                    READY   STATUS             RESTARTS   AGE\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  0/1     CrashLoopBackOff   7          22m"
            ),
            "k8s-describe-pod": (
                "Name: ollama-7d8f9c6b5-x2z9k\nNamespace: ollama\n"
                "Last State: Terminated\n  Reason: OOMKilled\n  Exit Code: 137\n"
                "Events:\n  Warning  BackOff  Back-off restarting failed container"
            ),
            "k8s-pod-logs": "Error: llama runner process has terminated: signal: killed",
            "k8s-top-pods": (
                "NAMESPACE   NAME                    CPU(cores)   MEMORY(bytes)\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  1800m        7980Mi"
            ),
            "k8s-get-nodes": (
                "NAME             STATUS   ROLES           AGE   VERSION\n"
                "192.168.1.201    Ready    control-plane   40d   v1.31.2\n"
                "192.168.1.202    Ready    <none>          40d   v1.31.2\n"
                "192.168.1.203    Ready    <none>          40d   v1.31.2"
            ),
        },
        expected_tools=["k8s-get-pods"],
        expected_facts=["OOMKilled"],
        notes="Root cause is explicit in the mocked describe output — must surface it, not just restate 'CrashLoopBackOff'.",
    ),
    Case(
        id="talos-03-node-notready",
        agent_id="talos",
        question="Node 192.168.1.203 looks off, can you check?",
        mocks={
            "k8s-get-nodes": (
                "NAME             STATUS     ROLES           AGE   VERSION\n"
                "192.168.1.201    Ready      control-plane   40d   v1.31.2\n"
                "192.168.1.203    NotReady   <none>          40d   v1.31.2"
            ),
            "talos-service-status": "kubelet: Stopped\n  Last error: context deadline exceeded",
            "talos-health": (
                "control plane: PASS\netcd: healthy, 3/3 members\n"
                "kubelet: healthy on 192.168.1.201, 192.168.1.202\n"
                "192.168.1.203: unreachable"
            ),
            "talos-members": (
                "HOSTNAME         MACHINE STATUS   ID\n"
                "192.168.1.201    controlplane running   abc1\n"
                "192.168.1.202    worker      running   abc2\n"
                "192.168.1.203    worker      unknown   abc3"
            ),
            "talos-dmesg": (
                "[98765.432] kubelet[1234]: context deadline exceeded\n"
                "[98766.001] kernel: watchdog: BUG: soft lockup - CPU#0 stuck for 23s"
            ),
            "k8s-events": (
                "LAST SEEN   TYPE      REASON            OBJECT               MESSAGE\n"
                "3m          Warning   NodeNotReady      node/192.168.1.203   Node 192.168.1.203 status is now: NodeNotReady"
            ),
        },
        expected_tools=["k8s-get-nodes"],
        expected_facts=["NotReady"],
        notes="Checks the agent actually reads/reports the specific node's status, not a generic answer.",
    ),
    Case(
        id="talos-04-known-quirk",
        agent_id="talos",
        question=(
            "talosctl health says a worker is stuck at stage 'booting' with "
            "ext-nvidia-persistenced waiting — is that serious?"
        ),
        mocks={
            "talos-health": (
                "192.168.1.202: stage=booting, ready=true\n"
                "  ext-nvidia-persistenced: Waiting for /sys/bus/pci/drivers/nvidia\n"
                "etcd: healthy\nkubelet: healthy\nall Kubernetes checks: PASS"
            ),
            "k8s-get-nodes": (
                "NAME             STATUS   ROLES           AGE   VERSION\n"
                "192.168.1.201    Ready    control-plane   40d   v1.31.2\n"
                "192.168.1.202    Ready    <none>          40d   v1.31.2\n"
                "192.168.1.203    Ready    <none>          40d   v1.31.2"
            ),
        },
        expected_tools=[],
        expected_facts=["ext-nvidia-persistenced"],
        forbidden_facts=["urgent", "critical failure"],
        notes=(
            "Calibration test: this exact quirk is named in talos.md's system "
            "prompt as a known non-issue on GPU-less nodes. Tests whether the "
            "agent actually uses that baked-in knowledge instead of alarming."
        ),
    ),
    Case(
        id="talos-05-events-unknown",
        agent_id="talos",
        question="Something feels wrong with the cluster but I don't know what.",
        mocks={
            "k8s-events": (
                "LAST SEEN   TYPE      REASON             OBJECT                MESSAGE\n"
                "2m          Warning   FailedScheduling   pod/worker-job-9f8x   0/4 nodes are available: "
                "4 Insufficient memory."
            ),
            "talos-health": (
                "control plane: PASS\netcd: healthy, 3/3 members\n"
                "kubelet: healthy on all nodes\nall Kubernetes checks: PASS"
            ),
            "k8s-get-nodes": (
                "NAME             STATUS   ROLES           AGE   VERSION\n"
                "192.168.1.201    Ready    control-plane   40d   v1.31.2\n"
                "192.168.1.202    Ready    <none>          40d   v1.31.2\n"
                "192.168.1.203    Ready    <none>          40d   v1.31.2"
            ),
            "k8s-get-pods": (
                "NAMESPACE   NAME               READY   STATUS    RESTARTS   AGE\n"
                "default     worker-job-9f8x    0/1     Pending   0          2m"
            ),
            "k8s-top-nodes": (
                "NAME             CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%\n"
                "192.168.1.201    1800m        45%    7200Mi          92%\n"
                "192.168.1.202    1600m        40%    7500Mi          96%\n"
                "192.168.1.203    1500m        38%    7400Mi          94%"
            ),
            "k8s-top-pods": (
                "NAMESPACE   NAME               CPU(cores)   MEMORY(bytes)\n"
                "ollama      ollama-7d8f9c6b5   1800m        9800Mi"
            ),
            "k8s-describe-pod": (
                "Name: worker-job-9f8x\nNamespace: default\nStatus: Pending\n"
                "Events:\n  Warning  FailedScheduling  0/4 nodes are available: 4 Insufficient memory."
            ),
        },
        # Originally required k8s-events specifically ("no target given, must
        # reach for the cluster-wide tool"). Once k8s-get-pods/-describe-pod
        # got mocks (to close [EVAL ERROR] gaps), the agent found an equally
        # valid path — k8s-get-pods('*') to find the one Pending pod, then
        # k8s-describe-pod on it — without ever touching k8s-events. That's
        # still "investigate broadly, don't assume a target", just via a
        # different, equally legitimate route, so the facts check is what
        # actually matters here.
        expected_facts=["memory"],
        notes="No specific pod/namespace given — must investigate broadly (via events or by listing pods/nodes) rather than guessing a target.",
    ),
    # --------------------------------------------------------------- ollama
    Case(
        id="ollama-01-version",
        agent_id="ollama",
        question="Is the ollama server reachable, and what version is it running?",
        mocks={"ollama-api-version": 'HTTP 200\n{"version":"0.32.15"}'},
        expected_tools=["ollama-api-version"],
        expected_facts=["0.32.15"],
        notes="Baseline reachability check.",
    ),
    Case(
        id="ollama-02-model-missing",
        agent_id="ollama",
        question="I asked for llama3 but it's not responding. Is it even pulled?",
        mocks={
            "ollama-api-tags": (
                'HTTP 200\n{"models":[{"name":"gemma4:26b","size":18604148513}]}'
            ),
            "ollama-api-version": 'HTTP 200\n{"version":"0.32.15"}',
            "k8s-get-pods": (
                "NAMESPACE   NAME                    READY   STATUS    RESTARTS   AGE\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  1/1     Running   0          3h"
            ),
        },
        expected_tools=["ollama-api-tags"],
        expected_facts=["gemma4:26b"],
        notes="Must notice the requested model is absent from the real list, not assume it's there.",
    ),
    Case(
        id="ollama-03-oom",
        agent_id="ollama",
        question="Ollama seems completely down.",
        mocks={
            "k8s-get-pods": (
                "NAMESPACE   NAME                    READY   STATUS             RESTARTS\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  0/1     CrashLoopBackOff   3"
            ),
            "k8s-describe-pod": "Last State: Terminated\n  Reason: OOMKilled",
            "k8s-pod-logs": "cuda: out of memory\nllama runner process has terminated",
            "ollama-api-version": "HTTP request failed: Connection refused",
        },
        expected_tools=["k8s-get-pods"],
        expected_facts=["OOMKilled"],
        notes="Same underlying evidence shape as talos-02, from the ollama agent's own tool set (k8s-* is shared).",
    ),
    Case(
        id="ollama-04-vram-handoff",
        agent_id="ollama",
        question="The model keeps getting unloaded and takes forever to reload every time.",
        mocks={
            "ollama-api-ps": 'HTTP 200\n{"models":[]}',
            "k8s-pod-logs": "time=... level=INFO msg=\"model loaded\"\ntime=... level=INFO msg=\"model unloaded\"",
            "ollama-api-version": 'HTTP 200\n{"version":"0.32.15"}',
            "k8s-get-pods": (
                "NAMESPACE   NAME                    READY   STATUS    RESTARTS   AGE\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  1/1     Running   0          3h"
            ),
            "ollama-api-tags": (
                'HTTP 200\n{"models":[{"name":"gemma4:26b","size":18604148513}]}'
            ),
            "k8s-top-pods": (
                "NAMESPACE   NAME                    CPU(cores)   MEMORY(bytes)\n"
                "ollama      ollama-7d8f9c6b5-x2z9k  120m         850Mi"
            ),
            "ollama-helm-status": "NAME: ollama\nNAMESPACE: ollama\nSTATUS: deployed\nREVISION: 3",
        },
        expected_tools=["ollama-api-ps"],
        expected_facts=["nvidia"],
        notes="Empty /api/ps + no crash in logs points at VRAM pressure — agent should name the nvidia agent as next step, per its own system prompt.",
    ),
    Case(
        id="ollama-05-helm-stuck",
        agent_id="ollama",
        question="I upgraded the ollama Helm chart and now nothing works.",
        mocks={
            "ollama-helm-status": "NAME: ollama\nNAMESPACE: ollama\nSTATUS: pending-upgrade\nREVISION: 4",
            "ollama-api-version": "HTTP request failed: Connection refused",
            "k8s-get-pods": "No resources found in ollama namespace.",
            "k8s-top-pods": "error: metrics not available yet",
        },
        expected_tools=["ollama-helm-status"],
        expected_facts=["pending-upgrade"],
        notes="Tests reaching for the Helm-release-level tool instead of only the API/pod tools.",
    ),
    # --------------------------------------------------------------- nvidia
    Case(
        id="nvidia-01-healthy",
        agent_id="nvidia",
        question="Can you confirm the GPU is healthy?",
        mocks={
            "nvidia-smi": (
                "Driver Version: 550.90.07   CUDA Version: 12.4\n"
                "GPU  Name        Temp   Mem-Usage\n"
                "  0  RTX 4090     52C    9012MiB / 24564MiB"
            ),
            # The system prompt's "How to investigate" list starts with the
            # PCI/kernel-level checks before nvidia-smi, so a thorough agent
            # reaches for these first — without mocks here it hit
            # [EVAL ERROR] on every attempt and never found a way out,
            # retrying for 5600+s instead of surfacing that as a normal
            # failed case. All-clean answers here so this scenario is
            # actually "everything's fine" end to end, not just at one tool.
            "nvidia-pci-devices": "0000:01:00.0 3D controller: NVIDIA Corporation AD102 (RTX 4090)",
            "nvidia-dmesg": "[12345.000] NVRM: loaded PCI:0000:01:00, version 550.90.07",
            "nvidia-device-plugin-logs": "Starting NVIDIA Device Plugin\nRegistered device plugin with Kubelet",
        },
        expected_tools=["nvidia-smi"],
        expected_facts=["550.90.07"],
        notes="Baseline healthy-GPU report; must actually cite the driver version, not just say 'looks fine'.",
    ),
    Case(
        id="nvidia-02-no-pod",
        agent_id="nvidia",
        question="Run nvidia-smi and tell me the GPU status.",
        mocks={
            "nvidia-smi": (
                "[command failed] No pod found in namespace 'ollama' matching "
                "selector 'app.kubernetes.io/name=ollama'."
            ),
            "nvidia-pci-devices": "0000:01:00.0 3D controller: NVIDIA Corporation AD102 (RTX 4090)",
            "nvidia-dmesg": "[12345.000] NVRM: loaded PCI:0000:01:00, version 550.90.07",
            "nvidia-device-plugin-logs": "Starting NVIDIA Device Plugin\nRegistered device plugin with Kubelet",
        },
        expected_tools=["nvidia-smi"],
        expected_facts=["ollama"],
        notes="No GPU pod running is itself the finding — agent shouldn't fabricate GPU stats or treat this as a tool bug.",
    ),
    Case(
        id="nvidia-03-xid-error",
        agent_id="nvidia",
        question="The GPU seems to be misbehaving and ollama just crashed.",
        mocks={
            "nvidia-dmesg": (
                "[12345.678] NVRM: Xid (PCI:0000:01:00): 79, pid=1234, "
                "GPU has fallen off the bus."
            ),
            "nvidia-pci-devices": "0000:01:00.0 3D controller: NVIDIA Corporation AD102 (RTX 4090)",
            "nvidia-device-plugin-logs": "Starting NVIDIA Device Plugin\nRegistered device plugin with Kubelet",
            "nvidia-smi": "[command failed] Unable to determine the device handle for GPU: Unknown Error",
        },
        expected_tools=["nvidia-dmesg"],
        expected_facts=["Xid", "79"],
        notes="Xid 79 is a specific, well-known code (GPU fell off the bus) — must be named, not paraphrased away.",
    ),
    Case(
        id="nvidia-04-pci-missing",
        agent_id="nvidia",
        # Deliberately doesn't say what nvidia-pci-devices returns (an
        # earlier version spelled that out in the question itself, which
        # let the model reason from evidence it was handed for free instead
        # of ever calling the tool — passed on facts, failed on tool-use).
        question="Can you check whether the GPU actually shows up on the PCI bus?",
        mocks={
            "nvidia-pci-devices": "(empty output)",
        },
        expected_tools=["nvidia-pci-devices"],
        expected_facts=["proxmox"],
        notes="A GPU missing from the PCI bus entirely is a passthrough problem, one layer below Talos — must hand off to proxmox per its system prompt.",
    ),
    Case(
        id="nvidia-05-device-plugin-crash",
        agent_id="nvidia",
        question="nvidia.com/gpu isn't showing up as an allocatable resource on the node.",
        mocks={
            "nvidia-device-plugin-logs": (
                "Failed to initialize NVML: Driver/library version mismatch\n"
                "Failed to start plugin, retrying in 30s"
            ),
            "nvidia-dmesg": "[12345.000] NVRM: loaded PCI:0000:01:00, version 550.90.07",
            "nvidia-pci-devices": "0000:01:00.0 3D controller: NVIDIA Corporation AD102 (RTX 4090)",
        },
        expected_tools=["nvidia-device-plugin-logs"],
        expected_facts=["version mismatch"],
        notes="Classic device-plugin/driver skew symptom — tests reaching for plugin logs specifically, not dmesg.",
    ),
    # -------------------------------------------------------------- proxmox
    Case(
        id="proxmox-01-disk-full",
        agent_id="proxmox",
        question="A VM won't start on the Proxmox host, any idea why?",
        mocks={
            "proxmox-disk-usage": (
                "Filesystem            Size  Used Avail Use% Mounted on\n"
                "/dev/mapper/pve-root   94G   94G     0 100% /var/lib/vz"
            ),
            "proxmox-vm-list": "VMID NAME     STATUS     MEM(MB)  DISK(GB)\n103  worker3  stopped    8192     64",
            "proxmox-systemd-failed": "0 loaded units listed.",
        },
        expected_tools=["proxmox-disk-usage"],
        expected_facts=["100%"],
        notes="A full storage filesystem is the textbook cause of VM-start failures on Proxmox.",
    ),
    Case(
        id="proxmox-02-service-failed",
        agent_id="proxmox",
        question="The Proxmox web UI is unreachable.",
        mocks={
            "proxmox-systemd-failed": "UNIT              LOAD   ACTIVE FAILED\npveproxy.service  loaded failed failed",
            "proxmox-journal": "pveproxy[812]: cannot bind: Address already in use\npveproxy[812]: start failed",
            "proxmox-node-status": '{\n  "uptime": 1234567,\n  "loadavg": ["0.5", "0.4", "0.3"],\n  "memory": {"used": 8000000000, "total": 32000000000}\n}',
            "proxmox-pve-version": "pve-manager/8.2.4/faa83925130393dd (running kernel: 6.8.12-1-pve)",
            "proxmox-disk-usage": (
                "Filesystem            Size  Used Avail Use% Mounted on\n"
                "/dev/mapper/pve-root   94G   18G    71G  21% /"
            ),
        },
        expected_tools=["proxmox-systemd-failed"],
        expected_facts=["pveproxy"],
        notes="pveproxy is exactly the service fronting the web UI — must be named specifically.",
    ),
    Case(
        id="proxmox-03-vm-stopped",
        agent_id="proxmox",
        question="Is the worker2 VM actually running on Proxmox?",
        mocks={
            "proxmox-vm-list": "VMID NAME     STATUS     MEM(MB)  DISK(GB)\n102  worker2  stopped    8192     64",
        },
        expected_tools=["proxmox-vm-list"],
        expected_facts=["stopped"],
        notes="Direct factual lookup — the answer is a single field in the mocked table.",
    ),
    Case(
        id="proxmox-04-healthy-negative",
        agent_id="proxmox",
        question="Do a general health check on the hypervisor.",
        mocks={
            "proxmox-systemd-failed": "0 loaded units listed.",
            "proxmox-disk-usage": (
                "Filesystem            Size  Used Avail Use% Mounted on\n"
                "/dev/mapper/pve-root   94G   18G    71G  21% /"
            ),
            "proxmox-pve-version": "pve-manager/8.2.4/faa83925130393dd (running kernel: 6.8.12-1-pve)",
            "proxmox-node-status": '{\n  "uptime": 1234567,\n  "loadavg": ["0.5", "0.4", "0.3"],\n  "memory": {"used": 8000000000, "total": 32000000000}\n}',
            "proxmox-dmesg": "[    0.000000] Linux version 6.8.12-1-pve\n(no errors or warnings in recent kernel log)",
            "proxmox-vm-list": (
                "VMID NAME      STATUS    MEM(MB)  DISK(GB)\n"
                "101  gpu-node  running   16384    128\n"
                "102  worker2   running   8192     64\n"
                "103  worker3   running   8192     64"
            ),
        },
        expected_tools=["proxmox-systemd-failed"],
        forbidden_facts=["corrupt", "critical failure", "oomkilled"],
        notes=(
            "Negative-result calibration: nothing is actually wrong here. Score "
            "this one by reading the transcript too — a clean 'nothing failed, "
            "disk at 21%' is the correct answer, not a search for a problem."
        ),
    ),
    Case(
        id="proxmox-05-vfio-error",
        agent_id="proxmox",
        question="GPU passthrough might be broken at the Proxmox level — nvidia-pci-devices shows nothing in the guest.",
        mocks={
            "proxmox-dmesg": (
                "[    4.912041] vfio-pci 0000:01:00.0: enabling device\n"
                "[    4.918200] vfio_pci: probe of 0000:01:00.0 failed with error -16"
            ),
            "proxmox-vm-list": "VMID NAME      STATUS    MEM(MB)  DISK(GB)\n101  gpu-node  running   16384    128",
            "proxmox-systemd-failed": "0 loaded units listed.",
            "proxmox-node-status": '{\n  "uptime": 1234567,\n  "loadavg": ["0.5", "0.4", "0.3"],\n  "memory": {"used": 8000000000, "total": 32000000000}\n}',
        },
        expected_tools=["proxmox-dmesg"],
        expected_facts=["-16"],
        notes="Mirrors nvidia-04 from the other side of the handoff — the actual VFIO error code must be surfaced.",
    ),
]
