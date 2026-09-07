import { useMemo, useState } from 'react';
import { formatSnapshot } from '../gather/format';
import { gatherSnapshot } from '../gather/kube';
import { ClusterSnapshot, CurrentResourceRef } from '../gather/types';
import { ChatMessage, streamChat } from '../ollama/client';
import { TALOS_SYSTEM_PROMPT } from '../prompt/talos';
import { PluginSettings } from '../settings/types';
import { useElapsedSeconds } from './useElapsedSeconds';

export type ChatPhase = 'idle' | 'gathering' | 'waiting' | 'streaming';

export interface UiMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  error?: boolean;
  pending?: boolean;
  snapshot?: ClusterSnapshot;
  elapsedSeconds?: number;
}

/**
 * How many of the most recent user/assistant turns to replay to the model
 * as conversation history on each new question. Kept short: this model's
 * cold-start cost (see README) means a shorter prompt matters more than
 * long recall.
 */
const HISTORY_TURNS = 6;

function uid(): string {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export interface UseChatSessionParams {
  cluster: string | null;
  settings: PluginSettings;
  current?: CurrentResourceRef;
  includeSnapshot: boolean;
}

export interface ChatSession {
  messages: UiMessage[];
  busy: boolean;
  phase: ChatPhase;
  elapsed: number;
  send: (text: string) => Promise<void>;
}

/**
 * Owns one chat conversation's messages and the send-a-question flow:
 * gather an optional live snapshot, assemble the prompt (system prompt +
 * recent history + this question, with the snapshot appended), stream the
 * model's reply token by token, and track which phase that's in
 * (gathering/waiting/streaming) so the UI can show progress.
 */
export function useChatSession({
  cluster,
  settings,
  current,
  includeSnapshot,
}: UseChatSessionParams): ChatSession {
  const [messages, setMessages] = useState<UiMessage[]>([]);
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<ChatPhase>('idle');
  const elapsed = useElapsedSeconds(busy);

  const historyForModel = useMemo(() => {
    return messages
      .filter(m => !m.error && m.content)
      .slice(-HISTORY_TURNS)
      .map(m => ({ role: m.role, content: m.content }) as ChatMessage);
  }, [messages]);

  const send = async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed || busy) {
      return;
    }
    const userMsg: UiMessage = { id: uid(), role: 'user', content: trimmed };
    const assistantId = uid();
    const assistantMsg: UiMessage = {
      id: assistantId,
      role: 'assistant',
      content: '',
      pending: true,
    };
    setMessages(prev => [...prev, userMsg, assistantMsg]);
    setBusy(true);
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
            ? `${trimmed}\n\n## Live cluster snapshot\n${formatSnapshot(snapshot)}`
            : trimmed,
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

  return { messages, busy, phase, elapsed, send };
}
