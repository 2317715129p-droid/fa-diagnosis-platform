import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { BarChart2, Loader2 } from 'lucide-react';
import ConfidenceBadge from './ConfidenceBadge';
import RemediationChecklist from './RemediationChecklist';
import { translateReport } from '../services/api';
import { TOAST_VISIBLE_MS } from '../utils/logHighlight';
import { parseRemediationSteps, clearChecklistStorage } from '../utils/reportSteps';

const BATCH_SIZE = 10;
const FRAME_THROTTLE_MS = 5;

const UI = {
  zh: {
    emptyTitle: '等待诊断结果...',
    emptyHint: '请在左侧输入日志并点击「启动 AI 诊断」',
    processing: 'AI 正在分析硬件日志...',
    translating: '正在翻译为英文…',
    copy: '📋 复制完整报告',
    archive: '📁 诊断归档',
    archived: '✓ 已归档',
    archiving: '归档中…',
    copied: '✓ 已复制到剪贴板',
    archiveOk: '✓ 归档成功',
    archiveNoId: '暂无报告 ID，无法归档',
    archiveFail: '归档失败',
    translateFail: '翻译失败',
    physicalPrefix: '物理位置：',
    unknownError: '未知错误',
  },
  en: {
    emptyTitle: 'Waiting for diagnosis…',
    emptyHint: 'Paste logs on the left and click Start AI Diagnosis',
    processing: 'AI is analyzing hardware logs…',
    translating: 'Translating to English…',
    copy: '📋 Copy full report',
    archive: '📁 Archive report',
    archived: '✓ Archived',
    archiving: 'Archiving…',
    copied: '✓ Copied to clipboard',
    archiveOk: '✓ Archived successfully',
    archiveNoId: 'No report ID to archive',
    archiveFail: 'Archive failed',
    translateFail: 'Translation failed',
    physicalPrefix: 'Location: ',
    unknownError: 'Unknown error',
  },
};

