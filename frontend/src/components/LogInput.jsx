import React, { useState, useRef, useMemo, useCallback, useEffect } from 'react';
import { mapLogTokens, TOAST_VISIBLE_MS } from '../utils/logHighlight';
import { fetchAssets, fetchAssetLogs, deleteAsset, getHttpOrigin } from '../services/api';

const POLL_MS = 15000;

const STATUS_META = {
  online: { label: '在线', dot: 'bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.8)]', text: 'text-green-400' },
  stale: { label: '过期', dot: 'bg-yellow-500 shadow-[0_0_8px_rgba(234,179,8,0.7)]', text: 'text-yellow-400' },
  offline: { label: '离线', dot: 'bg-gray-500', text: 'text-gray-400' },
  never: { label: '未上报', dot: 'bg-gray-700', text: 'text-gray-500' },
};

const FILTERS = [
  { id: 'all', label: '全部' },
  { id: 'online', label: '在线' },
  { id: 'stale', label: '过期' },
  { id: 'offline', label: '离线' },
];

function formatRelative(iso) {
  if (!iso) return '从未上报';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '从未上报';
  const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
  if (sec < 60) return `${sec} 秒前`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min} 分钟前`;
  const hr = Math.floor(min / 60);
  if (hr < 48) return `${hr} 小时前`;
  const days = Math.floor(hr / 24);
  return `${days} 天前`;
}

const LogInput = ({ onDiagnose, isProcessing }) => {
  const [activeTab, setActiveTab] = useState('manual');
  const [logText, setLogText] = useState('');
  const [toast, setToast] = useState(null);

  const [assets, setAssets] = useState([]);
  const [assetsError, setAssetsError] = useState(null);
  const [assetsLoading, setAssetsLoading] = useState(false);
  const [filter, setFilter] = useState('all');
  const [selectedId, setSelectedId] = useState(null);
  const [assetLogText, setAssetLogText] = useState('');
  const [assetLogMeta, setAssetLogMeta] = useState(null);
  const [logsLoading, setLogsLoading] = useState(false);

  const textareaRef = useRef(null);
  const highlightRef = useRef(null);
  const toastTimerRef = useRef(null);

  const exampleLog = `CPU 0: Machine Check Exception: 0000000000000004
