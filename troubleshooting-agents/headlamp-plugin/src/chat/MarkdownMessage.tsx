import Box from '@mui/material/Box';
import { alpha, Theme } from '@mui/material/styles';
import Typography from '@mui/material/Typography';
import { isValidElement, ReactNode } from 'react';
import ReactMarkdown, { Components } from 'react-markdown';

/** Flattens a React children tree back to plain text, for keyword matching
 * against a paragraph/list-item's content (ignores markup, just reads the
 * words). Good enough for classification — doesn't need to be exact. */
function textOf(node: ReactNode): string {
  if (node === null || node === undefined || typeof node === 'boolean') {
    return '';
  }
  if (typeof node === 'string' || typeof node === 'number') {
    return String(node);
  }
  if (Array.isArray(node)) {
    return node.map(textOf).join('');
  }
  if (isValidElement(node)) {
    return textOf((node.props as { children?: ReactNode }).children);
  }
  return '';
}

export type Importance = 'warning' | 'success' | 'info';

/**
 * Best-effort classification of a block's importance from its own wording,
 * so problem/evidence/healthy sections get visually distinct treatment
 * instead of a uniform look. Heuristic, not exhaustive — matches the
 * vocabulary this cluster's agents actually tend to use (see talos.md/
 * talos.ts's "root cause / evidence / next step / cluster is healthy"
 * answer shape). Order matters: a failure signal ("NotReady") is checked
 * before the generic "ready" success signal so it isn't misclassified.
 */
export function classifyImportance(text: string): Importance | undefined {
  if (
    /root cause|oomkilled|crashloopbackoff|not\s*ready|unhealthy|\berror\b|fail(ed|ing)?|insufficient|\bxid\b|vfio/i.test(
      text
    )
  ) {
    return 'warning';
  }
  if (/\bhealthy\b|no issues?(\s*(detected|found))?|\bready\b|\bresolved\b/i.test(text)) {
    return 'success';
  }
  if (/\bevidence\b|next (concrete )?step/i.test(text)) {
    return 'info';
  }
  return undefined;
}

/** A colored-left-border callout look for a classified block, or nothing
 * (an empty style) when the text doesn't match a known category — so
 * ordinary prose stays plain rather than getting an arbitrary default color.
 * Always returns a theme-callback (never a plain object) so every call site
 * can spread `calloutSx(text)(theme)` uniformly. */
function calloutSx(text: string): (theme: Theme) => Record<string, unknown> {
  const importance = classifyImportance(text);
  if (!importance) {
    return () => ({});
  }
  return (theme: Theme) => ({
    borderLeft: '3px solid',
    borderColor: `${importance}.main`,
    backgroundColor: alpha(theme.palette[importance].main, 0.08),
    pl: 1,
    pr: 0.75,
    py: 0.5,
    borderRadius: '0 4px 4px 0',
  });
}

/**
 * Element overrides so the model's Markdown (bold, bullets, headings, code
 * spans — it writes this even though the system prompt never asks for it)
 * renders as real rich text instead of literal `**`/`-`/`#`/backtick
 * characters. Plain CommonMark only — no remarkPlugins/remark-gfm, no
 * rehype-raw: react-markdown's default of never rendering raw embedded HTML
 * is the right, safe posture for LLM-controlled content and is kept as-is.
 */
const components: Components = {
  p: props => {
    const text = textOf(props.children);
    return (
      <Typography
        sx={theme => ({
          m: 0,
          mb: 1,
          '&:last-child': { mb: 0 },
          ...calloutSx(text)(theme),
        })}
      >
        {props.children}
      </Typography>
    );
  },
  // One small, bold size for every heading level — a chat bubble doesn't
  // need a full h1-h6 size hierarchy. Renders as a real <h6> (MUI's default
  // variantMapping for "subtitle2"), so it stays a real, accessible heading.
  h1: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  h2: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  h3: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  h4: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  h5: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  h6: props => (
    <Typography variant="subtitle2" sx={{ mt: 1, mb: 0.5, fontWeight: 600 }}>
      {props.children}
    </Typography>
  ),
  ul: props => (
    <Box component="ul" sx={{ pl: 3, m: 0, mb: 1 }}>
      {props.children}
    </Box>
  ),
  ol: props => (
    <Box component="ol" sx={{ pl: 3, m: 0, mb: 1 }}>
      {props.children}
    </Box>
  ),
  li: props => {
    const text = textOf(props.children);
    return (
      <Box component="li" sx={theme => ({ mb: 0.5, ...calloutSx(text)(theme) })}>
        {props.children}
      </Box>
    );
  },
  // A fenced code block's <code> is always wrapped in <pre> — react-markdown
  // v10 no longer passes an `inline` prop to distinguish it any other way —
  // so the block-vs-inline styling split happens structurally: style the
  // `pre` wrapper for a fenced block, and `code` below only ever sees the
  // inline case.
  pre: props => (
    <Box
      component="pre"
      sx={{
        backgroundColor: 'action.hover',
        p: 1,
        borderRadius: 1,
        overflowX: 'auto',
        fontFamily: 'monospace',
        fontSize: '0.85em',
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
        m: 0,
        mb: 1,
      }}
    >
      {props.children}
    </Box>
  ),
  code: props => (
    <Box
      component="code"
      sx={{
        fontFamily: 'monospace',
        fontSize: '0.85em',
        backgroundColor: 'action.hover',
        px: 0.5,
        py: 0.125,
        borderRadius: 0.5,
      }}
    >
      {props.children}
    </Box>
  ),
  // strong/em, a, blockquote, table: no override — native <strong>/<em>
  // already inherit the ambient font correctly, and there's no link
  // resolution or table requirement here (no remark-gfm, so GFM tables
  // don't parse as tables anyway).
};

export interface MarkdownMessageProps {
  content: string;
  /** Shown as plain text when `content` is empty, e.g. a pending "…". */
  placeholder?: string;
}

/** Renders one chat message's Markdown content as MUI-styled rich text. */
export function MarkdownMessage({ content, placeholder = '' }: MarkdownMessageProps) {
  if (!content) {
    return <Typography sx={{ m: 0 }}>{placeholder}</Typography>;
  }
  return <ReactMarkdown components={components}>{content}</ReactMarkdown>;
}
