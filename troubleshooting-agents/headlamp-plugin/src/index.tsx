import { Icon } from '@iconify/react';
import {
  DetailsViewSectionProps,
  registerAppBarAction,
  registerDetailsViewSection,
  registerPluginSettings,
  registerRoute,
  registerSidebarEntry,
  registerUIPanel,
} from '@kinvolk/headlamp-plugin/lib';
import Box from '@mui/material/Box';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import ChatPage from './chat/ChatPage';
import { setChatPanelOpen, toggleChatPanel, useChatPanelOpen } from './chat/panelState';
import { AskAboutSection } from './details/AskAboutSection';
import Settings from './settings/Settings';
import { PLUGIN_NAME } from './settings/types';

registerSidebarEntry({
  parent: null,
  name: 'cluster-chat',
  label: 'Cluster Chat',
  url: '/cluster-chat',
  icon: 'mdi:chat-question',
  useClusterURL: true,
});

registerRoute({
  path: '/cluster-chat',
  sidebar: 'cluster-chat',
  name: 'cluster-chat',
  exact: true,
  useClusterURL: true,
  component: () => <ChatPage />,
});

registerPluginSettings(PLUGIN_NAME, Settings, true);

registerDetailsViewSection(({ resource }: DetailsViewSectionProps) => (
  <AskAboutSection resource={resource} />
));

function ChatAppBarButton() {
  const open = useChatPanelOpen();
  return (
    <Tooltip title="Cluster Chat">
      <IconButton
        aria-label="Cluster Chat"
        aria-pressed={open}
        size="small"
        color={open ? 'primary' : 'default'}
        onClick={() => toggleChatPanel()}
      >
        <Icon icon="mdi:chat-question" />
      </IconButton>
    </Tooltip>
  );
}

function ChatPanel() {
  const open = useChatPanelOpen();
  if (!open) {
    return null;
  }
  return (
    <Box
      sx={{
        width: { xs: '100%', sm: 420, md: 480 },
        maxWidth: '100%',
        height: '100%',
        overflow: 'auto',
        borderLeft: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
      }}
    >
      <Box sx={{ display: 'flex', justifyContent: 'flex-end', px: 1, pt: 1 }}>
        <IconButton aria-label="Close Cluster Chat" size="small" onClick={() => setChatPanelOpen(false)}>
          <Icon icon="mdi:close" />
        </IconButton>
      </Box>
      <ChatPage />
    </Box>
  );
}

registerAppBarAction(ChatAppBarButton);

registerUIPanel({
  id: 'cluster-chat-panel',
  side: 'right',
  component: () => <ChatPanel />,
});