Bank 4: f200000000070005
Error code 0x0005: Internal parity error`;

  const [deployServerId, setDeployServerId] = useState('Node-01');

  const httpOrigin = getHttpOrigin();
  const collectUrl = `${httpOrigin}/api/collect`;
  const oneClickCmd = `curl -fsSL "${httpOrigin}/api/agent/install.sh?server_id=${encodeURIComponent(deployServerId || 'Node-01')}" | sudo bash`;
  const oneClickUninstallCmd = `curl -fsSL "${httpOrigin}/api/agent/uninstall.sh" | sudo bash`;

  const highlighted = useMemo(() => mapLogTokens(logText, React), [logText]);
  const assetHighlighted = useMemo(
    () => mapLogTokens(assetLogText, React),
    [assetLogText]
  );

  const showToast = useCallback((message) => {
    if (toastTimerRef.current) {
      clearTimeout(toastTimerRef.current);
    }
    setToast({ message, key: Date.now() });
    toastTimerRef.current = setTimeout(() => {
      setToast(null);
      toastTimerRef.current = null;
    }, TOAST_VISIBLE_MS);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    };
  }, []);

  const loadAssets = useCallback(async () => {
    setAssetsLoading(true);
    setAssetsError(null);
    try {
      const data = await fetchAssets();
      setAssets(Array.isArray(data) ? data : []);
    } catch (err) {
      setAssetsError(err?.message || '加载资产失败');
    } finally {
      setAssetsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeTab !== 'auto') return undefined;
    loadAssets();
    const id = setInterval(loadAssets, POLL_MS);
    return () => clearInterval(id);
  }, [activeTab, loadAssets]);

  useEffect(() => {
    if (activeTab !== 'auto' || !selectedId) {
      return undefined;
    }
    let cancelled = false;
    setLogsLoading(true);
    fetchAssetLogs(selectedId)
      .then((data) => {
        if (cancelled) return;
        setAssetLogText(data.last_log_text || '');
        setAssetLogMeta(data);
      })
      .catch((err) => {
        if (cancelled) return;
        setAssetLogText('');
        setAssetLogMeta(null);
        showToast(err?.message || '加载日志失败');
      })
      .finally(() => {
        if (!cancelled) setLogsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [activeTab, selectedId, showToast]);

  // Refresh selected log when assets poll updates that row's last_log_at
  useEffect(() => {
    if (activeTab !== 'auto' || !selectedId || !assetLogMeta) return;
    const row = assets.find((a) => a.asset_id === selectedId);
    if (!row) return;
    if (row.last_log_at && row.last_log_at !== assetLogMeta.last_log_at) {
      fetchAssetLogs(selectedId)
        .then((data) => {
          setAssetLogText(data.last_log_text || '');
          setAssetLogMeta(data);
        })
        .catch(() => {});
    }
  }, [assets, selectedId, activeTab, assetLogMeta]);

  const filteredAssets = useMemo(() => {
    if (filter === 'all') return assets;
    if (filter === 'offline') {
      return assets.filter(
        (a) => a.online_status === 'offline' || a.online_status === 'never'
      );
    }
    return assets.filter((a) => a.online_status === filter);
  }, [assets, filter]);

  const syncScroll = () => {
    const ta = textareaRef.current;
    const hi = highlightRef.current;
    if (ta && hi) {
      hi.scrollTop = ta.scrollTop;
      hi.scrollLeft = ta.scrollLeft;
    }
  };

  const handleDeleteAsset = async (assetId, e) => {
    e?.stopPropagation?.();
    if (!assetId) return;
    if (!window.confirm(`从监视列表删除「${assetId}」？\n（仅删中心记录，不会卸载服务器上的 Agent）`)) {
      return;
    }
    try {
      await deleteAsset(assetId);
      if (selectedId === assetId) {
        setSelectedId(null);
        setAssetLogText('');
        setAssetLogMeta(null);
      }
      showToast(`✓ 已删除 ${assetId}`);
      await loadAssets();
    } catch (err) {
      showToast(err?.message || '删除失败');
    }
  };

  const handleDiagnose = () => {
    if (activeTab === 'manual') {
      if (!logText.trim()) return;
      onDiagnose(logText, 'manual-input');
      return;
    }
    if (!selectedId || !assetLogText.trim()) return;
    onDiagnose(assetLogText, selectedId);
  };

  const handleClear = () => {
    if (activeTab === 'manual') {
      setLogText('');
    } else {
      setSelectedId(null);
      setAssetLogText('');
      setAssetLogMeta(null);
    }
  };

  const handleExport = () => {
    const text = activeTab === 'manual' ? logText : assetLogText;
    if (!text) return;
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download =
      activeTab === 'auto' && selectedId
        ? `${selectedId}_hardware_log.txt`
        : 'hardware_log.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('✓ 已成功导出');
  };

  const canDiagnose =
    activeTab === 'manual'
      ? Boolean(logText.trim())
      : Boolean(selectedId && assetLogText.trim());

  const exportDisabled =
    isProcessing ||
    (activeTab === 'manual' ? !logText : !assetLogText);

  return (
    <div className="flex flex-col h-full bg-[#0c0c22] overflow-hidden">
      <div className="flex border-b border-[#333]">
        <button
          className={`flex-1 py-3 text-sm font-bold transition-colors ${
            activeTab === 'manual'
              ? 'bg-[#0a0a1a] border-b-2 border-blue-500 text-blue-400'
              : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
          }`}
          onClick={() => setActiveTab('manual')}
        >
          ✍️ 手动粘贴
        </button>
        <button
          className={`flex-1 py-3 text-sm font-bold transition-colors ${
            activeTab === 'auto'
              ? 'bg-[#0a0a1a] border-b-2 border-blue-500 text-blue-400'
              : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
          }`}
          onClick={() => setActiveTab('auto')}
        >
          🤖 自动采集
        </button>
      </div>

      <div className="p-4 flex-1 flex flex-col gap-4 overflow-y-auto">
        {activeTab === 'manual' ? (
          <>
            <div className="flex justify-between items-end">
              <span className="text-[10px] text-gray-500 uppercase tracking-widest">
                Raw Hardware Logs
              </span>
              <span className="text-[10px] text-gray-400">
                已输入 {logText.length} 字符
              </span>
            </div>

            <div className="relative flex-1 group min-h-[300px]">
              <pre
                ref={highlightRef}
                aria-hidden="true"
                className="log-highlight-layer absolute inset-0 m-0 p-4 overflow-hidden border border-transparent rounded font-mono text-sm leading-normal pointer-events-none whitespace-pre-wrap break-words"
              >
                {highlighted}
                {'\n'}
              </pre>

              <textarea
                ref={textareaRef}
                className="log-editor-layer relative z-10 w-full h-full bg-transparent text-transparent caret-[#0f0] p-4 text-sm border border-[#333] rounded focus:outline-none focus:border-green-500 resize-none font-mono leading-normal scrollbar-thin scrollbar-thumb-gray-700 selection:bg-green-500/30"
                placeholder="在此粘贴服务器硬件日志...（支持 dmesg、mcelog、IPMI SEL 格式）"
                value={logText}
                onChange={(e) => setLogText(e.target.value)}
                onScroll={syncScroll}
                spellCheck={false}
              />

              <button
                type="button"
                onClick={() => setLogText(exampleLog)}
                className="absolute top-2 right-2 z-20 px-2 py-1 bg-[#222] hover:bg-[#333] text-[10px] text-gray-300 border border-gray-600 rounded flex items-center gap-1 transition-colors"
              >
                📋 加载示例
              </button>
            </div>
          </>
        ) : (
          <div className="flex flex-col gap-3 flex-1 min-h-0">
            <div className="flex items-center justify-between gap-2">
              <span className="text-[10px] text-gray-500 uppercase tracking-widest">
                监视资产
              </span>
              <button
                type="button"
                onClick={loadAssets}
                disabled={assetsLoading}
                className="text-[10px] text-blue-400 hover:text-blue-300 disabled:opacity-40"
              >
                {assetsLoading ? '刷新中…' : '刷新'}
              </button>
            </div>

            <div className="flex flex-wrap gap-1.5">
              {FILTERS.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => setFilter(f.id)}
                  className={`px-2.5 py-1 text-[10px] font-semibold rounded border transition-colors ${
                    filter === f.id
                      ? 'border-blue-500/60 bg-blue-500/15 text-blue-300'
                      : 'border-[#333] text-gray-500 hover:text-gray-300'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>

            {assetsError && (
              <p className="text-xs text-red-400 border border-red-500/30 bg-red-900/20 rounded px-3 py-2">
                {assetsError}
              </p>
            )}

            <div className="border border-[#333] rounded overflow-hidden max-h-48 overflow-y-auto shrink-0">
              {filteredAssets.length === 0 ? (
                <div className="px-3 py-6 text-center text-xs text-gray-500">
                  {assetsLoading ? '加载中…' : '暂无上报资产，请先安装 Agent'}
                </div>
              ) : (
                <ul className="divide-y divide-[#222]">
                  {filteredAssets.map((asset) => {
                    const meta =
                      STATUS_META[asset.online_status] || STATUS_META.never;
                    const selected = selectedId === asset.asset_id;
                    return (
                      <li key={asset.asset_id}>
                        <div
                          className={`flex items-stretch gap-1 transition-colors ${
                            selected
                              ? 'bg-blue-500/10'
                              : 'hover:bg-white/[0.03]'
                          }`}
                        >
                          <button
                            type="button"
                            onClick={() => setSelectedId(asset.asset_id)}
                            className="flex-1 min-w-0 text-left px-3 py-2.5 flex items-start gap-2.5"
                          >
                            <span
                              className={`mt-1.5 w-2 h-2 rounded-full shrink-0 ${meta.dot}`}
                            />
                            <span className="flex-1 min-w-0">
                              <span className="flex items-center justify-between gap-2">
                                <span className="text-sm text-gray-200 font-semibold truncate">
                                  {asset.asset_id}
                                </span>
                                <span className={`text-[10px] shrink-0 ${meta.text}`}>
                                  {meta.label}
                                </span>
                              </span>
                              <span className="block text-[10px] text-gray-500 mt-0.5 truncate">
                                {asset.server_model || '未知型号'} ·{' '}
                                {formatRelative(asset.last_seen_at)}
                                {asset.has_log ? '' : ' · 无日志'}
                              </span>
                            </span>
                          </button>
                          <button
                            type="button"
                            title="从列表删除"
                            onClick={(e) => handleDeleteAsset(asset.asset_id, e)}
                            className="shrink-0 px-2.5 text-gray-600 hover:text-red-400 hover:bg-red-500/10 text-xs self-stretch"
                          >
                            删除
                          </button>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>

            <div className="flex justify-between items-end">
              <span className="text-[10px] text-gray-500 uppercase tracking-widest">
                {selectedId ? `最近日志 · ${selectedId}` : '最近日志'}
              </span>
              <span className="text-[10px] text-gray-400">
                {logsLoading
                  ? '加载中…'
                  : assetLogText
                    ? `${assetLogText.length} 字符`
                    : '—'}
              </span>
            </div>

            <div className="relative flex-1 min-h-[160px] border border-[#333] rounded bg-black/40 overflow-hidden">
              {!selectedId ? (
                <div className="h-full flex items-center justify-center text-xs text-gray-600 px-4 text-center">
                  选择上方资产以查看最近一次采集日志
                </div>
              ) : (
                <pre className="absolute inset-0 m-0 p-3 overflow-auto font-mono text-sm leading-normal whitespace-pre-wrap break-words scrollbar-thin scrollbar-thumb-gray-700">
                  {assetLogText ? (
                    assetHighlighted
                  ) : (
                    <span className="text-gray-600">
                      该资产暂无日志快照（Agent 可能推送了空列表）
                    </span>
                  )}
                </pre>
              )}
            </div>

            <div className="rounded border border-[#333] bg-black/30 px-3 py-2.5 space-y-2 shrink-0">
              <p className="text-[10px] text-gray-500 uppercase tracking-wider">
                一键部署 Agent（Linux）
              </p>
              <div className="flex items-center gap-2">
                <label className="text-[10px] text-gray-500 shrink-0">服务器 ID</label>
                <input
                  type="text"
                  value={deployServerId}
                  onChange={(e) => setDeployServerId(e.target.value)}
                  placeholder="Node-01"
                  className="flex-1 min-w-0 bg-black text-[#e0e0e0] border border-[#333] rounded px-2 py-1 text-xs focus:border-blue-500 focus:outline-none"
                />
              </div>
              <code className="block text-[10px] text-gray-300 break-all leading-relaxed bg-black/50 border border-[#222] rounded px-2 py-2">
                {oneClickCmd}
              </code>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => {
                    navigator.clipboard.writeText(oneClickCmd);
                    showToast('✓ 已复制一键部署命令');
                  }}
                  className="px-2.5 py-1 text-[10px] font-semibold rounded border border-blue-500/50 text-blue-300 hover:bg-blue-500/15"
                >
                  复制命令
                </button>
                <a
                  href={`${httpOrigin}/api/agent/install.sh?server_id=${encodeURIComponent(deployServerId || 'Node-01')}`}
                  className="px-2.5 py-1 text-[10px] font-semibold rounded border border-[#444] text-gray-400 hover:text-gray-200"
                  target="_blank"
                  rel="noreferrer"
                >
                  仅下载脚本
                </a>
              </div>
              <p className="text-[10px] text-gray-600 leading-relaxed">
                在目标 Linux 服务器执行上方命令。若业务机访问不到本机，请把命令里的{' '}
                <span className="text-gray-500">{httpOrigin}</span> 改成中心机局域网
                IP（采集地址应为 {collectUrl}）。
              </p>
              <div className="border-t border-[#222] pt-2 space-y-1.5">
                <p className="text-[10px] text-gray-500 uppercase tracking-wider">
                  一键卸载 Agent
                </p>
                <code className="block text-[10px] text-gray-400 break-all leading-relaxed bg-black/50 border border-[#222] rounded px-2 py-2">
                  {oneClickUninstallCmd}
                </code>
                <button
                  type="button"
                  onClick={() => {
                    navigator.clipboard.writeText(oneClickUninstallCmd);
                    showToast('✓ 已复制一键卸载命令');
                  }}
                  className="px-2.5 py-1 text-[10px] font-semibold rounded border border-red-500/40 text-red-300/90 hover:bg-red-500/10"
                >
                  复制卸载命令
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="relative grid grid-cols-2 gap-2 mt-auto pt-4">
          <button
            onClick={handleDiagnose}
            disabled={isProcessing || !canDiagnose}
            className={`col-span-2 py-3 font-bold rounded flex items-center justify-center gap-2 transition-all shadow-lg ${
              isProcessing || !canDiagnose
                ? 'bg-[#2a2a3a] text-gray-500 cursor-not-allowed'
                : 'bg-blue-600 hover:bg-blue-500 active:scale-95 text-white shadow-blue-900/20'
            }`}
          >
            {isProcessing ? (
              <>
                <span className="animate-spin text-xl">⏳</span> 诊断中...
              </>
            ) : (
              '⚡ 启动 AI 诊断'
            )}
          </button>
          <button
            onClick={handleClear}
            disabled={isProcessing}
            className="py-2 bg-[#2a2a3a] hover:bg-[#3a3a4a] text-xs font-semibold rounded flex items-center justify-center gap-1 text-[#e0e0e0] transition-colors"
          >
            {activeTab === 'auto' ? '取消选择' : '🗑️ 清空日志'}
          </button>
          <button
            onClick={handleExport}
            disabled={exportDisabled}
            className="py-2 bg-[#2a2a3a] hover:bg-[#3a3a4a] text-xs font-semibold rounded flex items-center justify-center gap-1 text-[#e0e0e0] transition-colors disabled:opacity-40"
          >
            📥 导出 TXT
          </button>

          {toast && (
            <div key={toast.key} className="fa-action-toast" role="status">
              {toast.message}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default LogInput;
