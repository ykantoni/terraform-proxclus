function ArgsList({ args }) {
  const entries = Object.entries(args || {});
  if (entries.length === 0) return <em>no args</em>;
  return entries.map(([k, v]) => `${k}=${JSON.stringify(v)}`).join(", ");
}

export default function TraceView({ trace }) {
  if (!trace || trace.length === 0) return null;

  return (
    <details className="trace">
      <summary>
        {trace.filter((t) => t.type === "tool_call").length} tool call
        {trace.filter((t) => t.type === "tool_call").length === 1 ? "" : "s"}
      </summary>
      <ol>
        {trace.map((entry, i) => {
          if (entry.type === "route") {
            return (
              <li key={i} className="trace-route">
                Routed to <strong>{entry.agent_id}</strong>
              </li>
            );
          }
          if (entry.type === "tool_call") {
            return (
              <li key={i} className="trace-call">
                <span className="trace-icon">🔧</span>
                {entry.calls.map((c, j) => (
                  <div key={j}>
                    <code>{c.name}</code>(<ArgsList args={c.args} />)
                  </div>
                ))}
              </li>
            );
          }
          if (entry.type === "tool_result") {
            return (
              <li key={i} className="trace-result">
                <span className="trace-icon">↳</span>
                <code>{entry.name}</code>
                <pre>{entry.content}</pre>
              </li>
            );
          }
          return null;
        })}
      </ol>
    </details>
  );
}
