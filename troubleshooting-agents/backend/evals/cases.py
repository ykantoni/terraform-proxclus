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
        },
        expected_tools=["k8s-events"],
        expected_facts=["memory"],
        notes="No specific pod/namespace given — must reach for the cluster-wide events tool first.",
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
        },
        expected_tools=["nvidia-dmesg"],
        expected_facts=["Xid", "79"],
        notes="Xid 79 is a specific, well-known code (GPU fell off the bus) — must be named, not paraphrased away.",
    ),
    Case(
        id="nvidia-04-pci-missing",
        agent_id="nvidia",
        question="nvidia-pci-devices shows nothing — is the card even there?",
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
        },
        expected_tools=["proxmox-dmesg"],
        expected_facts=["-16"],
        notes="Mirrors nvidia-04 from the other side of the handoff — the actual VFIO error code must be surfaced.",
    ),
]
