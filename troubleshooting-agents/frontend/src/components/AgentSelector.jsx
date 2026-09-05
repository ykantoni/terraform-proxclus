export default function AgentSelector({ agents, value, onChange, disabled }) {
  const current = agents.find((a) => a.id === value);

  return (
    <div className="agent-selector">
      <label htmlFor="agent-select">Agent</label>
      <select
        id="agent-select"
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
      >
        <option value="auto">Auto-detect</option>
        {agents.map((a) => (
          <option key={a.id} value={a.id}>
            {a.title}
          </option>
        ))}
      </select>
      <p className="agent-description">
        {value === "auto"
          ? "The router reads your question and picks the specialist agent for it."
          : current?.description}
      </p>
    </div>
  );
}
