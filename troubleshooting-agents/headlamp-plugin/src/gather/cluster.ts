/** Pull `/c/<cluster>` from hash or pathname. Electron Headlamp is inconsistent about which it uses. */
export function clusterFromLocation(path?: string): string | null {
  const candidates = path
    ? [path]
    : typeof window === 'undefined'
      ? []
      : [window.location.hash.replace(/^#/, ''), window.location.pathname, window.location.href];
  for (const raw of candidates) {
    if (!raw) {
      continue;
    }
    const m = raw.match(/\/c\/([^/?#]+)/);
    const name = m?.[1];
    if (name && name !== 'undefined') {
      return decodeURIComponent(name.split('+')[0]);
    }
  }
  return null;
}
