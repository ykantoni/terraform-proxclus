import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import Button from '@mui/material/Button';
import Typography from '@mui/material/Typography';
import { setAskTarget } from '../chat/askTarget';
import { setChatPanelOpen } from '../chat/panelState';
import { ASKABLE_KINDS } from './kinds';

interface ResourceLike {
  kind?: string;
  metadata?: { name?: string; namespace?: string };
}

export function AskAboutSection({ resource }: { resource?: ResourceLike }) {
  if (!resource?.kind || !ASKABLE_KINDS.has(resource.kind) || !resource.metadata?.name) {
    return null;
  }

  const kind = resource.kind;
  const name = resource.metadata.name;
  const namespace = resource.metadata.namespace;

  const open = () => {
    // Opens the side panel in place, rather than navigating the main
    // content area to the dedicated /cluster-chat page — that would
    // replace this details page instead of just adding the chat alongside
    // it. ChatPage picks this up via useAskTarget().
    setAskTarget({ kind, name, namespace });
    setChatPanelOpen(true);
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
