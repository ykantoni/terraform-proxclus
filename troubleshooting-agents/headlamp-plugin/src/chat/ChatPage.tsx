import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Checkbox from '@mui/material/Checkbox';
import FormControlLabel from '@mui/material/FormControlLabel';
import LinearProgress from '@mui/material/LinearProgress';
import Paper from '@mui/material/Paper';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { formatSnapshot, snapshotPreviewLines } from '../gather/format';
import { gatherSnapshot, useGatherCluster } from '../gather/kube';
import { spaceQuoteMarks } from './displayText';
import { ClusterSnapshot, CurrentResourceRef } from '../gather/types';
import { ChatMessage, ModelStatus, pingModel, streamChat } from '../ollama/client';
import { TALOS_SYSTEM_PROMPT } from '../prompt/talos';
import { store } from '../settings/store';
import { mergeSettings } from '../settings/types';

type Phase = 'idle' | 'gathering' | 'waiting' | 'streaming';

interface UiMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  error?: boolean;
  pending?: boolean;
  snapshot?: ClusterSnapshot;
  elapsedSeconds?: number;
}

function uid(): string {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function refFromSearch(search: string): CurrentResourceRef | undefined {
  const q = new URLSearchParams(search);
  const kind = q.get('kind') || '';
  const name = q.get('name') || '';
  const namespace = q.get('namespace') || undefined;
  if (!kind || !name) {
    return undefined;
  }
  return { kind, name, namespace: namespace || undefined };
}

export default function ChatPage() {
  const location = useLocation();
  const cluster = useGatherCluster();
  const useConf = store.useConfig();
  const settings = mergeSettings(useConf() || undefined);
  const [messages, setMessages] = useState<UiMessage[]>([]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [includeSnapshot, setIncludeSnapshot] = useState(true);
  const [phase, setPhase] = useState<Phase>('idle');
  const [elapsed, setElapsed] = useState(0);
  const [status, setStatus] = useState<ModelStatus | null>(null);
  const [current, setCurrent] = useState<CurrentResourceRef | undefined>(() =>
    refFromSearch(location.search)
  );
  const bottomRef = useRef<HTMLDivElement | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    setCurrent(refFromSearch(location.search));
  }, [location.search]);

  useEffect(() => {
    pingModel(settings).then(setStatus).catch(() => undefined);
    // settings identity changes every render if we depend on the object
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings.baseUrl, settings.model, settings.transport]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, phase]);

  useEffect(() => {
    if (!busy) {
      if (timerRef.current) {
        window.clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }
    const t0 = Date.now();
    timerRef.current = window.setInterval(() => {
      setElapsed(Math.round((Date.now() - t0) / 1000));
    }, 500);
    return () => {
      if (timerRef.current) {
        window.clearInterval(timerRef.current);
      }
    };
  }, [busy]);

  const historyForModel = useMemo(() => {
    const prose = messages
      .filter(m => !m.error && m.content)
      .slice(-6)
      .map(m => ({ role: m.role, content: m.content }) as ChatMessage);
    return prose;
  }, [messages]);

  const send = async (preset?: string) => {
    const text = (preset ?? input).trim();
    if (!text || busy) {
      return;
    }
    const userMsg: UiMessage = { id: uid(), role: 'user', content: text };
    const assistantId = uid();
    const assistantMsg: UiMessage = {
      id: assistantId,
      role: 'assistant',
      content: '',
      pending: true,
    };
    setMessages(prev => [...prev, userMsg, assistantMsg]);
    setInput('');
    setBusy(true);
    setElapsed(0);
    setPhase(includeSnapshot ? 'gathering' : 'waiting');

    const patch = (fn: (m: UiMessage) => UiMessage) =>
      setMessages(prev => prev.map(m => (m.id === assistantId ? fn(m) : m)));

    try {
      let snapshot: ClusterSnapshot | undefined;
      if (includeSnapshot) {
        snapshot = await gatherSnapshot(current, cluster);
        patch(m => ({ ...m, snapshot }));
      }

      setPhase('waiting');
      const payload: ChatMessage[] = [
        { role: 'system', content: TALOS_SYSTEM_PROMPT },
        ...historyForModel,
        {
          role: 'user',
          content: snapshot
            ? `${text}\n\n## Live cluster snapshot\n${formatSnapshot(snapshot)}`
            : text,
        },
      ];

      let sawToken = false;
      const t0 = Date.now();
      await streamChat({
        settings,
        messages: payload,
        onToken: chunk => {
          if (!sawToken) {
            sawToken = true;
            setPhase('streaming');
          }
          patch(m => ({ ...m, content: m.content + chunk }));
        },
      });
      patch(m => ({
        ...m,
        pending: false,
        elapsedSeconds: Math.round((Date.now() - t0) / 1000),
      }));
    } catch (err) {
      patch(m => ({
        ...m,
        pending: false,
        error: true,
        content: `⚠️ ${err instanceof Error ? err.message : String(err)}`,
      }));
    } finally {
      setBusy(false);
      setPhase('idle');
    }
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
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
              <Button key={q} size="small" variant="outlined" disabled={busy} onClick={() => send(q)}>
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
            <Typography
              component="pre"
              sx={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit', m: 0, mt: 0.5 }}
            >
              {m.content ? spaceQuoteMarks(m.content) : m.pending ? '…' : ''}
            </Typography>
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
        <Button variant="contained" onClick={() => send()} disabled={busy || !input.trim()}>
          {busy ? 'Thinking…' : 'Send'}
        </Button>
      </Box>
    </SectionBox>
  );
}
