/**
 * crypto.randomUUID() only exists in "secure contexts" (https, or exactly
 * localhost) — this GUI is also opened over plain http://<lan-ip>:5173,
 * where it's undefined. This falls back to a non-cryptographic v4-shaped
 * id in that case; good enough since these ids are only ever local React
 * keys / a chat thread id, never security-sensitive.
 */
export function uid() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
