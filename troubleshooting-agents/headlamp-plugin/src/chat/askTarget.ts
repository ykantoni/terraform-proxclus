import { CurrentResourceRef } from '../gather/types';
import { createModuleState } from './moduleState';

/**
 * The resource `AskAboutSection` last asked about, so the chat side panel
 * can show it without navigating away from the details page underneath —
 * see `AskAboutSection.tsx`'s comment for why this replaced pushing the
 * `/cluster-chat?kind=&name=&namespace=` route from there.
 */
const askTarget = createModuleState<CurrentResourceRef | undefined>(undefined);

export const setAskTarget = askTarget.set;
export const useAskTarget = askTarget.useValue;
