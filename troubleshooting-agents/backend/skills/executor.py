"""Runs one skill invocation. Every path here ends in either a subprocess
call with argv passed as a list (never `shell=True`) or a `requests` call —
no user-controlled string is ever concatenated into a shell command.
"""
from __future__ import annotations

import shlex
import subprocess
from dataclasses import dataclass

import requests

from config import SSHConnection, settings

MAX_OUTPUT_CHARS = 4000  # keeps one tool result from blowing the model's context window


@dataclass
class ExecResult:
    ok: bool
    output: str

    def formatted(self) -> str:
        text = self.output.strip() or "(empty output)"
        if len(text) > MAX_OUTPUT_CHARS:
            # Keep the tail, not the head: for logs/dmesg/journal output the
            # most recent lines are almost always the relevant ones.
            text = f"[... truncated, {len(self.output)} chars total] ...\n" + text[-MAX_OUTPUT_CHARS:]
        prefix = "" if self.ok else "[command failed] "
        return prefix + text


def _run(argv: list[str], timeout: int) -> ExecResult:
    try:
        proc = subprocess.run(
            argv,
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        return ExecResult(ok=False, output=f"{exc}\nIs `{argv[0]}` installed and on PATH for this backend process?")
    except subprocess.TimeoutExpired:
        return ExecResult(ok=False, output=f"Timed out after {timeout}s running: {' '.join(argv)}")

    combined = proc.stdout
    if proc.stderr:
        combined = (combined + "\n" + proc.stderr) if combined else proc.stderr
    return ExecResult(ok=proc.returncode == 0, output=combined)


def run_local(command: list[str], timeout: int) -> ExecResult:
    return _run(command, timeout)


def run_ssh(connection: SSHConnection, command: list[str], timeout: int) -> ExecResult:
    # OpenSSH re-joins argv into one string and hands it to the remote
    # shell, so each token is quoted here to keep a parameter value from
    # being reinterpreted as additional remote commands.
    remote_cmd = " ".join(shlex.quote(tok) for tok in command)
    ssh_argv = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=accept-new",
        "-p", str(connection.port),
    ]
    if connection.identity_file:
        ssh_argv += ["-i", connection.identity_file]
    ssh_argv += [f"{connection.user}@{connection.host}", remote_cmd]
    return _run(ssh_argv, timeout)


def _resolve_pod(namespace: str, pod: str | None, selector: str | None, timeout: int) -> tuple[str | None, ExecResult | None]:
    if pod:
        return pod, None
    if not selector:
        return None, ExecResult(ok=False, output="Skill misconfigured: neither `pod` nor `selector` given.")
    result = _run(
        ["kubectl", "--kubeconfig", settings.kubeconfig, "get", "pods", "-n", namespace,
         "-l", selector, "-o", "jsonpath={.items[0].metadata.name}"],
        timeout,
    )
    if not result.ok or not result.output.strip():
        return None, ExecResult(ok=False, output=f"No pod found in namespace '{namespace}' matching selector '{selector}'.\n{result.output}")
    return result.output.strip(), None


def run_kubectl(
    *,
    mode: str,
    namespace: str | None = None,
    pod: str | None = None,
    selector: str | None = None,
    container: str | None = None,
    command: list[str] | None = None,
    resource: str | None = None,
    resource_name: str | None = None,
    extra_args: list[str] | None = None,
    tail: int | None = None,
    timeout: int = 30,
) -> ExecResult:
    base = ["kubectl", "--kubeconfig", settings.kubeconfig]

    if mode in ("exec", "logs"):
        ns = namespace or "default"
        resolved_pod, err = _resolve_pod(ns, pod, selector, timeout)
        if err:
            return err
        if mode == "exec":
            argv = base + ["exec", "-n", ns, resolved_pod]
            if container:
                argv += ["-c", container]
            argv += ["--"] + (command or [])
        else:  # logs
            argv = base + ["logs", "-n", ns, resolved_pod, "--tail", str(tail or 200)]
            if container:
                argv += ["-c", container]
        return _run(argv, timeout)

    if mode in ("get", "describe", "top"):
        argv = base + [mode, resource or "pods"]
        if namespace == "*":
            argv += ["-A"]
        elif namespace:
            argv += ["-n", namespace]
        if resource_name:
            argv.append(resource_name)
        if extra_args:
            argv += extra_args
        return _run(argv, timeout)

    return ExecResult(ok=False, output=f"Skill misconfigured: unknown kubectl mode '{mode}'.")


def run_http(*, method: str, url: str, timeout: int, json_body: dict | None = None) -> ExecResult:
    try:
        resp = requests.request(method=method, url=url, json=json_body, timeout=timeout)
    except requests.RequestException as exc:
        return ExecResult(ok=False, output=f"HTTP request failed: {exc}")
    return ExecResult(ok=resp.ok, output=f"HTTP {resp.status_code}\n{resp.text}")