const ReportPanel = ({
  reportLines = [],
  isStreaming,
  isProcessing,
  reportId = null,
  isArchived = false,
  isArchiving = false,
  onArchive,
}) => {
  const [displayedText, setDisplayedText] = useState('');
  const [lang, setLang] = useState('zh');
  const [toast, setToast] = useState(null);
  const [localArchived, setLocalArchived] = useState(false);
  const [reportEn, setReportEn] = useState(null);
  const [isTranslating, setIsTranslating] = useState(false);
  const [translateError, setTranslateError] = useState(null);
  const scrollRef = useRef(null);
  const rafIdRef = useRef(null);
  const displayedLenRef = useRef(0);
  const lastFrameTimeRef = useRef(0);
  const toastTimerRef = useRef(null);
  const translateReqRef = useRef(0);
  const prevReportRef = useRef({ reportId: null, reportZh: '' });

  const t = UI[lang] || UI.zh;
  const archived = isArchived || localArchived;
  const reportZh = reportLines.join('');

  const showToast = (type, message) => {
    if (toastTimerRef.current) {
      clearTimeout(toastTimerRef.current);
    }
    setToast({ type, message, key: Date.now() });
    toastTimerRef.current = setTimeout(() => {
      setToast(null);
      toastTimerRef.current = null;
    }, TOAST_VISIBLE_MS);
  };

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    };
  }, []);

  useEffect(() => {
    setLocalArchived(false);
  }, [reportId]);

  // New diagnosis → clear English cache and checklist storage
  useEffect(() => {
    if (reportLines.length === 0) {
      if (prevReportRef.current.reportZh) {
        clearChecklistStorage(
          prevReportRef.current.reportId,
          prevReportRef.current.reportZh
        );
      }
      setReportEn(null);
      setTranslateError(null);
      setIsTranslating(false);
      translateReqRef.current += 1;
    }
  }, [reportLines.length]);

  useEffect(() => {
    if (reportZh) {
      prevReportRef.current = { reportId, reportZh };
    }
  }, [reportId, reportZh]);

  // Drop EN cache when Chinese source no longer matches what was translated
  useEffect(() => {
    setReportEn((prev) => {
      if (!prev) return null;
      if (prev._sourceZh === reportZh) return prev;
      return null;
    });
  }, [reportZh]);

  // Typewriter for Chinese stream only
  useEffect(() => {
    if (lang === 'en') return;

    const fullText = reportZh;

    if (rafIdRef.current != null) {
      cancelAnimationFrame(rafIdRef.current);
      rafIdRef.current = null;
    }

    if (!isStreaming) {
      displayedLenRef.current = fullText.length;
      setDisplayedText(fullText);
      return;
    }

    if (fullText.length <= displayedLenRef.current) {
      return;
    }

    lastFrameTimeRef.current = 0;

    const tick = (timestamp) => {
      if (
        lastFrameTimeRef.current &&
        timestamp - lastFrameTimeRef.current < FRAME_THROTTLE_MS
      ) {
        rafIdRef.current = requestAnimationFrame(tick);
        return;
      }
      lastFrameTimeRef.current = timestamp;

      const nextLen = Math.min(
        displayedLenRef.current + BATCH_SIZE,
        fullText.length
      );
      displayedLenRef.current = nextLen;
      setDisplayedText(fullText.slice(0, nextLen));

      if (nextLen < fullText.length) {
        rafIdRef.current = requestAnimationFrame(tick);
      } else {
        rafIdRef.current = null;
      }
    };

    rafIdRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafIdRef.current != null) {
        cancelAnimationFrame(rafIdRef.current);
        rafIdRef.current = null;
      }
    };
  }, [reportZh, isStreaming, lang]);

  useEffect(() => {
    if (reportLines.length === 0) {
      displayedLenRef.current = 0;
      setDisplayedText('');
    }
  }, [reportLines.length]);

  const ensureEnglish = useCallback(async () => {
    if (!reportZh.trim()) return;
    if (reportEn && reportEn._sourceZh === reportZh) {
      setDisplayedText(reportEn.text);
      return;
    }

    const reqId = ++translateReqRef.current;
    setIsTranslating(true);
    setTranslateError(null);
    try {
      const data = await translateReport(reportZh);
      if (reqId !== translateReqRef.current) return;
      const cached = { text: data.report_en, _sourceZh: reportZh };
      setReportEn(cached);
      setDisplayedText(data.report_en);
    } catch (err) {
      if (reqId !== translateReqRef.current) return;
      const msg = err?.message || t.unknownError;
      setTranslateError(msg);
      showToast('error', `${t.translateFail}: ${msg}`);
      setLang('zh');
      setDisplayedText(reportZh);
    } finally {
      if (reqId === translateReqRef.current) {
        setIsTranslating(false);
      }
    }
  }, [reportZh, reportEn, t.translateFail, t.unknownError]);

  // Switch language display
  useEffect(() => {
    if (lang === 'zh') {
      if (!isStreaming) {
        setDisplayedText(reportZh);
      }
      return;
    }
    if (lang === 'en' && !isStreaming && reportZh.trim()) {
      ensureEnglish();
    }
  }, [lang, isStreaming, reportZh, ensureEnglish]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [displayedText, isTranslating]);

  const handleCopy = () => {
    navigator.clipboard.writeText(displayedText);
    showToast('success', t.copied);
  };

  const handleArchiveClick = async () => {
    if (archived || isArchiving) return;
    if (reportId == null) {
      showToast('error', t.archiveNoId);
      return;
    }
    try {
      await onArchive?.(reportId);
      setLocalArchived(true);
      showToast('success', t.archiveOk);
    } catch (err) {
      showToast('error', `${t.archiveFail}: ${err?.message || t.unknownError}`);
    }
  };

  const handleLangChange = (next) => {
    if (next === lang) return;
    if (next === 'en' && (isStreaming || isProcessing || !reportZh.trim())) {
      return;
    }
    setLang(next);
  };

  const renderParagraph = ({ children }) => {
    let isPhysicalLocation = false;

    React.Children.forEach(children, (child) => {
      if (typeof child === 'string') {
        const hasKeyword = /CPU|DIMM|Channel/i.test(child);
        const hasNumber = /\d/.test(child);
        if (hasKeyword && hasNumber) {
          isPhysicalLocation = true;
        }
      }
    });

    if (isPhysicalLocation) {
      return (
        <div className="bg-red-500/10 border-l-4 border-red-500 p-4 mb-6">
          <p className="text-[#ff4444] text-xl font-bold uppercase">
            {t.physicalPrefix}
            {children}
          </p>
          <p className="text-xs text-red-400/70 mt-1 uppercase tracking-tighter italic">
            Suggested action: Inspect & Reseat
          </p>
        </div>
      );
    }

    return <p className="text-sm text-gray-300 leading-relaxed mb-6">{children}</p>;
  };

  const remediationSteps = useMemo(
    () => parseRemediationSteps(displayedText, lang),
    [displayedText, lang]
  );

  const showChecklist =
    !isStreaming && !isTranslating && remediationSteps.length > 0;

  const showEmpty = !isProcessing && !displayedText && !isTranslating;
  const showProcessing = isProcessing && !displayedText && !isTranslating;

  return (
    <div className="flex flex-col h-full bg-[#0a0a1a] relative overflow-hidden">
      <div className="flex items-center justify-between px-6 py-2 border-b border-[#333] bg-[#0d0d26]/50">
        <div className="flex gap-4 items-center">
          <button
            onClick={() => handleLangChange('zh')}
            className={`text-xs font-bold pb-1 ${
              lang === 'zh' ? 'text-white border-b-2 border-white' : 'text-gray-500 hover:text-gray-300'
            }`}
          >
            🇨🇳 中文报告
          </button>
          <button
            onClick={() => handleLangChange('en')}
            disabled={isStreaming || isProcessing || !reportZh.trim() || isTranslating}
            className={`text-xs font-bold pb-1 disabled:opacity-40 disabled:cursor-not-allowed ${
              lang === 'en' ? 'text-white border-b-2 border-white' : 'text-gray-500 hover:text-gray-300'
            }`}
          >
            🇬🇧 English
          </button>
          {archived && (
            <span className="ml-2 text-[10px] font-bold tracking-wide uppercase px-2.5 py-1 rounded-full bg-green-500/15 text-green-400 border border-green-500/40">
              {t.archived}
            </span>
          )}
        </div>

        {displayedText && !isTranslating && (
          <ConfidenceBadge
            reportText={lang === 'zh' ? reportZh : displayedText}
            isStreaming={isStreaming}
            reportId={reportId}
            lang={lang}
          />
        )}
      </div>

      <div
        ref={scrollRef}
        className="flex-1 p-8 overflow-y-auto scrollbar-thin scrollbar-thumb-gray-700"
      >
        {showEmpty && (
          <div className="h-full flex flex-col items-center justify-center text-gray-500 space-y-4">
            <BarChart2 size={64} className="opacity-50" />
            <h3 className="text-xl font-medium text-gray-400">{t.emptyTitle}</h3>
            <p className="text-sm">{t.emptyHint}</p>
          </div>
        )}

        {(showProcessing || isTranslating) && (
          <div className="h-full flex flex-col items-center justify-center text-blue-400 space-y-4">
            <Loader2 size={48} className="animate-spin" />
            <p className="text-lg animate-pulse tracking-wide font-semibold">
              {isTranslating ? t.translating : t.processing}
            </p>
            {translateError && (
              <p className="text-xs text-red-400 max-w-md text-center">{translateError}</p>
            )}
          </div>
        )}

        {displayedText && !isTranslating && (
          <div className="max-w-3xl mx-auto pb-24">
            <div className="flex items-center gap-4 mb-8">
              <div className="h-px flex-1 bg-gradient-to-r from-transparent to-[#333]"></div>
              <h2 className="text-sm tracking-[0.3em] uppercase text-gray-500">
                Diagnosis Report
              </h2>
              <div className="h-px flex-1 bg-gradient-to-l from-transparent to-[#333]"></div>
            </div>

            {showChecklist && (
              <RemediationChecklist
                steps={remediationSteps}
                reportId={reportId}
                reportText={displayedText}
                lang={lang}
                disabled={isStreaming || isTranslating}
              />
            )}

            <div className="prose prose-invert max-w-none">
              <ReactMarkdown
                remarkPlugins={[remarkGfm]}
                components={{
                  h3: ({ node, ...props }) => (
                    <h3 className="text-blue-400 text-lg mb-2 mt-6" {...props} />
                  ),
                  p: renderParagraph,
                  pre: ({ node, ...props }) => (
                    <pre
                      className="bg-[#1a1a2e] p-4 rounded border border-[#333] overflow-x-auto my-4"
                      {...props}
                    />
                  ),
                  code: ({ node, inline, ...props }) =>
                    inline ? (
                      <code
                        className="bg-[#1a1a2e] px-1.5 py-0.5 rounded text-blue-300 font-mono text-[0.9em]"
                        {...props}
                      />
                    ) : (
                      <code {...props} />
                    ),
                  table: ({ node, ...props }) => (
                    <table
                      className="w-full text-sm border-collapse border border-[#333] mb-6"
                      {...props}
                    />
                  ),
                  thead: ({ node, ...props }) => (
                    <thead className="bg-[#1a1a2e]" {...props} />
                  ),
                  th: ({ node, ...props }) => (
                    <th className="border border-[#333] p-2 text-left" {...props} />
                  ),
                  td: ({ node, ...props }) => (
                    <td className="border border-[#333] p-2" {...props} />
                  ),
                  ul: ({ node, ...props }) => (
                    <ul
                      className="list-disc list-inside text-sm text-gray-300 space-y-2 mb-6"
                      {...props}
                    />
                  ),
                  li: ({ node, ...props }) => <li {...props} />,
                }}
              >
                {displayedText}
              </ReactMarkdown>

              {isStreaming && lang === 'zh' && (
                <span className="inline-block w-2 h-4 bg-blue-400 animate-pulse ml-1 align-middle" />
              )}
            </div>
          </div>
        )}
      </div>

      {displayedText && !isTranslating && (
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-40">
          <div className="relative flex items-center gap-3 p-2 bg-[#1a1a2e]/80 backdrop-blur border border-white/10 rounded-full shadow-2xl">
            {toast && toast.type === 'success' && (
              <div key={toast.key} className="fa-action-toast" role="status">
                {toast.message}
              </div>
            )}
            <button
              onClick={handleCopy}
              className="px-6 py-2 bg-blue-500/20 hover:bg-blue-500 text-blue-400 hover:text-white text-xs font-bold rounded-full border border-blue-500/50 transition-all flex items-center gap-2"
            >
              {t.copy}
            </button>
            <button
              onClick={handleArchiveClick}
              disabled={archived || isArchiving || reportId == null}
              className={`px-6 py-2 text-xs font-bold rounded-full border transition-all flex items-center gap-2 ${
                archived
                  ? 'bg-green-500/30 text-green-300 border-green-500/60 cursor-not-allowed opacity-80'
                  : isArchiving || reportId == null
                    ? 'bg-gray-500/20 text-gray-500 border-gray-600 cursor-not-allowed'
                    : 'bg-green-500/20 hover:bg-green-500 text-green-400 hover:text-white border-green-500/50'
              }`}
            >
              {archived ? t.archived : isArchiving ? t.archiving : t.archive}
            </button>
          </div>
        </div>
      )}

      {toast && toast.type === 'error' && (
        <div
          key={toast.key}
          className="fa-toast absolute bottom-20 left-1/2 -translate-x-1/2 px-4 py-2 rounded-lg shadow-lg flex items-center gap-2 border bg-red-900/90 text-red-100 border-red-500/50"
        >
          <span className="text-red-300">✕</span>
          {toast.message}
        </div>
      )}
    </div>
  );
};

export default ReportPanel;
