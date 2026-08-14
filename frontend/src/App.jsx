import React, { useState } from 'react';
import LogInput from './components/LogInput';
import ReportPanel from './components/ReportPanel';
import { useWebSocket } from './hooks/useWebSocket';

const App = () => {
  const {
    isConnected,
    reportLines,
    isStreaming,
    isProcessing,
    error,
    reportId,
    isArchived,
    isArchiving,
    archiveReport,
    sendDiagnosis,
  } = useWebSocket();

  const [leftWidth, setLeftWidth] = useState(40); // percentage

  // Simple drag-to-resize implementation
  const startResizing = () => {
    const handleMouseMove = (mouseMoveEvent) => {
      const newWidth = (mouseMoveEvent.clientX / window.innerWidth) * 100;
      if (newWidth > 25 && newWidth < 75) {
        setLeftWidth(newWidth);
      }
    };

    const handleMouseUp = () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
  };

  const handleDiagnose = (logText, serverId) => {
    sendDiagnosis(logText, serverId);
  };

  const handleArchive = async () => {
    return archiveReport();
  };

  return (
    <div className="flex flex-col h-screen bg-[#0a0a1a] text-[#e0e0e0] font-mono overflow-hidden select-none">
      {/* Header */}
      <header className="flex items-center justify-between px-6 py-4 border-b border-[#333] bg-[#0d0d26] shadow-lg shadow-black/50">
        <div className="flex items-center gap-3">
          <span className="text-2xl">🔧</span>
          <h1 className="text-xl font-bold tracking-tight text-white">
            FA智能诊断系统{' '}
            <span className="text-xs font-normal text-blue-400 bg-blue-400/10 px-2 py-0.5 rounded border border-blue-400/30 align-middle">
              MVP
            </span>
          </h1>
        </div>

        <div className="flex items-center gap-4">
          <div
            className={`flex items-center gap-2 px-3 py-1 border rounded-full ${
              isConnected
                ? 'bg-green-500/10 border-green-500/30'
                : 'bg-red-500/10 border-red-500/30'
            }`}
          >
            <span
              className={`w-2 h-2 rounded-full ${
                isConnected
                  ? 'bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.8)]'
                  : 'bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.8)]'
              }`}
            ></span>
            <span
              className={`text-xs font-semibold ${
                isConnected ? 'text-green-400' : 'text-red-400'
              }`}
            >
              WebSocket {isConnected ? '已连接' : '未连接'}
            </span>
          </div>
          <div className="text-xs opacity-50">v1.2.0-stable</div>
        </div>
      </header>

      {/* Main Content - Dual Column */}
      <main className="flex-1 flex overflow-hidden">
        <div
          style={{ width: `${leftWidth}%`, minWidth: '400px' }}
          className="flex flex-col h-full shrink-0 border-r border-[#333]"
        >
          <LogInput onDiagnose={handleDiagnose} isProcessing={isProcessing} />
        </div>

        <div
          className="w-1 bg-transparent hover:bg-blue-500 cursor-col-resize shrink-0 transition-colors z-10"
          onMouseDown={startResizing}
          style={{ marginLeft: '-2px', marginRight: '-2px' }}
        />

        <div
          style={{ flex: 1, minWidth: '500px' }}
          className="flex flex-col h-full bg-[#0a0a1a]"
        >
          {error && (
            <div className="m-4 p-4 bg-red-900/20 border border-red-500/50 rounded text-red-400 flex items-center justify-between">
              <span className="text-sm">{error}</span>
              <button
                onClick={() => window.location.reload()}
                className="text-xs font-semibold underline hover:text-red-300"
              >
                刷新重试
              </button>
            </div>
          )}

          <ReportPanel
            reportLines={reportLines}
            isStreaming={isStreaming}
            isProcessing={isProcessing}
            reportId={reportId}
            isArchived={isArchived}
            isArchiving={isArchiving}
            onArchive={handleArchive}
          />
        </div>
      </main>
    </div>
  );
};

export default App;
