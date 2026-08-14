import React, { useEffect, useState } from 'react';

const STREAK_KEY = 'fa_low_conf_streak';
const LAST_ID_KEY = 'fa_low_conf_last_report_id';

const LEVEL_MAP = {
  高: 'high',
  中: 'medium',
  低: 'low',
  High: 'high',
  Medium: 'medium',
  Med: 'medium',
  Low: 'low',
};

/** 从报告正文解析置信度，返回 canonical: high | medium | low */
export function extractConfidence(reportText = '') {
  const zh = reportText.match(/置信度[：:\s]*([高中低])/);
  if (zh) return LEVEL_MAP[zh[1]] || null;

  const en = reportText.match(
    /Confidence(?:\s*Assessment)?[：:\s]*\*?\*?(High|Medium|Med|Low)\b/i
  );
  if (en) {
    const key = en[1].charAt(0).toUpperCase() + en[1].slice(1).toLowerCase();
    if (key === 'Med') return 'medium';
    return LEVEL_MAP[key] || LEVEL_MAP[en[1]] || null;
  }
  return null;
}

const ConfidenceBadge = ({
  reportText = '',
  isStreaming = false,
  reportId = null,
  lang = 'zh',
}) => {
  const level = extractConfidence(reportText);
  const [lowStreak, setLowStreak] = useState(() =>
    Number(sessionStorage.getItem(STREAK_KEY) || 0)
  );

  useEffect(() => {
    if (isStreaming || !level) return;

    const idKey = reportId != null ? String(reportId) : `hash:${reportText.length}`;
    if (sessionStorage.getItem(LAST_ID_KEY) === idKey) {
      setLowStreak(Number(sessionStorage.getItem(STREAK_KEY) || 0));
      return;
    }

    let streak = Number(sessionStorage.getItem(STREAK_KEY) || 0);
    if (level === 'low') {
      streak += 1;
    } else {
      streak = 0;
    }
    sessionStorage.setItem(STREAK_KEY, String(streak));
    sessionStorage.setItem(LAST_ID_KEY, idKey);
    setLowStreak(streak);
  }, [isStreaming, level, reportId, reportText]);

  if (!level) return null;

  const labels =
    lang === 'en'
      ? { high: 'High', medium: 'Medium', low: 'Low', prefix: 'Confidence: ' }
      : { high: '高', medium: '中', low: '低', prefix: '置信度：' };

  let config = {
    bg: 'bg-gray-500/20 border-gray-500/40 text-gray-400',
    icon: '',
    label: lang === 'en' ? 'Unknown' : '未知',
  };

  switch (level) {
    case 'high':
      config = {
        bg: 'bg-green-500/20 border-green-500/40 text-green-400',
        icon: '✅',
        label: labels.high,
      };
      break;
    case 'medium':
      config = {
        bg: 'bg-yellow-500/20 border-yellow-500/40 text-yellow-500',
        icon: '⚠️',
        label: labels.medium,
      };
      break;
    case 'low':
      config = {
        bg: 'bg-red-500/20 border-red-500/40 text-red-500',
        icon: '❌',
        label: labels.low,
      };
      break;
    default:
      return null;
  }

  const confirmedLow = level === 'low' && lowStreak >= 3;
  const suggestRetry = level === 'low' && !isStreaming && lowStreak > 0 && lowStreak < 3;

  return (
    <div className="flex flex-col items-end gap-1 max-w-[260px]">
      <div className={`flex items-center gap-2 px-3 py-1 border rounded ${config.bg}`}>
        <span className="text-xs font-bold">
          {config.icon} {labels.prefix}
          {config.label}
          {level === 'low' && lowStreak > 0 ? (
            <span className="ml-1 opacity-70 font-normal">({lowStreak}/3)</span>
          ) : null}
        </span>
      </div>

      {suggestRetry && (
        <p className="text-[10px] text-red-400/80 leading-snug text-right">
          {lang === 'en'
            ? `Suggest re-running diagnosis (low confidence ${lowStreak}/3)`
            : `建议再识别一次（连续低置信度 ${lowStreak}/3）`}
        </p>
      )}

      {confirmedLow && !isStreaming && (
        <p className="text-[10px] text-red-300/90 leading-snug text-right">
          {lang === 'en'
            ? 'Low confidence 3 times in a row — result can be treated as Low'
            : '连续 3 次均为低置信度，可确认结果为低'}
        </p>
      )}
    </div>
  );
};

export default ConfidenceBadge;
