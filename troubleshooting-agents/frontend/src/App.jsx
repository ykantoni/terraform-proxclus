import { useEffect, useRef, useState } from "react";
import AgentSelector from "./components/AgentSelector.jsx";
import MessageBubble from "./components/MessageBubble.jsx";
import { fetchAgents, streamChat } from "./api.js";
import { uid } from "./uid.js";

const THREAD_ID = uid();

export default function App() {
  const [agents, setAgents] = useState([]);
  const [agentId, setAgentId] = useState("auto");
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [loadError, setLoadError] = useState(null);
  const bottomRef = useRef(null);

  useEffect(() => {
    fetchAgents()
      .then(setAgents)
      .catch((e) => setLoadError(e.message));
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const send = async () => {
    const text = input.trim();
    if (!text || busy) return;

    const userMsg = { id: uid(), role: "user", content: text };
    const assistantId = uid();
    const assistantMsg = { id: assistantId, role: "assistant", content: "", trace: [], pending: true };

    setMessages((prev) => [...prev, userMsg, assistantMsg]);
    setInput("");
    setBusy(true);

    const patch = (fn) =>
      setMessages((prev) => prev.map((m) => (m.id === assistantId ? fn(m) : m)));

    try {
      await streamChat({ message: text, agentId, threadId: THREAD_ID }, (event) => {
        switch (event.type) {
          case "route":
            patch((m) => ({ ...m, trace: [...m.trace, event] }));
            break;
          case "tool_call":
            patch((m) => ({ ...m, trace: [...m.trace, event] }));
            break;
          case "tool_result":
            patch((m) => ({ ...m, trace: [...m.trace, event] }));
            break;
          case "message":
            patch((m) => ({
              ...m,
              content: m.content ? `${m.content}\n\n${event.content}` : event.content,
            }));
            break;
          case "error":
            patch((m) => ({ ...m, content: `⚠️ ${event.message}`, error: true }));
            break;
          case "done":
            patch((m) => ({ ...m, pending: false }));
            break;
          default:
            break;
        }
      });
    } catch (e) {
      patch((m) => ({ ...m, content: `⚠️ ${e.message}`, error: true, pending: false }));
    } finally {
      setBusy(false);
    }
  };

  const onKeyDown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>Troubleshooting Agents</h1>
        <p>Talos · Ollama · NVIDIA · Proxmox — backed by gemma via LangGraph</p>
      </header>

      {loadError && (
        <div className="banner banner-error">
          Couldn't reach the backend ({loadError}). Is it running? See README.md.
        </div>
      )}

      <AgentSelector agents={agents} value={agentId} onChange={setAgentId} disabled={busy} />

      <main className="chat">
        {messages.length === 0 && (
          <p className="empty-hint">
            Ask something like "why is the ollama pod crash-looping?" or "is the GPU healthy?".
            Responses can take a while — this LLM runs on a single locally-hosted GPU.
          </p>
        )}
        {messages.map((m) => (
          <MessageBubble key={m.id} message={m} />
        ))}
        <div ref={bottomRef} />
      </main>

      <footer className="composer">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder="Describe the problem..."
          disabled={busy}
          rows={2}
        />
        <button onClick={send} disabled={busy || !input.trim()}>
          {busy ? "Thinking…" : "Send"}
        </button>
      </footer>
    </div>
  );
}
