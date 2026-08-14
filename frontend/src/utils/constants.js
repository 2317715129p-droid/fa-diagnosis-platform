// Backend WebSocket / HTTP base URL.
// Local Vite (`npm run dev`): always FastAPI on :8000
// Docker nginx UI (:3000, production build): same origin (proxies /api /ws)
export const getBackendUrl = () => {
  if (import.meta.env.DEV) {
    const host =
      typeof window !== 'undefined' && window.location?.hostname
        ? window.location.hostname
        : 'localhost';
    return `ws://${host}:8000`;
  }
  if (typeof window !== 'undefined' && window.location?.host) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}`;
  }
  return 'ws://localhost:8000';
};

export const WS_ENDPOINT = '/ws/diagnose';
export const API_ENDPOINT = '/api/diagnose';
