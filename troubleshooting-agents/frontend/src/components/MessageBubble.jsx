import TraceView from "./TraceView.jsx";

export default function MessageBubble({ message }) {
  const { role, content, trace, pending, error } = message;

  return (
    <div className={`bubble bubble-${role}${error ? " bubble-error" : ""}`}>
      <div className="bubble-role">{role === "user" ? "You" : "Agent"}</div>
      <TraceView trace={trace} />
      <div className="bubble-content">
        {content}
        {pending && <span className="cursor">▍</span>}
      </div>
    </div>
  );
}
