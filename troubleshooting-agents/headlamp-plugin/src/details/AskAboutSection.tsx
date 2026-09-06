import { Router } from '@kinvolk/headlamp-plugin/lib';
import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import Button from '@mui/material/Button';
import Typography from '@mui/material/Typography';
import { useHistory } from 'react-router-dom';
import { setChatPanelOpen } from '../chat/panelState';
import { ASKABLE_KINDS } from './kinds';

interface ResourceLike {
  kind?: string;
  metadata?: { name?: string; namespace?: string };
}

export function AskAboutSection({ resource }: { resource?: ResourceLike }) {
  const history = useHistory();
  if (!resource?.kind || !ASKABLE_KINDS.has(resource.kind) || !resource.metadata?.name) {
    return null;
  }

  const kind = resource.kind;
  const name = resource.metadata.name;
  const namespace = resource.metadata.namespace;

  const open = () => {
    const params = new URLSearchParams({ kind, name });
    if (namespace) {
      params.set('namespace', namespace);
    }
    setChatPanelOpen(true);
    try {
      const url = Router.createRouteURL('cluster-chat');
      history.push(`${url}?${params.toString()}`);
    } catch {
      // panel is already open
    }
  };

  return (
    <SectionBox title="Cluster Chat">
      <Typography variant="body2" sx={{ mb: 1 }}>
        Ask the read-only chatbot about this {kind}. It will attach a trimmed snapshot of the
        object plus cluster nodes, unhealthy pods, and warning events.
      </Typography>
      <Button variant="outlined" size="small" onClick={open}>
        Ask about {kind}/{namespace ? `${namespace}/` : ''}
        {name}
      </Button>
    </SectionBox>
  );
}
