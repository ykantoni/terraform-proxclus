import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { classifyImportance, MarkdownMessage } from './MarkdownMessage';

describe('classifyImportance', () => {
  it('classifies failure/problem language as "warning"', () => {
    expect(classifyImportance('Reason: OOMKilled, container was killed')).toBe('warning');
    expect(classifyImportance('The node is NotReady')).toBe('warning');
    expect(classifyImportance('Root cause: insufficient memory')).toBe('warning');
  });

  it('classifies healthy/resolved language as "success"', () => {
    expect(classifyImportance('Cluster is healthy. No issues detected.')).toBe('success');
    expect(classifyImportance('All four nodes report ready: true')).toBe('success');
  });

  it('does not misclassify "not ready" as success just because it contains "ready"', () => {
    expect(classifyImportance('The node is not ready yet')).toBe('warning');
  });

  it('classifies evidence/next-step language as "info"', () => {
    expect(classifyImportance('Evidence: the describe output shows the reason')).toBe('info');
    expect(classifyImportance('Next concrete step: check the pod logs')).toBe('info');
  });

  it('returns undefined for plain, unclassified text', () => {
    expect(classifyImportance('Analysis:')).toBeUndefined();
    expect(classifyImportance('Nodes:')).toBeUndefined();
  });
});

describe('MarkdownMessage', () => {
  it('renders **bold** text as a real bold element with no literal asterisks', () => {
    const { container } = render(<MarkdownMessage content="**Nodes** are healthy" />);
    const nodesText = screen.getByText('Nodes');
    expect(nodesText.tagName).toBe('STRONG');
    expect(container.textContent).not.toContain('*');
  });

  it('renders a bullet list as real <ul>/<li> elements, not literal dashes', () => {
    const { container } = render(<MarkdownMessage content={'- foo\n- bar'} />);
    const items = screen.getAllByRole('listitem');
    expect(items).toHaveLength(2);
    expect(items[0]).toHaveTextContent('foo');
    expect(items[1]).toHaveTextContent('bar');
    expect(container.textContent).not.toContain('-');
  });

  it('renders a heading as a real heading element, not literal "#"', () => {
    const { container } = render(<MarkdownMessage content="### Something" />);
    expect(screen.getByRole('heading')).toHaveTextContent('Something');
    expect(container.textContent).not.toContain('#');
  });

  it('renders inline code as a distinct element with no literal backticks', () => {
    const { container } = render(<MarkdownMessage content="run `nvidia-smi`" />);
    expect(container.textContent).toBe('run nvidia-smi');
    expect(screen.getByText('nvidia-smi').tagName).toBe('CODE');
  });

  it('renders the placeholder when content is empty', () => {
    render(<MarkdownMessage content="" placeholder="…" />);
    expect(screen.getByText('…')).toBeInTheDocument();
  });

  it('renders plain text with no Markdown syntax unchanged', () => {
    render(<MarkdownMessage content="All four nodes are Ready." />);
    expect(screen.getByText('All four nodes are Ready.')).toBeInTheDocument();
  });

  it('renders a real-world answer shape: bold labels inside bullets, no blank line before the list', () => {
    const content = [
      'Yes, the cluster is healthy.',
      '',
      '**Analysis:**',
      '* **Nodes:** All four nodes report ready.',
      '* **Pods:** The list is empty.',
      '* **Events:** The list is empty.',
      '',
      '**Conclusion:**',
      'Cluster is healthy. No issues detected.',
    ].join('\n');
    const { container } = render(<MarkdownMessage content={content} />);

    expect(screen.getAllByRole('listitem')).toHaveLength(3);
    expect(screen.getByText('Analysis:').tagName).toBe('STRONG');
    expect(screen.getByText('Conclusion:').tagName).toBe('STRONG');
    expect(container.textContent).not.toMatch(/[*]/);
  });

  it('gives a classified paragraph a colored callout border, and leaves a plain one unstyled', () => {
    const { container } = render(
      <MarkdownMessage content={'Cluster is healthy.\n\nAnalysis:'} />
    );
    const paragraphs = container.querySelectorAll('p');
    expect(paragraphs).toHaveLength(2);
    // "Cluster is healthy." matches the success pattern and gets a callout
    // border; the bare "Analysis:" label matches nothing and stays plain.
    expect(getComputedStyle(paragraphs[0]).borderLeftWidth).toBe('3px');
    expect(getComputedStyle(paragraphs[1]).borderLeftWidth).not.toBe('3px');
  });
});
