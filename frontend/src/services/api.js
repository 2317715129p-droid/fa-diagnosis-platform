import { getBackendUrl } from '../utils/constants';

// For REST APIs, we need HTTP url instead of WS
const getHttpUrl = () => {
  const wsUrl = getBackendUrl();
  return wsUrl.replace(/^ws/, 'http');
};

/**
 * List monitored assets (agent collect inventory).
 * GET /api/assets
 */
export const fetchAssets = async () => {
  const response = await fetch(`${getHttpUrl()}/api/assets`);
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(
      `Failed to fetch assets: ${response.status}${detail ? ` — ${detail}` : ''}`
    );
  }
  return await response.json();
};

/**
 * Latest log snapshot for one asset.
 * GET /api/assets/{assetId}/logs
 */
export const fetchAssetLogs = async (assetId) => {
  if (!assetId) {
    throw new Error('Missing asset_id');
  }
  const response = await fetch(
    `${getHttpUrl()}/api/assets/${encodeURIComponent(assetId)}/logs`
  );
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(
      `Failed to fetch asset logs: ${response.status}${detail ? ` — ${detail}` : ''}`
    );
  }
  return await response.json();
};

/**
 * Remove asset from center inventory.
 * DELETE /api/assets/{assetId}
 */
export const deleteAsset = async (assetId) => {
  if (!assetId) {
    throw new Error('Missing asset_id');
  }
  const response = await fetch(
    `${getHttpUrl()}/api/assets/${encodeURIComponent(assetId)}`,
    { method: 'DELETE' }
  );
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(
      `Failed to delete asset: ${response.status}${detail ? ` — ${detail}` : ''}`
    );
  }
  return await response.json();
};

/** HTTP origin for agent install / download links */
export const getHttpOrigin = () => getHttpUrl();

/**
 * Archive a diagnosis report by id.
 * POST /api/archive  body: { report_id: reportId }
 */
export const archiveReport = async (reportId) => {
  if (reportId == null || reportId === '') {
    throw new Error('Missing report_id');
  }

  const response = await fetch(`${getHttpUrl()}/api/archive`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ report_id: reportId }),
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(
      `Failed to archive report: ${response.status} ${response.statusText}${detail ? ` — ${detail}` : ''}`
    );
  }

  return await response.json();
};

/**
 * Translate Chinese FA report to English.
 * POST /api/translate  body: { report_zh }
 */
export const translateReport = async (reportZh) => {
  if (!reportZh || !String(reportZh).trim()) {
    throw new Error('Missing report_zh');
  }

  const response = await fetch(`${getHttpUrl()}/api/translate`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ report_zh: reportZh }),
  });

  if (!response.ok) {
    let detail = '';
    try {
      const errBody = await response.json();
      detail = errBody.detail || JSON.stringify(errBody);
    } catch {
      detail = await response.text().catch(() => '');
    }
    throw new Error(
      `Failed to translate report: ${response.status}${detail ? ` — ${detail}` : ''}`
    );
  }

  const data = await response.json();
  if (!data.report_en) {
    throw new Error('Translate API returned empty report_en');
  }
  return data;
};

export const exportLog = async (logText) => {
  try {
    const response = await fetch(`${getHttpUrl()}/api/export`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ log_text: logText }),
    });

    if (!response.ok) {
      throw new Error(`Failed to export log: ${response.statusText}`);
    }

    return await response.blob();
  } catch (error) {
    console.error('API Error (exportLog):', error);
    throw error;
  }
};
