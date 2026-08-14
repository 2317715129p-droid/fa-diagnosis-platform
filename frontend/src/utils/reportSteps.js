/**
 * Parse numbered remediation steps from FA diagnosis report Markdown.
 */

const ZH_SECTION = /【工程处置建议】/i;
const EN_SECTION = /engineering\s+remediation|remediation\s+checklist|\bremediation\b/i;

const NEXT_SECTION = /^(?:###\s*|【置信度|confidence\s+assessment)/i;

const STEP_LINE = /^\s*(\d+)\.\s*(.+)$/;

/**
 * Infer step phase from text prefix.
 * @param {string} text
 * @returns {'emergency'|'root_cause'|'verify'|undefined}
 */
function inferPhase(text) {
  const lower = text.toLowerCase();
  if (/紧急|emergency|urgent/i.test(lower)) return 'emergency';
  if (/根治|root\s*cause|radical|permanent/i.test(lower)) return 'root_cause';
  if (/验证|verify|validation|test/i.test(lower)) return 'verify';
  return undefined;
}

/**
 * Extract remediation section body from full report text.
 * @param {string} reportText
 * @param {'zh'|'en'} lang
 * @returns {string}
 */
function extractRemediationSection(reportText, lang) {
  if (!reportText || !reportText.trim()) return '';

  const lines = reportText.split('\n');
  let inSection = false;
  const body = [];

  const sectionRe = lang === 'en' ? EN_SECTION : ZH_SECTION;
  // Also accept either language header when lang is zh (reports may mix)
  const altRe = lang === 'en' ? ZH_SECTION : EN_SECTION;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!inSection) {
      if (sectionRe.test(trimmed) || altRe.test(trimmed)) {
        inSection = true;
      }
      continue;
    }
    if (NEXT_SECTION.test(trimmed)) {
      break;
    }
    body.push(line);
  }

  return body.join('\n');
}

/**
 * @param {string} reportText
 * @param {'zh'|'en'} [lang='zh']
 * @returns {Array<{ id: string, text: string, phase?: string }>}
 */
export function parseRemediationSteps(reportText, lang = 'zh') {
  const section = extractRemediationSection(reportText, lang);
  if (!section.trim()) return [];

  const steps = [];
  for (const line of section.split('\n')) {
    const m = STEP_LINE.exec(line);
    if (!m) continue;
    const text = m[2].trim();
    if (!text) continue;
    steps.push({
      id: String(m[1]),
      text,
      phase: inferPhase(text),
    });
  }
  return steps;
}

/** sessionStorage key for checklist state */
export function checklistStorageKey(reportId, reportText) {
  if (reportId != null) return `fa_checklist_${reportId}`;
  const len = (reportText || '').length;
  return `fa_checklist_hash_${len}`;
}

/** Remove stored checklist when starting a new diagnosis */
export function clearChecklistStorage(reportId, reportText) {
  try {
    sessionStorage.removeItem(checklistStorageKey(reportId, reportText));
  } catch {
    // ignore quota / private mode
  }
}
