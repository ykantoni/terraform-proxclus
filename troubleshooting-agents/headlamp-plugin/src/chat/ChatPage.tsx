import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Checkbox from '@mui/material/Checkbox';
import FormControlLabel from '@mui/material/FormControlLabel';
import LinearProgress from '@mui/material/LinearProgress';
import Paper from '@mui/material/Paper';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import React, { useEffect, useRef, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { formatSnapshot, snapshotPreviewLines } from '../gather/format';
import { useGatherCluster } from '../gather/kube';
import { CurrentResourceRef } from '../gather/types';
import { store } from '../settings/store';
import { mergeSettings } from '../settings/types';
import { useAskTarget } from './askTarget';
import { MarkdownMessage } from './MarkdownMessage';
import { useChatSession } from './useChatSession';
import { useModelStatus } from './useModelStatus';

function refFromSearch(search: string): CurrentResourceRef | undefined {
  const q = new URLSearchParams(search);
  const kind = q.get('kind') || '';
  const name = q.get('name') || '';
  const namespace = q.get('namespace') || undefined;
  if (!kind || !name) {
    return undefined;
  }
  return { kind, name, namespace };
}

export default function ChatPage() {
  const location = useLocation();
  const cluster = useGatherCluster();
  const useConf = store.useConfig();
  const settings = mergeSettings(useConf() || undefined);
  const [input, setInput] = useState('');
  const [includeSnapshot, setIncludeSnapshot] = useState(true);
  const status = useModelStatus(settings);
  // Set by AskAboutSection (a resource's details page) when the panel is
  // opened in place; refFromSearch is the fallback for a direct/bookmarked
  // link to the dedicated /cluster-chat page.
  const current = useAskTarget() ?? refFromSearch(location.search);
  const { messages, busy, phase, elapsed, send } = useChatSession({
    cluster,
    settings,
    current,
    includeSnapshot,
  });
  const bottomRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, phase]);

  const onSend = (preset?: string) => {
    const text = preset ?? input;
    setInput('');
    void send(text);
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      onSend();
    }
  };

  const phaseLabel =
    phase === 'gathering'
      ? `gathering cluster facts… (${elapsed}s)`
      : phase === 'waiting'
        ? `waiting on ${settings.model} (${elapsed}s)`
        : phase === 'streaming'
          ? `streaming (${elapsed}s)`
          : null;

  return (
    <SectionBox title="Cluster Chat">
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        This model often takes tens of seconds; the first question after idle can be a minute. The
        plugin gathers a live Kubernetes snapshot, then {settings.model} writes the answer. It
        cannot run talosctl, SSH, or mutate the cluster.
      </Typography>

      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', mb: 2, alignItems: 'center' }}>
        <Typography variant="caption">
          cluster: {cluster || 'none — open a cluster first'}
          {' · '}
          {status?.error
            ? `Ollama: ${status.error}`
            : status?.loaded
              ? `${settings.model} is loaded (${status.transport})`
              : status
                ? `${settings.model} is not loaded — first reply pays cold prompt-eval`
                : 'checking Ollama…'}
        </Typography>
        <FormControlLabel
          control={
            <Checkbox
              checked={includeSnapshot}
              onChange={e => setIncludeSnapshot(e.target.checked)}
              disabled={busy}
            />
          }
          label="include live snapshot"
        />
        {current && (
          <Typography variant="caption">
            current resource: {current.kind}/{current.namespace ? `${current.namespace}/` : ''}
            {current.name}
          </Typography>
        )}
      </Box>

      {messages.length === 0 && (
        <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
          <Typography variant="body2">Try:</Typography>
          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mt: 1 }}>
            {[
              'Is the cluster healthy right now?',
              'Any CrashLoopBackOff or OOMKilled pods?',
              'talosctl health says ext-nvidia-persistenced is waiting — is that serious?',
            ].map(q => (
              <Button
                key={q}
                size="small"
                variant="outlined"
                disabled={busy}
                onClick={() => onSend(q)}
              >
                {q}
              </Button>
            ))}
          </Box>
        </Paper>
      )}

      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5, mb: 2 }}>
        {messages.map(m => (
          <Paper key={m.id} variant="outlined" sx={{ p: 1.5 }}>
            <Typography variant="caption" color="text.secondary">
              {m.role}
              {m.pending ? ' · thinking' : ''}
            </Typography>
            <Box sx={{ mt: 0.5 }}>
              <MarkdownMessage content={m.content} placeholder={m.pending ? '…' : ''} />
            </Box>
            {m.snapshot && (
              <details style={{ marginTop: 8 }}>
                <summary>snapshot sent ({snapshotPreviewLines(m.snapshot).join(' · ')})</summary>
                <Typography
                  component="pre"
                  sx={{ fontSize: 12, overflow: 'auto', maxHeight: 240, mt: 1 }}
                >
                  {formatSnapshot(m.snapshot)}
                </Typography>
              </details>
            )}
          </Paper>
        ))}
        <div ref={bottomRef} />
      </Box>

      {busy && (
        <Box sx={{ mb: 2 }}>
          <LinearProgress />
          {phaseLabel && (
            <Typography variant="caption" color="text.secondary">
              {phaseLabel}
            </Typography>
          )}
        </Box>
      )}

      <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-end' }}>
        <TextField
          fullWidth
          multiline
          minRows={2}
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          disabled={busy}
          placeholder="Ask about node health, unhealthy pods, or this resource…"
        />
        <Button variant="contained" onClick={() => onSend()} disabled={busy || !input.trim()}>
          {busy ? 'Thinking…' : 'Send'}
        </Button>
      </Box>
    </SectionBox>
  );
}
