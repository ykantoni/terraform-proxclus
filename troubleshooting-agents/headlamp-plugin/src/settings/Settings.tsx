import { NameValueTable } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import Box from '@mui/material/Box';
import MenuItem from '@mui/material/MenuItem';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import type { ReactNode } from 'react';
import { DEFAULT_SETTINGS, mergeSettings,PluginSettings, Transport } from './types';

interface SettingsProps {
  data?: Partial<PluginSettings> | null;
  onDataChange?: (data: PluginSettings) => void;
}

function Field({ helper, children }: { helper?: string; children: ReactNode }) {
  return (
    <Box sx={{ minWidth: 280 }}>
      {children}
      {helper && (
        <Typography variant="caption" color="text.secondary" display="block">
          {helper}
        </Typography>
      )}
    </Box>
  );
}

export default function Settings({ data, onDataChange }: SettingsProps) {
  const current = mergeSettings(data);

  function patch(partial: Partial<PluginSettings>) {
    onDataChange?.({ ...current, ...partial });
  }

  const rows = [
    {
      name: 'Ollama base URL',
      value: (
        <Field helper="LAN LoadBalancer. Used when transport is direct or auto.">
          <TextField
            size="small"
            fullWidth
            value={current.baseUrl}
            onChange={e => patch({ baseUrl: e.target.value })}
          />
        </Field>
      ),
    },
    {
      name: 'Model',
      value: (
        <TextField
          size="small"
          fullWidth
          value={current.model}
          onChange={e => patch({ model: e.target.value })}
        />
      ),
    },
    {
      name: 'Timeout (seconds)',
      value: (
        <Field helper={`Default ${DEFAULT_SETTINGS.timeoutSeconds}s per LLM call.`}>
          <TextField
            size="small"
            type="number"
            value={current.timeoutSeconds}
            onChange={e => patch({ timeoutSeconds: Number(e.target.value) || 300 })}
          />
        </Field>
      ),
    },
    {
      name: 'keep_alive',
      value: (
        <TextField
          size="small"
          value={current.keepAlive}
          onChange={e => patch({ keepAlive: e.target.value })}
        />
      ),
    },
    {
      name: 'Transport',
      value: (
        <Field helper="auto: LAN first, kube service proxy if CORS or LAN fails.">
          <TextField
            select
            size="small"
            value={current.transport}
            onChange={e => patch({ transport: e.target.value as Transport })}
          >
            <MenuItem value="auto">auto</MenuItem>
            <MenuItem value="direct">direct</MenuItem>
            <MenuItem value="proxy">proxy</MenuItem>
          </TextField>
        </Field>
      ),
    },
    {
      name: 'Proxy service',
      value: (
        <Field helper="kube-apiserver service proxy: namespace/service:port">
          <TextField
            size="small"
            value={`${current.proxyNamespace}/${current.proxyService}:${current.proxyPort}`}
            onChange={e => {
              const m = e.target.value.match(/^([^/]+)\/([^:]+):(\d+)$/);
              if (m) {
                patch({
                  proxyNamespace: m[1],
                  proxyService: m[2],
                  proxyPort: Number(m[3]),
                });
              }
            }}
          />
        </Field>
      ),
    },
  ];

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Read-only cluster chat. The plugin gathers Kubernetes facts; the model only writes prose.
      </Typography>
      <NameValueTable rows={rows} />
    </Box>
  );
}
