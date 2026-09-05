"""
All environment-derived settings in one place. Everything here has a
default that matches this repo's own cluster (see ../../README.md), so the
backend runs unconfigured for local development against that cluster and
only needs a .env for anything that differs (a different Proxmox host, a
different Ollama model already pulled, etc).
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

# Repo root two levels up from this file (backend/config.py -> troubleshooting-agents/ -> repo root).
REPO_ROOT = Path(__file__).resolve().parents[2]

# Load troubleshooting-agents/.env (if present) without overriding variables
# already set in the real environment.
load_dotenv(Path(__file__).resolve().parents[1] / ".env", override=False)


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


@dataclass(frozen=True)
class SSHConnection:
    host: str
    user: str = "root"
    port: int = 22
    identity_file: str | None = None


@dataclass(frozen=True)
class Settings:
    # --- LLM (also the thing the "ollama" agent troubleshoots) ---
    ollama_base_url: str = field(default_factory=lambda: _env("OLLAMA_BASE_URL", "http://192.168.1.63:11434"))
    ollama_model: str = field(default_factory=lambda: _env("OLLAMA_MODEL", "gemma4:26b"))
    ollama_temperature: float = field(default_factory=lambda: float(_env("OLLAMA_TEMPERATURE", "0")))
    # Measured against this repo's own server: a trivial 2-token reply from
    # gemma4:26b took ~58s (prompt eval alone was ~19s) — a tool-calling turn
    # is at least one more round trip on top of that, so the client-side
    # HTTP timeout needs real headroom, not the ollama client's ~1min default.
    ollama_request_timeout: int = field(default_factory=lambda: int(_env("OLLAMA_REQUEST_TIMEOUT", "300")))
    # How long Ollama keeps the model loaded after the last request, so a
    # multi-turn troubleshooting conversation doesn't eat the ~20s prompt-eval
    # cold-start cost between every turn.
    ollama_keep_alive: str = field(default_factory=lambda: _env("OLLAMA_KEEP_ALIVE", "30m"))

    # --- Talos / Kubernetes ---
    talos_vip: str = field(default_factory=lambda: _env("TALOS_VIP", "192.168.1.99"))
    # Node that carries the GPU (see ../../README.md "GPU" section); used as
    # the default target for nvidia-* skills.
    gpu_node: str = field(default_factory=lambda: _env("GPU_NODE", "192.168.1.201"))
    kubeconfig: str = field(
        default_factory=lambda: _env("KUBECONFIG_PATH", str(REPO_ROOT / ".kube" / "config"))
    )

    # --- Proxmox (SSH) ---
    proxmox_host: str = field(default_factory=lambda: _env("PROXMOX_HOST", "192.168.1.100"))
    proxmox_user: str = field(default_factory=lambda: _env("PROXMOX_USER", "root"))
    proxmox_port: int = field(default_factory=lambda: int(_env("PROXMOX_SSH_PORT", "22")))
    proxmox_identity_file: str | None = field(default_factory=lambda: os.environ.get("PROXMOX_SSH_KEY") or None)

    # --- Server ---
    host: str = field(default_factory=lambda: _env("BACKEND_HOST", "0.0.0.0"))
    port: int = field(default_factory=lambda: int(_env("BACKEND_PORT", "8000")))
    # "*" by default: this API carries no auth/cookies (allow_credentials is
    # off in server.py) and the GUI gets opened from whatever host/IP is
    # convenient on the LAN, not just localhost:5173 — restricting this to
    # one origin just breaks that with a CORS error. Set an explicit
    # comma-separated list here to lock it down instead.
    cors_origins: list[str] = field(default_factory=lambda: _env("CORS_ORIGINS", "*").split(","))

    @property
    def connections(self) -> dict[str, SSHConnection]:
        """Named SSH connection profiles, referenced by skills via `connection: <name>`."""
        return {
            "proxmox": SSHConnection(
                host=self.proxmox_host,
                user=self.proxmox_user,
                port=self.proxmox_port,
                identity_file=self.proxmox_identity_file,
            ),
        }

    @property
    def template_vars(self) -> dict[str, str]:
        """Values substitutable in skill frontmatter as "${VAR}" at catalog-load time."""
        return {
            "TALOS_VIP": self.talos_vip,
            "GPU_NODE": self.gpu_node,
            "OLLAMA_BASE_URL": self.ollama_base_url,
            "PROXMOX_HOST": self.proxmox_host,
            "KUBECONFIG": self.kubeconfig,
        }


settings = Settings()
