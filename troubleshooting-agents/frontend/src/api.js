// Defaults to the backend on the same host the page was loaded from
// (localhost, a LAN IP, whatever) rather than hardcoding "localhost" — that
// hardcoding is what breaks the GUI as soon as it's opened via a LAN address
// instead of localhost:5173. Override with VITE_API_BASE when the backend
// really is on a different host than the frontend.
const API_BASE = import.meta.env.VITE_API_BASE || `${window.location.protocol}//${window.location.hostname}:8000`;

export async function fetchAgents() {
  const res = await fetch(`${API_BASE}/api/agents`);
  if (!res.ok) throw new Error(`Failed to load agents (${res.status})`);
  return res.json();
}

/**
 * POSTs a chat turn and calls onEvent(event) for each newline-delimited
 * JSON event the backend streams back (see backend/server.py: route,
 * tool_call, tool_result, message, error, done).
 */
export async function streamChat({ message, agentId, threadId }, onEvent) {
  const res = await fetch(`${API_BASE}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, agent_id: agentId, thread_id: threadId }),
  });
  if (!res.ok || !res.body) {
    throw new Error(`Chat request failed (${res.status})`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  const consume = (line) => {
    const trimmed = line.trim();
    if (trimmed) onEvent(JSON.parse(trimmed));
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    lines.forEach(consume);
  }
  if (buffer) consume(buffer);
}
