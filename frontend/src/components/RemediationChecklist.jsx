import React, { useState, useEffect, useCallback } from 'react';
import { checklistStorageKey } from '../utils/reportSteps';

const PHASE_LABELS = {
  zh: {
    emergency: '紧急',
    root_cause: '根治',
    verify: '验证',
    title: '工程处置清单',
    progress: (done, total) => `${done}/${total} 已完成`,
  },
  en: {
    emergency: 'Emergency',
    root_cause: 'Root fix',
    verify: 'Verify',
    title: 'Remediation Checklist',
    progress: (done, total) => `${done}/${total} completed`,
  },
};

function loadChecked(storageKey) {
  try {
    const raw = sessionStorage.getItem(storageKey);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return typeof parsed === 'object' && parsed !== null ? parsed : {};
  } catch {
    return {};
  }
}

function saveChecked(storageKey, checked) {
  try {
    sessionStorage.setItem(storageKey, JSON.stringify(checked));
  } catch {
    // ignore
  }
}

const RemediationChecklist = ({
  steps = [],
  reportId = null,
  reportText = '',
  lang = 'zh',
  disabled = false,
}) => {
  const labels = PHASE_LABELS[lang] || PHASE_LABELS.zh;
  const storageKey = checklistStorageKey(reportId, reportText);

  const [checked, setChecked] = useState(() => loadChecked(storageKey));

  // Reload when report identity changes
  useEffect(() => {
    setChecked(loadChecked(storageKey));
  }, [storageKey]);

  const toggle = useCallback(
    (stepId) => {
      if (disabled) return;
      setChecked((prev) => {
        const next = { ...prev, [stepId]: !prev[stepId] };
        saveChecked(storageKey, next);
        return next;
      });
    },
    [disabled, storageKey]
  );

  if (!steps.length) return null;

  const doneCount = steps.filter((s) => checked[s.id]).length;

  return (
    <div className="mb-8 rounded-lg border border-[#333] bg-[#0d0d1a]/80 overflow-hidden">
      <div className="flex items-center justify-between px-4 py-3 border-b border-[#333] bg-[#1a1a2e]/50">
        <h3 className="text-sm font-bold text-green-400 tracking-wide">
          ✓ {labels.title}
        </h3>
        <span className="text-[10px] text-gray-500 uppercase tracking-wider">
          {labels.progress(doneCount, steps.length)}
        </span>
      </div>

      <ul className="divide-y divide-[#222]">
        {steps.map((step) => {
          const isChecked = Boolean(checked[step.id]);
          const phaseLabel = step.phase ? labels[step.phase] : null;

          return (
            <li key={step.id}>
              <label
                className={`flex items-start gap-3 px-4 py-3 cursor-pointer transition-colors hover:bg-white/[0.02] ${
                  disabled ? 'opacity-60 cursor-not-allowed' : ''
                }`}
              >
                <input
                  type="checkbox"
                  checked={isChecked}
                  disabled={disabled}
                  onChange={() => toggle(step.id)}
                  className="mt-0.5 h-4 w-4 shrink-0 accent-green-500 cursor-pointer disabled:cursor-not-allowed"
                />
                <span className="flex-1 min-w-0">
                  <span className="flex items-center gap-2 flex-wrap mb-0.5">
                    <span className="text-[10px] font-mono text-gray-500">
                      #{step.id}
                    </span>
                    {phaseLabel && (
                      <span className="text-[9px] uppercase tracking-wide px-1.5 py-0.5 rounded border border-[#444] text-gray-400">
                        {phaseLabel}
                      </span>
                    )}
                  </span>
                  <span
                    className={`text-sm leading-relaxed block ${
                      isChecked
                        ? 'text-green-600/70 line-through'
                        : 'text-gray-300'
                    }`}
                  >
                    {step.text}
                  </span>
                </span>
              </label>
            </li>
          );
        })}
      </ul>
    </div>
  );
};

export default RemediationChecklist;
