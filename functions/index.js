const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { genkit } = require('genkit');
const { googleAI } = require('@genkit-ai/googleai');
const {
  FIRESTORE_DATABASE_ID,
  USE_DEFAULT_FIRESTORE_DATABASE,
} = require('./firestore_target');

initializeApp();

const db = USE_DEFAULT_FIRESTORE_DATABASE
  ? getFirestore()
  : getFirestore(FIRESTORE_DATABASE_ID);

const HANDBOOK_MODEL = 'googleai/gemini-2.5-flash-lite';
const OSA_MODEL = 'googleai/gemini-2.5-flash-lite';
const MAX_CONTEXT_CHARS = 16000;
const MAX_SOURCE_CHARS = 1200;
const MAX_IN_QUERY_VALUES = 10;
const INVALID_FCM_TOKEN_ERRORS = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function normalizeString(value) {
  return (value ?? '').toString().trim();
}

function normalizeLower(value) {
  return normalizeString(value).toLowerCase();
}

function toStringMap(raw) {
  if (!raw || typeof raw !== 'object') return {};
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    out[key] = normalizeString(value);
  }
  return out;
}

function orderValue(value) {
  if (typeof value === 'number') return Math.trunc(value);
  return 0;
}

function scoreEntry(entry, question) {
  const q = normalizeLower(question);
  if (!q) return 0;
  const tokens = q.split(/[^a-z0-9]+/).filter((t) => t.length >= 3);
  let score = 0;
  if (entry.searchable.includes(q)) score += 30;
  for (const token of tokens) {
    if (entry.searchable.includes(token)) score += 4;
  }
  return score;
}

async function generateText(model, prompt) {
  const apiKey = normalizeString(
    process.env.GEMINI_API_KEY || process.env.GOOGLE_GENAI_API_KEY,
  );
  if (!apiKey) {
    throw new HttpsError(
      'failed-precondition',
      'Missing GEMINI_API_KEY function secret.',
    );
  }
  const ai = genkit({
    plugins: [googleAI({ apiKey })],
  });
  const response = await ai.generate({
    model,
    prompt,
    config: {
      temperature: 0.2,
    },
  });
  return (
    response?.text ??
    response?.outputText ??
    response?.output?.text ??
    ''
  ).toString().trim();
}

async function getActiveVersionId() {
  const hbCurrentSnap = await db.collection('hb_version').doc('current').get();
  const versionId = normalizeString(hbCurrentSnap.data()?.activeVersionId);
  if (!versionId) {
    throw new HttpsError(
      'failed-precondition',
      'Missing active handbook version id in hb_version/current.activeVersionId',
    );
  }

  const versionSnap = await db.collection('hb_version').doc(versionId).get();
  if (!versionSnap.exists) {
    throw new HttpsError(
      'failed-precondition',
      `Active handbook version document not found: hb_version/${versionId}`,
    );
  }

  const status = normalizeLower(versionSnap.data()?.status);
  const normalizedStatus = status === 'active' ? 'active' : 'inactive';
  if (normalizedStatus !== 'active') {
    await db.collection('hb_version').doc(versionId).set({
      status: 'active',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return versionId;
}

function sectionSort(a, b) {
  const orderCompare = orderValue(a.sortOrder) - orderValue(b.sortOrder);
  if (orderCompare !== 0) return orderCompare;
  const titleCompare = normalizeString(a.title).localeCompare(
    normalizeString(b.title),
  );
  if (titleCompare !== 0) return titleCompare;
  return normalizeString(a.id).localeCompare(normalizeString(b.id));
}

function flattenSectionRows(sections) {
  const byParent = new Map();
  const byId = new Map();
  for (const section of sections) {
    const parentId = normalizeString(section.parentId);
    if (!byParent.has(parentId)) byParent.set(parentId, []);
    byParent.get(parentId).push(section);
    byId.set(section.id, section);
  }

  for (const children of byParent.values()) {
    children.sort(sectionSort);
  }

  const roots = sections
    .filter((section) => {
      const parentId = normalizeString(section.parentId);
      return !parentId || !byId.has(parentId);
    })
    .sort(sectionSort);

  const rows = [];
  const visited = new Set();

  const walk = (section, depth) => {
    if (!section || visited.has(section.id)) return;
    visited.add(section.id);
    rows.push({ section, depth });
    const children = byParent.get(section.id) || [];
    for (const child of children) {
      walk(child, depth + 1);
    }
  };

  for (const root of roots) {
    walk(root, 0);
  }

  for (const section of sections.sort(sectionSort)) {
    if (!visited.has(section.id)) {
      walk(section, 0);
    }
  }

  return rows;
}

function buildDisplayCodeBySectionId(rows) {
  const codeBySectionId = new Map();
  const levelCounters = [];

  for (const row of rows) {
    const section = row.section || {};
    if (section.useSectionNumbering === false) {
      codeBySectionId.set(section.id, '');
      continue;
    }

    const depth = row.depth < 0 ? 0 : row.depth;
    while (levelCounters.length <= depth) {
      levelCounters.push(0);
    }
    if (levelCounters.length > depth + 1) {
      levelCounters.splice(depth + 1);
    }
    levelCounters[depth] += 1;

    codeBySectionId.set(section.id, levelCounters.slice(0, depth + 1).join('.'));
  }

  return codeBySectionId;
}

function extractTextFromTablePayload(raw) {
  const payload = normalizeString(raw);
  if (!payload) return '';

  try {
    const decoded = JSON.parse(payload);
    if (decoded && typeof decoded === 'object') {
      const headers = Array.isArray(decoded.headers)
        ? decoded.headers.map((value) => normalizeString(value))
        : [];
      const rows = Array.isArray(decoded.rows)
        ? decoded.rows
            .map((rawRow) => {
              if (!Array.isArray(rawRow)) return [];
              return rawRow.map((value) => normalizeString(value));
            })
        : [];

      const lines = [];
      const headerLine = headers.filter(Boolean).join(' | ');
      if (headerLine) lines.push(headerLine);
      for (const row of rows) {
        const line = row.filter(Boolean).join(' | ');
        if (line) lines.push(line);
      }
      return lines.join('\n').trim();
    }
  } catch (_) {
    // best-effort only
  }

  return payload;
}

function extractTextFromQuillOps(ops) {
  if (!Array.isArray(ops)) return '';
  const parts = [];

  for (const rawOp of ops) {
    if (!rawOp || typeof rawOp !== 'object') continue;
    const insert = rawOp.insert;
    if (typeof insert === 'string') {
      parts.push(insert);
      continue;
    }
    if (!insert || typeof insert !== 'object') continue;

    const tablePayload = normalizeString(insert['x-embed-table'] || insert.table);
    if (tablePayload) {
      const tableText = extractTextFromTablePayload(tablePayload);
      if (tableText) parts.push(`\n${tableText}\n`);
      continue;
    }

    const embedCaption = normalizeString(
      insert.caption || insert.alt || insert.title || insert.url,
    );
    if (embedCaption) parts.push(embedCaption);
  }

  return parts.join('').replace(/\n{3,}/g, '\n\n').trim();
}

function extractContentText(rawContent) {
  if (typeof rawContent === 'string') {
    const trimmed = rawContent.trim();
    if (!trimmed) return '';
    try {
      const decoded = JSON.parse(trimmed);
      if (Array.isArray(decoded)) {
        return extractTextFromQuillOps(decoded);
      }
      if (decoded && typeof decoded === 'object' && Array.isArray(decoded.ops)) {
        return extractTextFromQuillOps(decoded.ops);
      }
    } catch (_) {
      // Plain text fallback.
    }
    return trimmed;
  }

  if (Array.isArray(rawContent)) {
    return extractTextFromQuillOps(rawContent);
  }

  if (rawContent && typeof rawContent === 'object' && Array.isArray(rawContent.ops)) {
    return extractTextFromQuillOps(rawContent.ops);
  }

  return '';
}

async function loadContentMapBySection(versionId) {
  const collections = ['hb_contents', 'hb_content'];
  const contentBySectionId = new Map();

  for (const collectionName of collections) {
    let snap;
    try {
      snap = await db
        .collection(collectionName)
        .where('versionId', '==', versionId)
        .get();
    } catch (error) {
      console.error(`failed reading ${collectionName} for handbook ai`, error);
      continue;
    }
    if (!snap || snap.empty) continue;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const sectionId = normalizeString(data.sectionId) || doc.id;
      if (!sectionId || contentBySectionId.has(sectionId)) continue;

      const rawContent = data.content ?? data.publishedContent ?? data.body ?? '';
      const plainText = extractContentText(rawContent);
      if (!plainText) continue;

      contentBySectionId.set(sectionId, plainText);
    }

    if (contentBySectionId.size > 0) break;
  }

  return contentBySectionId;
}

async function loadHandbookEntries() {
  const versionId = await getActiveVersionId();

  const sectionSnap = await db
    .collection('hb_section')
    .where('versionId', '==', versionId)
    .get();

  const sections = sectionSnap.docs
    .map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        parentId: normalizeString(data.parentId),
        title: normalizeString(data.title) || '(Untitled entry)',
        code: normalizeString(data.code),
        sortOrder: orderValue(data.sortOrder),
        isVisible: data.isVisible !== false,
        status: normalizeLower(data.status),
        useSectionNumbering: data.useSectionNumbering !== false,
      };
    })
    .filter((section) => section.isVisible);

  if (sections.length === 0) return [];

  const rows = flattenSectionRows(sections);
  const codeBySectionId = buildDisplayCodeBySectionId(rows);
  const contentBySectionId = await loadContentMapBySection(versionId);

  const entries = [];
  for (const row of rows) {
    const section = row.section;
    const content = normalizeString(contentBySectionId.get(section.id));
    if (!content) continue;

    const displayCode = normalizeString(
      codeBySectionId.get(section.id) || section.code,
    );
    const source = displayCode
      ? `${displayCode} ${section.title}`.trim()
      : section.title;

    entries.push({
      sectionId: section.id,
      versionId,
      sectionCode: displayCode,
      sectionTitle: section.title,
      topicCode: '',
      topicTitle: '',
      content,
      searchable: `${displayCode} ${section.title} ${content}`.toLowerCase(),
      source,
    });
  }

  return entries;
}

function buildHandbookPrompt(question, entries) {
  const ranked = [...entries].sort((a, b) => scoreEntry(b, question) - scoreEntry(a, question));
  const picked = ranked.slice(0, 8);

  let context = '';
  const usedEntries = [];
  for (let i = 0; i < picked.length; i += 1) {
    const entry = picked[i];
    const body = entry.content.length > MAX_SOURCE_CHARS
      ? `${entry.content.slice(0, MAX_SOURCE_CHARS)}...`
      : entry.content;
    const sectionLine = [entry.sectionCode, entry.sectionTitle]
      .filter((value) => normalizeString(value))
      .join(' ')
      .trim();
    const topicLine = [entry.topicCode, entry.topicTitle]
      .filter((value) => normalizeString(value))
      .join(' ')
      .trim();
    const block = `[Source ${i + 1}]
Section: ${sectionLine || normalizeString(entry.sectionTitle)}
${topicLine ? `Entry: ${topicLine}\n` : ''}Content:
${body}

    `;
    if (context.length + block.length > MAX_CONTEXT_CHARS) break;
    context += block;
    usedEntries.push(entry);
  }

  const seenSourceRef = new Set();
  const sourceRefs = [];
  const sourceLabels = [];
  for (const entry of usedEntries) {
    const sectionId = normalizeString(entry.sectionId);
    const versionId = normalizeString(entry.versionId);
    const label = normalizeString(entry.source);
    const dedupeKey = `${sectionId}|${versionId}|${label}`;
    if (!label || seenSourceRef.has(dedupeKey)) continue;
    seenSourceRef.add(dedupeKey);
    sourceLabels.push(label);
    sourceRefs.push({
      label,
      sectionId,
      versionId,
      excerpt: buildHandbookSourceExcerpt(entry.content, question),
    });
  }

  return {
    prompt: `You are the official student handbook assistant.
Answer ONLY from the handbook context.
If not in context, explicitly say it is not stated.
Be clear, practical, and student-friendly.

Output rules:
1) Plain text only.
2) Do NOT use markdown symbols like *, #, _, -, or backticks as formatting.
3) Use this exact structure:
Short Answer
<direct explanation>

Key Details
• <important rules>
• <conditions>
• <consequences>

What You Should Do
<helpful advice>

Source
<handbook section reference>
4) In "Key Details", use 2 to 4 bullet points, each starting with "• ".
5) Keep response concise and readable.

Question:
${question}

Handbook context:
${context.trim()}`,
    sources: [...new Set(sourceLabels)],
    sourceRefs,
  };
}

function buildHandbookSourceExcerpt(content, question) {
  const cleanContent = normalizeString(content).replace(/\s+/g, ' ').trim();
  if (!cleanContent) return '';

  const cleanQuestion = normalizeLower(question);
  const tokens = cleanQuestion
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 4);

  const lowerContent = cleanContent.toLowerCase();
  let hitIndex = -1;
  for (const token of tokens) {
    const idx = lowerContent.indexOf(token);
    if (idx >= 0) {
      hitIndex = idx;
      break;
    }
  }
  if (hitIndex < 0) {
    hitIndex = 0;
  }

  const windowSize = 220;
  const contextBefore = 80;
  const start = hitIndex > contextBefore ? hitIndex - contextBefore : 0;
  const end = Math.min(cleanContent.length, start + windowSize);
  let excerpt = cleanContent.slice(start, end).trim();
  if (start > 0) excerpt = `...${excerpt}`;
  if (end < cleanContent.length) excerpt = `${excerpt}...`;
  return excerpt;
}

function toPlainAiText(value) {
  let text = normalizeString(value);
  if (!text) return '';

  text = text.replace(/\r\n/g, '\n');
  text = text.replace(/^\s*#{1,6}\s*/gm, '');
  text = text.replace(/\*\*(.*?)\*\*/g, '$1');
  text = text.replace(/__(.*?)__/g, '$1');
  text = text.replace(/`([^`]+)`/g, '$1');
  text = text.replace(/^\s*[*-]\s+/gm, '\u2022 ');
  text = text.replace(/\n{3,}/g, '\n\n');

  return text.trim();
}

function normalizeHandbookAiText(value) {
  let text = toPlainAiText(value);
  if (!text) return '';

  const aliases = [
    ['Short Answer', 'Short Answer'],
    ['Answer', 'Short Answer'],
    ['Direct Answer', 'Short Answer'],
    ['Key Details', 'Key Details'],
    ['Details', 'Key Details'],
    ['Important Details', 'Key Details'],
    ['What You Should Do', 'What You Should Do'],
    ['Recommended Action', 'What You Should Do'],
    ['Action', 'What You Should Do'],
    ['Source', 'Source'],
  ];

  for (const [alias, canonical] of aliases) {
    const inlineRegex = new RegExp(`^\\s*${alias}\\s*:\\s*`, 'gmi');
    const headingRegex = new RegExp(`^\\s*${alias}\\s*$`, 'gmi');
    text = text.replace(inlineRegex, `${canonical}\n`);
    text = text.replace(headingRegex, canonical);
  }

  text = text.replace(/^\s*[•*-]\s*/gm, '\u2022 ');
  text = text.replace(/\n{3,}/g, '\n\n');
  return text.trim();
}

async function ensureOsaAdmin(context) {
  const uid = normalizeString(context?.auth?.uid);
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Login required.');
  }
  const userDoc = await db.collection('users').doc(uid).get();
  const role = normalizeLower(userDoc.data()?.role);
  if (role !== 'osa_admin') {
    throw new HttpsError('permission-denied', 'OSA admin access only.');
  }
  return uid;
}

async function ensurePasswordLinkSender(context) {
  const uid = normalizeString(context?.auth?.uid);
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Login required.');
  }
  const userDoc = await db.collection('users').doc(uid).get();
  const role = normalizeLower(userDoc.data()?.role);
  const allowed = new Set(['osa_admin', 'department_admin', 'dean', 'super_admin']);
  if (!allowed.has(role)) {
    throw new HttpsError('permission-denied', 'Not allowed to generate set-password links.');
  }
  return uid;
}

function appendQueryParams(url, params) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch (error) {
    throw new HttpsError('invalid-argument', 'Invalid continueUrl.');
  }
  for (const [key, value] of Object.entries(params || {})) {
    if (!normalizeString(value)) continue;
    parsed.searchParams.set(key, normalizeString(value));
  }
  return parsed.toString();
}

function appendRouteAwareParams(url, params) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    throw new HttpsError('invalid-argument', 'Invalid continueUrl.');
  }

  const hash = normalizeString(parsed.hash);
  if (hash.startsWith('#')) {
    const hashValue = hash.slice(1);
    const questionIndex = hashValue.indexOf('?');
    const pathPart = questionIndex >= 0 ? hashValue.slice(0, questionIndex) : hashValue;
    const existingQuery = questionIndex >= 0 ? hashValue.slice(questionIndex + 1) : '';
    const hashParams = new URLSearchParams(existingQuery);
    for (const [key, value] of Object.entries(params || {})) {
      const v = normalizeString(value);
      if (!v) continue;
      hashParams.set(key, v);
    }
    const nextQuery = hashParams.toString();
    parsed.hash = nextQuery ? `#${pathPart}?${nextQuery}` : `#${pathPart}`;
    return parsed.toString();
  }

  return appendQueryParams(url, params);
}

function extractOobCode(link) {
  try {
    const parsed = new URL(link);
    return normalizeString(parsed.searchParams.get('oobCode'));
  } catch (_) {
    return '';
  }
}

function buildInAppVerifyLink(continueUrl, verifyLink, prefillEmail = '') {
  const safeContinueUrl = normalizeString(continueUrl);
  const oobCode = extractOobCode(verifyLink);
  if (!safeContinueUrl || !oobCode) {
    return '';
  }
  return appendRouteAwareParams(safeContinueUrl, {
    mode: 'verifyEmail',
    oobCode,
    prefillEmail,
  });
}

function escapeHtml(value) {
  return normalizeString(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildBrandedEmailHtml({
  title,
  subtitle = '',
  buttonLabel,
  buttonUrl,
  details = [],
  note = '',
}) {
  const safeTitle = escapeHtml(title);
  const safeSubtitle = escapeHtml(subtitle);
  const safeButtonLabel = escapeHtml(buttonLabel);
  const safeButtonUrl = escapeHtml(buttonUrl);
  const safeNote = escapeHtml(note);

  const detailsHtml = details
    .map((detail) => {
      const label = escapeHtml(detail.label);
      const value = escapeHtml(detail.value);
      return (
        `<tr>` +
        `<td style="padding:8px 0;color:#6d7f62;font-size:13px;font-weight:700;vertical-align:top;width:140px">${label}</td>` +
        `<td style="padding:8px 0;color:#1f2a1f;font-size:13px;font-weight:700;word-break:break-word">${value}</td>` +
        `</tr>`
      );
    })
    .join('');

  return (
    `<div style="background:#f4f8f4;padding:28px 14px;font-family:Arial,sans-serif">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" style="max-width:620px;width:100%;margin:0 auto;background:#ffffff;border:1px solid #dbe7db;border-radius:14px">` +
    `<tr><td style="padding:24px 24px 10px 24px;text-align:center">` +
    `<div style="font-size:14px;font-weight:800;color:#1b5e20;letter-spacing:.2px">Baliuag University: Disciplink</div>` +
    `<h2 style="margin:12px 0 6px 0;color:#1f2a1f;font-size:22px;line-height:1.2">${safeTitle}</h2>` +
    `<p style="margin:0;color:#4f6350;font-size:14px;line-height:1.5">${safeSubtitle}</p>` +
    `</td></tr>` +
    `<tr><td style="padding:12px 24px 8px 24px">` +
    `<div style="text-align:center;margin:8px 0 18px 0">` +
    `<a href="${safeButtonUrl}" style="display:inline-block;background:#1b5e20;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:9px;font-weight:800;font-size:14px">${safeButtonLabel}</a>` +
    `</div>` +
    `</td></tr>` +
    (detailsHtml
      ? `<tr><td style="padding:0 24px 10px 24px"><table role="presentation" cellpadding="0" cellspacing="0" style="width:100%">${detailsHtml}</table></td></tr>`
      : '') +
    `<tr><td style="padding:6px 24px 20px 24px">` +
    `<p style="margin:0 0 8px 0;color:#6d7f62;font-size:12px">If the button does not work, open this link:</p>` +
    `<p style="margin:0 0 10px 0;word-break:break-all;font-size:12px"><a href="${safeButtonUrl}" style="color:#1b5e20">${safeButtonUrl}</a></p>` +
    (safeNote
      ? `<p style="margin:0;color:#6d7f62;font-size:12px">${safeNote}</p>`
      : '') +
    `</td></tr>` +
    `</table>` +
    `</div>`
  );
}

function statusKey(rawStatus) {
  const status = normalizeLower(rawStatus).replace(/[\s-]+/g, '_');
  if (status === 'under_review') return 'under_review';
  if (status === 'action_set') return 'action_set';
  if (status === 'resolved') return 'resolved';
  if (status === 'unresolved') return 'unresolved';
  if (status === 'submitted' || status === 'reported') return 'submitted';
  return status || 'unknown';
}

function meetingKey(rawMeetingStatus, rawBookingStatus) {
  const meeting = normalizeLower(rawMeetingStatus);
  const booking = normalizeLower(rawBookingStatus);

  if (meeting.includes('completed') || booking.includes('completed')) {
    return 'completed';
  }
  if (
    meeting.includes('meeting_missed') ||
    (meeting.includes('missed') && !meeting.includes('booking'))
  ) {
    return 'meeting_missed';
  }
  if (meeting.includes('booking_missed') || booking.includes('missed')) {
    return 'booking_missed';
  }
  if (meeting.includes('scheduled') || booking.includes('booked')) {
    return 'scheduled';
  }
  if (!meeting || meeting.includes('pending')) {
    return 'needs_booking';
  }
  return meeting.replace(/[\s-]+/g, '_');
}

function addCount(map, key) {
  if (!key) return;
  map[key] = (map[key] || 0) + 1;
}

function topCounts(map, limit) {
  return Object.entries(map)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, count]) => ({ name, count }));
}

function scoreCaseRow(row, queryText) {
  const q = normalizeLower(queryText);
  if (!q) return 0;
  const tokens = q.split(/[^a-z0-9]+/).filter((token) => token.length >= 3);
  const searchable = [
    row.caseCode,
    row.studentName,
    row.concern,
    row.violation,
    row.status,
    row.meetingStatus,
    row.severity,
    row.sanctionType,
  ]
    .join(' ')
    .toLowerCase();

  let score = 0;
  if (searchable.includes(q)) score += 35;
  if (row.caseCode && q.includes(row.caseCode.toLowerCase())) score += 30;
  for (const token of tokens) {
    if (searchable.includes(token)) score += 4;
  }
  return score;
}

function parseOsaHistory(rawHistory) {
  if (!Array.isArray(rawHistory)) return [];
  return rawHistory
    .map((row) => {
      if (!row || typeof row !== 'object') return null;
      const role = normalizeLower(row.role) === 'assistant' ? 'assistant' : 'user';
      const text = normalizeString(row.text).slice(0, 700);
      if (!text) return null;
      return { role, text };
    })
    .filter(Boolean)
    .slice(-8);
}

function pickRelevantRows(question, history, rows) {
  const queryText = [question, ...history.map((h) => h.text)].join(' ').trim();
  const scored = rows
    .map((row) => ({
      row,
      score: scoreCaseRow(row, queryText),
    }))
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return b.row.createdAtMs - a.row.createdAtMs;
    });

  const rankedRows = scored.filter((item) => item.score > 0).map((item) => item.row);
  const fallbackRows = rows.slice(0, 25);
  const combined = [...rankedRows, ...fallbackRows];

  const unique = [];
  const seen = new Set();
  for (const row of combined) {
    if (seen.has(row.caseCode)) continue;
    seen.add(row.caseCode);
    unique.push(row);
    if (unique.length >= 60) break;
  }
  return unique;
}

function buildSnapshotCounts(rows) {
  const byStatus = {};
  const byConcern = {};
  const byMeetingStatus = {};
  const byViolation = {};

  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;
  const last7Cutoff = now - 7 * dayMs;
  const last30Cutoff = now - 30 * dayMs;
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const startTodayMs = startOfToday.getTime();

  let today = 0;
  let last7d = 0;
  let last30d = 0;

  for (const row of rows) {
    addCount(byStatus, row.statusKey);
    addCount(byConcern, row.concern || 'unknown');
    addCount(byMeetingStatus, row.meetingKey || 'unknown');
    addCount(byViolation, row.violation || 'unknown');

    if (row.createdAtMs >= startTodayMs) today += 1;
    if (row.createdAtMs >= last7Cutoff) last7d += 1;
    if (row.createdAtMs >= last30Cutoff) last30d += 1;
  }

  return {
    total: rows.length,
    submitted: byStatus.submitted || 0,
    review: byStatus.under_review || 0,
    monitoring: byStatus.action_set || 0,
    resolved: byStatus.resolved || 0,
    unresolved: byStatus.unresolved || 0,
    meetingMissed: (byMeetingStatus.booking_missed || 0) + (byMeetingStatus.meeting_missed || 0),
    recent: {
      today,
      last7d,
      last30d,
    },
    byStatus,
    byConcern,
    byMeetingStatus,
    topViolations: topCounts(byViolation, 8),
  };
}

async function loadViolationSnapshot({ question, history }) {
  const snap = await db
    .collection('violation_cases')
    .orderBy('createdAt', 'desc')
    .limit(500)
    .get();

  const rows = snap.docs.map((doc) => {
    const data = doc.data() || {};
    const createdAt = data.createdAt?.toDate?.() || null;
    const status = normalizeString(data.status);
    const meetingStatus = normalizeString(data.meetingStatus);
    const bookingStatus = normalizeString(data.bookingStatus);
    return {
      caseCode: normalizeString(data.caseCode) || doc.id,
      studentName: normalizeString(data.studentNameSnapshot || data.studentName),
      concern: normalizeString(data.concern || data.concernType),
      violation: normalizeString(
        data.violationTypeLabel || data.typeNameSnapshot || data.violationName,
      ),
      status,
      meetingStatus,
      bookingStatus,
      statusKey: statusKey(status),
      meetingKey: meetingKey(meetingStatus, bookingStatus),
      severity: normalizeString(data.finalSeverity),
      sanctionType: normalizeString(data.sanctionType),
      createdAt: createdAt ? createdAt.toISOString() : '',
      createdAtMs: createdAt ? createdAt.getTime() : 0,
    };
  });

  const counts = buildSnapshotCounts(rows);
  const relevantRows = pickRelevantRows(question, history, rows);
  return {
    counts,
    rows: relevantRows,
    snapshotAt: new Date().toISOString(),
  };
}

function buildOsaPrompt(question, history, snapshot) {
  const historyBlock = history
    .map((turn) => `${turn.role === 'assistant' ? 'Assistant' : 'User'}: ${turn.text}`)
    .join('\n');
  const summary = JSON.stringify(snapshot.counts, null, 2);
  const rows = snapshot.rows
    .map(
      (r, i) =>
        `${i + 1}) ${r.caseCode} | ${r.studentName || '-'} | concern=${r.concern || '-'} | violation=${r.violation || '-'} | status=${r.statusKey || r.status || '-'} | meeting=${r.meetingKey || '-'} | severity=${r.severity || '-'} | sanction=${r.sanctionType || '-'} | createdAt=${r.createdAt || '-'}`,
    )
    .join('\n');

  return `You are an internal OSA analytics assistant.
Use only the provided violation snapshot and conversation context. Do not invent data.
If data is insufficient, say exactly what is missing.
Prioritize direct answers with numbers first and practical next steps.
Keep answer concise and operational.
If user asks a follow-up, use Conversation context.

Output rules:
1) Plain text only.
2) Do NOT use markdown symbols like *, #, _, -, or backticks as formatting.
3) Use this exact structure:
Summary: <1-2 sentences>
Key numbers: <single paragraph with the most important counts>
Recommended actions: <single paragraph with practical admin actions>
Data source: Summary counts and/or Case rows

Question:
${question}

Conversation context:
${historyBlock || '(none)'}

Snapshot summary:
${summary}

Relevant case rows (max 60):
${rows}

Snapshot generatedAt:
${snapshot.snapshotAt}`;
}

exports.createCustomSetPasswordLink = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      await ensurePasswordLinkSender(request);

      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      const continueUrl = normalizeString(request.data?.continueUrl);
      if (!continueUrl) {
        throw new HttpsError(
          'invalid-argument',
          'continueUrl is required.',
        );
      }
      const verifyContinueUrl = normalizeString(request.data?.verifyContinueUrl) || continueUrl;

      const actionCodeSettings = {
        url: continueUrl,
        handleCodeInApp: true,
      };
      const resetLink = await getAuth().generatePasswordResetLink(
        email,
        actionCodeSettings,
      );
      const oobCode = extractOobCode(resetLink);
      if (!oobCode) {
        throw new HttpsError(
          'internal',
          'Could not generate reset action code.',
        );
      }

      let verifyOobCode = '';
      try {
        const verifyLink = await getAuth().generateEmailVerificationLink(
          email,
          {
            url: verifyContinueUrl,
            handleCodeInApp: true,
          },
        );
        verifyOobCode = extractOobCode(verifyLink);
      } catch (error) {
        console.error('verify link generation failed (non-blocking)', error);
      }

      const customLink = appendRouteAwareParams(continueUrl, {
        mode: 'resetPassword',
        oobCode,
        verifyOobCode,
        prefillEmail: email,
      });

      try {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Account Setup',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Your account is ready.\n` +
              `Please verify your email and set your password using this link:\n${customLink}\n\n` +
              `Login Email: ${email}\n\n` +
              `If you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Account Setup',
              subtitle:
                'Please verify your email and set your password to activate your account.',
              buttonLabel: 'Verify Email & Set Password',
              buttonUrl: customLink,
              details: [
                { label: 'Login Email', value: email },
              ],
              note:
                'If you did not request this account setup, you can ignore this email.',
            }),
          },
          meta: {
            kind: 'set_password',
          },
          createdAt: new Date().toISOString(),
        });
      } catch (error) {
        console.error('mail queue write failed', error);
        throw new HttpsError(
          'internal',
          'Failed to queue the account setup email.',
        );
      }

      return {
        customLink,
        verifyOobCode,
        mailQueued: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('createCustomSetPasswordLink failed', error);
      throw new HttpsError(
        'internal',
        'Failed to generate custom set-password link.',
      );
    }
  },
);

exports.requestAdminActivationLink = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      const continueUrl = normalizeString(request.data?.continueUrl);
      if (!continueUrl) {
        throw new HttpsError(
          'invalid-argument',
          'continueUrl is required.',
        );
      }
      const verifyContinueUrl = normalizeString(request.data?.verifyContinueUrl) || continueUrl;

      let authUser = null;
      try {
        authUser = await getAuth().getUserByEmail(email);
      } catch (_) {
        return { sent: true };
      }

      const userDoc = await db.collection('users').doc(authUser.uid).get();
      const userData = userDoc.data() || {};
      if (userData.createdByAdmin !== true) {
        return { sent: true };
      }

      const resetLink = await getAuth().generatePasswordResetLink(
        email,
        {
          url: continueUrl,
          handleCodeInApp: true,
        },
      );
      const oobCode = extractOobCode(resetLink);
      if (!oobCode) {
        throw new HttpsError(
          'internal',
          'Could not generate reset action code.',
        );
      }

      let verifyOobCode = '';
      try {
        const verifyLink = await getAuth().generateEmailVerificationLink(
          email,
          {
            url: verifyContinueUrl,
            handleCodeInApp: true,
          },
        );
        verifyOobCode = extractOobCode(verifyLink);
      } catch (_) {}

      const customLink = appendRouteAwareParams(continueUrl, {
        mode: 'resetPassword',
        oobCode,
        verifyOobCode,
        prefillEmail: email,
        source: 'signup',
      });

      await db.collection('mail').add({
        to: [email],
        message: {
          subject: 'Baliuag University: Disciplink | Activation Link',
          text:
            `Baliuag University: Disciplink\n\n` +
            `Please activate your account and set your password using this link:\n${customLink}\n\n` +
            `Login Email: ${email}\n\n` +
            `If you did not request this, you can ignore this message.`,
          html: buildBrandedEmailHtml({
            title: 'Activation Link',
            subtitle:
              'Please verify your email and set your password to activate your account.',
            buttonLabel: 'Activate Account',
            buttonUrl: customLink,
            details: [
              { label: 'Login Email', value: email },
            ],
            note:
              'If you did not request this email, you can ignore it.',
          }),
        },
        meta: {
          kind: 'activation_link_resend',
        },
        createdAt: new Date().toISOString(),
      });

      return { sent: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('requestAdminActivationLink failed', error);
      throw new HttpsError(
        'internal',
        'Failed to send activation link.',
      );
    }
  },
);

exports.resolveForgotPasswordFlow = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      let authUser = null;
      try {
        authUser = await getAuth().getUserByEmail(email);
      } catch (_) {
        return { action: 'reset_password' };
      }

      if (authUser.emailVerified === true) {
        return { action: 'reset_password' };
      }

      let createdByAdmin = false;
      try {
        const userDoc = await db.collection('users').doc(authUser.uid).get();
        const data = userDoc.data() || {};
        createdByAdmin = data.createdByAdmin === true;
      } catch (_) {}

      if (createdByAdmin) {
        return { action: 'needs_activation' };
      }
      return { action: 'needs_email_verification' };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('resolveForgotPasswordFlow failed', error);
      throw new HttpsError(
        'internal',
        'Failed to resolve forgot-password flow.',
      );
    }
  },
);

exports.sendForgotPasswordAssistanceEmail = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      const intent = normalizeLower(request.data?.intent);
      const continueUrl = normalizeString(request.data?.continueUrl);
      const verifyContinueUrl = normalizeString(request.data?.verifyContinueUrl) || continueUrl;

      let authUser = null;
      try {
        authUser = await getAuth().getUserByEmail(email);
      } catch (_) {
        return { sent: true };
      }

      if (authUser.emailVerified === true) {
        return { sent: true };
      }

      const userDoc = await db.collection('users').doc(authUser.uid).get();
      const userData = userDoc.data() || {};
      const createdByAdmin = userData.createdByAdmin === true;

      if (intent === 'activation' && createdByAdmin) {
        if (!continueUrl) {
          throw new HttpsError(
            'invalid-argument',
            'continueUrl is required.',
          );
        }

        const resetLink = await getAuth().generatePasswordResetLink(
          email,
          {
            url: continueUrl,
            handleCodeInApp: true,
          },
        );
        const oobCode = extractOobCode(resetLink);
        if (!oobCode) {
          throw new HttpsError(
            'internal',
            'Could not generate reset action code.',
          );
        }

        let verifyOobCode = '';
        try {
          const verifyLink = await getAuth().generateEmailVerificationLink(
            email,
            {
              url: verifyContinueUrl,
              handleCodeInApp: true,
            },
          );
          verifyOobCode = extractOobCode(verifyLink);
        } catch (_) {}

        const customLink = appendRouteAwareParams(continueUrl, {
          mode: 'resetPassword',
          oobCode,
          verifyOobCode,
          prefillEmail: email,
          source: 'signup',
        });

        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Activation Link',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Please activate your account and set your password using this link:\n${customLink}\n\n` +
              `Login Email: ${email}\n\n` +
              `If you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Activation Link',
              subtitle:
                'Please verify your email and set your password to activate your account.',
              buttonLabel: 'Activate Account',
              buttonUrl: customLink,
              details: [
                { label: 'Login Email', value: email },
              ],
              note:
                'If you did not request this email, you can ignore it.',
            }),
          },
          meta: {
            kind: 'activation_link_resend',
          },
          createdAt: new Date().toISOString(),
        });
        return { sent: true, type: 'activation' };
      }

      if (intent === 'verify' && !createdByAdmin) {
        if (!continueUrl) {
          throw new HttpsError(
            'invalid-argument',
            'continueUrl is required.',
          );
        }

        const verifyLink = await getAuth().generateEmailVerificationLink(
          email,
          {
            url: continueUrl,
            handleCodeInApp: true,
          },
        );
        const appVerifyLink =
          buildInAppVerifyLink(continueUrl, verifyLink, email) || verifyLink;

        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Verify Email',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Please verify your email using this link:\n${appVerifyLink}\n\n` +
              `Login Email: ${email}\n\n` +
              `If you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Verify Your Email',
              subtitle:
                'Please verify your email before resetting your password.',
              buttonLabel: 'Verify Email',
              buttonUrl: appVerifyLink,
              details: [
                { label: 'Login Email', value: email },
              ],
              note:
                'If you did not request this email, you can ignore it.',
            }),
          },
          meta: {
            kind: 'verify_email_recovery',
          },
          createdAt: new Date().toISOString(),
        });
        return { sent: true, type: 'verify' };
      }

      return { sent: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('sendForgotPasswordAssistanceEmail failed', error);
      throw new HttpsError(
        'internal',
        'Failed to send assistance email.',
      );
    }
  },
);

exports.sendPublicPasswordResetLink = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      const continueUrl = normalizeString(request.data?.continueUrl);

      let authUser = null;
      try {
        authUser = await getAuth().getUserByEmail(email);
      } catch (_) {
        return { sent: true };
      }

      let resetLink = '';
      if (continueUrl) {
        try {
          resetLink = await getAuth().generatePasswordResetLink(
            email,
            {
              url: continueUrl,
              handleCodeInApp: true,
            },
          );
        } catch (_) {
          resetLink = await getAuth().generatePasswordResetLink(email);
        }
      } else {
        resetLink = await getAuth().generatePasswordResetLink(email);
      }

      const oobCode = extractOobCode(resetLink);
      const appResetLink =
        continueUrl && oobCode
          ? appendRouteAwareParams(continueUrl, {
              mode: 'resetPassword',
              oobCode,
              prefillEmail: email,
              source: 'forgot_password',
            })
          : resetLink;

      await db.collection('mail').add({
        to: [email],
        message: {
          subject: 'Baliuag University: Disciplink | Reset Password',
          text:
            `Baliuag University: Disciplink\n\n` +
            `Reset your password using this link:\n${appResetLink}\n\n` +
            `Login Email: ${email}\n\n` +
            `If you did not request this, you can ignore this message.`,
          html: buildBrandedEmailHtml({
            title: 'Reset Your Password',
            subtitle:
              'Use the button below to set a new password for your account.',
            buttonLabel: 'Reset Password',
            buttonUrl: appResetLink,
            details: [
              { label: 'Login Email', value: email },
            ],
            note:
              'If you did not request this email, you can ignore it.',
          }),
        },
        meta: {
          kind: 'password_reset_public',
          uid: authUser.uid,
        },
        createdAt: new Date().toISOString(),
      });

      return { sent: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('sendPublicPasswordResetLink failed', error);
      throw new HttpsError(
        'internal',
        'Failed to send password reset link.',
      );
    }
  },
);

exports.createCustomVerifyEmailLink = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      await ensurePasswordLinkSender(request);

      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      const continueUrl = normalizeString(request.data?.continueUrl);
      if (!continueUrl) {
        throw new HttpsError(
          'invalid-argument',
          'continueUrl is required.',
        );
      }
      const temporaryPassword = normalizeString(request.data?.temporaryPassword);

      const verifyLink = await getAuth().generateEmailVerificationLink(
        email,
        {
          url: continueUrl,
          handleCodeInApp: true,
        },
      );
      const appVerifyLink =
        buildInAppVerifyLink(continueUrl, verifyLink, email) || verifyLink;

      try {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Verify Email',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Your account was created by the administrator.\n` +
              `Please verify your email using this link:\n${appVerifyLink}\n\n` +
              `Login Email: ${email}\n` +
              (temporaryPassword
                ? `Password: ${temporaryPassword}\n`
                : '') +
              `\nIf you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Verify Your Email',
              subtitle:
                'Your account is ready. Verify your email before logging in.',
              buttonLabel: 'Verify Email',
              buttonUrl: appVerifyLink,
              details: [
                { label: 'Login Email', value: email },
                ...(temporaryPassword
                  ? [{ label: 'Password', value: temporaryPassword }]
                  : []),
              ],
              note:
                'If you did not request this account, you can ignore this email.',
            }),
          },
          meta: {
            kind: 'verify_email',
          },
          createdAt: new Date().toISOString(),
        });
      } catch (error) {
        console.error('mail queue write failed', error);
        throw new HttpsError(
          'internal',
          'Failed to queue the verify-email message.',
        );
      }

      return {
        verifyLink,
        appVerifyLink,
        mailQueued: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('createCustomVerifyEmailLink failed', error);
      throw new HttpsError(
        'internal',
        'Failed to generate custom verify-email link.',
      );
    }
  },
);

exports.sendCurrentUserVerifyEmailLink = onCall(
  { region: 'asia-east1', timeoutSeconds: 60 },
  async (request) => {
    try {
      const uid = normalizeString(request.auth?.uid);
      if (!uid) {
        throw new HttpsError('unauthenticated', 'Login required.');
      }

      const authUser = await getAuth().getUser(uid);
      const email = normalizeString(authUser.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError(
          'failed-precondition',
          'Authenticated user has no valid email.',
        );
      }

      const requestedEmail = normalizeString(request.data?.email).toLowerCase();
      if (requestedEmail && requestedEmail !== email) {
        throw new HttpsError(
          'permission-denied',
          'Email does not match authenticated user.',
        );
      }

      const continueUrl = normalizeString(request.data?.continueUrl);
      if (!continueUrl) {
        throw new HttpsError(
          'invalid-argument',
          'continueUrl is required.',
        );
      }

      const verifyLink = await getAuth().generateEmailVerificationLink(
        email,
        {
          url: continueUrl,
          handleCodeInApp: true,
        },
      );
      const appVerifyLink =
        buildInAppVerifyLink(continueUrl, verifyLink, email) || verifyLink;

      try {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Verify Email',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Please verify your email using this link:\n${appVerifyLink}\n\n` +
              `After verification, log in to BUDiscipLink and complete your student profile.\n\n` +
              `Login Email: ${email}\n\n` +
              `If you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Verify Your Email',
              subtitle:
                'Please verify your email, then log in and complete your student profile.',
              buttonLabel: 'Verify Email',
              buttonUrl: appVerifyLink,
              details: [
                { label: 'Login Email', value: email },
              ],
              note:
                'After verification, log in and complete your student profile. If you did not request this email, you can ignore this message.',
            }),
          },
          meta: {
            kind: 'verify_email_self',
          },
          createdAt: new Date().toISOString(),
        });
      } catch (error) {
        console.error('mail queue write failed', error);
        throw new HttpsError(
          'internal',
          'Failed to queue the verification email.',
        );
      }

      return {
        verifyLink,
        appVerifyLink,
        mailQueued: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('sendCurrentUserVerifyEmailLink failed', error);
      throw new HttpsError(
        'internal',
        'Failed to send current-user verify email link.',
      );
    }
  },
);

exports.checkEmailVerificationStatus = onCall(
  { region: 'asia-east1', timeoutSeconds: 30 },
  async (request) => {
    try {
      const email = normalizeString(request.data?.email).toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email is required.');
      }

      try {
        const authUser = await getAuth().getUserByEmail(email);
        return {
          found: true,
          emailVerified: authUser.emailVerified === true,
        };
      } catch (_) {
        return {
          found: false,
          emailVerified: false,
        };
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('checkEmailVerificationStatus failed', error);
      throw new HttpsError(
        'internal',
        'Failed to check email verification status.',
      );
    }
  },
);

exports.askHandbookAi = onCall(
  { region: 'asia-east1', timeoutSeconds: 120, secrets: ['GEMINI_API_KEY'] },
  async (request) => {
    try {
      const question = normalizeString(request.data?.question);
      if (!question) {
        throw new HttpsError('invalid-argument', 'Question is required.');
      }

      const entries = await loadHandbookEntries();
      if (entries.length === 0) {
        return {
          answer: 'No active handbook content is available right now.',
          sources: [],
          sourceRefs: [],
        };
      }

      const { prompt, sources, sourceRefs } = buildHandbookPrompt(question, entries);
      const answer = normalizeHandbookAiText(
        await generateText(HANDBOOK_MODEL, prompt),
      );
      return {
        answer: answer || 'I could not generate a handbook answer right now.',
        sources,
        sourceRefs,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('askHandbookAi failed', error);
      throw new HttpsError('internal', 'Failed to generate handbook response.');
    }
  },
);

exports.askOsaViolationAi = onCall(
  { region: 'asia-east1', timeoutSeconds: 120, secrets: ['GEMINI_API_KEY'] },
  async (request) => {
    try {
      await ensureOsaAdmin(request);

      const question = normalizeString(request.data?.question);
      if (!question) {
        throw new HttpsError('invalid-argument', 'Question is required.');
      }

      const history = parseOsaHistory(request.data?.history);
      const snapshot = await loadViolationSnapshot({ question, history });
      const prompt = buildOsaPrompt(question, history, snapshot);
      const answer = toPlainAiText(await generateText(OSA_MODEL, prompt));
      return {
        answer: answer || 'I could not generate a violation analytics answer right now.',
        sources: [
          'violation_cases summary',
          ...snapshot.rows.slice(0, 8).map((row) => row.caseCode),
        ],
        counts: snapshot.counts,
        snapshotAt: snapshot.snapshotAt,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('askOsaViolationAi failed', error);
      throw new HttpsError('internal', 'Failed to generate OSA analytics response.');
    }
  },
);

async function queueCounselingNotification({
  caseId,
  studentUid,
  title,
  body,
  payload = {},
}) {
  const safeCaseId = normalizeString(caseId);
  const safeStudentUid = normalizeString(studentUid);
  if (!safeCaseId || !safeStudentUid) return;

  const now = FieldValue.serverTimestamp();
  await Promise.all([
    db
      .collection('counseling_cases')
      .doc(safeCaseId)
      .collection('notification_queue')
      .add({
        toType: 'uid',
        toUid: safeStudentUid,
        title: normalizeString(title),
        body: normalizeString(body),
        payload,
        createdAt: now,
        readAt: null,
      }),
    db
      .collection('users')
      .doc(safeStudentUid)
      .collection('notifications')
      .add({
        caseId: safeCaseId,
        title: normalizeString(title),
        body: normalizeString(body),
        payload,
        createdAt: now,
        readAt: null,
      }),
  ]);
}

async function queueViolationNotification({
  caseId,
  studentUid,
  title,
  body,
  payload = {},
}) {
  const safeCaseId = normalizeString(caseId);
  const safeStudentUid = normalizeString(studentUid);
  if (!safeCaseId || !safeStudentUid) return;

  const now = FieldValue.serverTimestamp();
  await Promise.all([
    db
      .collection('violation_cases')
      .doc(safeCaseId)
      .collection('notification_queue')
      .add({
        toType: 'uid',
        toUid: safeStudentUid,
        title: normalizeString(title),
        body: normalizeString(body),
        payload,
        createdAt: now,
        readAt: null,
      }),
    db
      .collection('users')
      .doc(safeStudentUid)
      .collection('notifications')
      .add({
        caseId: safeCaseId,
        title: normalizeString(title),
        body: normalizeString(body),
        payload,
        createdAt: now,
        readAt: null,
      }),
  ]);
}

exports.pushUserNotification = onDocumentCreated(
  {
    region: 'asia-east1',
    document: 'users/{uid}/notifications/{notificationId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const uid = normalizeString(event.params?.uid);
    const notificationId = normalizeString(event.params?.notificationId);
    const data = event.data?.data() || {};
    if (!uid || !notificationId) return;

    const title = normalizeString(data.title) || 'New notification';
    const body = normalizeString(data.body);
    const payload = data.payload && typeof data.payload === 'object'
      ? data.payload
      : {};
    const payloadMap = toStringMap(payload);
    const caseId =
      normalizeString(data.caseId) || normalizeString(payloadMap.caseId);
    const link = normalizeString(payloadMap.link) || '/';

    const userSnap = await db.collection('users').doc(uid).get();
    const role = normalizeLower(userSnap.data()?.role);
    if (role && role !== 'student') return;

    const tokenSnap = await db
      .collection('users')
      .doc(uid)
      .collection('fcmTokens')
      .limit(40)
      .get();

    const tokens = tokenSnap.docs
      .filter((doc) => doc.data()?.enabled !== false)
      .map((doc) => normalizeString(doc.id))
      .filter((token) => token.length > 0);

    if (tokens.length === 0) return;

    const message = {
      tokens,
      notification: {
        title,
        body,
      },
      data: {
        uid,
        notificationId,
        title,
        body,
        caseId,
        ...payloadMap,
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
        },
      },
      webpush: {
        fcmOptions: {
          link,
        },
        notification: {
          title,
          body,
          icon: '/icons/Icon-192-bud.png',
          badge: '/icons/Icon-192-bud.png',
        },
      },
    };

    const response = await getMessaging().sendEachForMulticast(message);

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = normalizeString(result.error?.code);
      if (INVALID_FCM_TOKEN_ERRORS.has(code)) {
        invalidTokens.push(tokens[index]);
      }
    });

    if (invalidTokens.length > 0) {
      const batch = db.batch();
      for (const token of invalidTokens) {
        batch.delete(
          db.collection('users').doc(uid).collection('fcmTokens').doc(token),
        );
      }
      await batch.commit();
    }
  },
);

async function appendCounselingActivity({
  caseId,
  event,
  title,
  description = '',
  actorRole = 'system',
  meta = {},
}) {
  const safeCaseId = normalizeString(caseId);
  if (!safeCaseId) return;
  await db
    .collection('counseling_cases')
    .doc(safeCaseId)
    .collection('activity')
    .add({
      event: normalizeString(event),
      title: normalizeString(title),
      description: normalizeString(description),
      actorUid: '',
      actorRole: normalizeString(actorRole) || 'system',
      meta,
      createdAt: FieldValue.serverTimestamp(),
      createdAtEpochMs: Date.now(),
    });
}

exports.sweepOverdueCounselingMeetings = onSchedule(
  {
    region: 'asia-east1',
    schedule: 'every 15 minutes',
    timeZone: 'Asia/Manila',
    retryCount: 0,
  },
  async () => {
    const now = Date.now();
    const graceMs = 60 * 60 * 1000;

    const snap = await db
      .collection('counseling_cases')
      .where('meetingStatus', '==', 'scheduled')
      .limit(500)
      .get();

    if (snap.empty) {
      return { processed: 0, message: 'No scheduled counseling cases.' };
    }

    const overdueRows = [];
    const caseBatch = db.batch();
    const slotBatch = db.batch();
    let hasSlotUpdates = false;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const scheduledAt =
        data.scheduledAt && typeof data.scheduledAt.toDate === 'function'
          ? data.scheduledAt.toDate()
          : null;
      if (!scheduledAt) continue;

      const workflowStatus = normalizeLower(data.workflowStatus);
      const bookingStatus = normalizeLower(data.bookingStatus);
      const completedOrCancelled =
        workflowStatus === 'completed' ||
        workflowStatus === 'cancelled' ||
        bookingStatus === 'completed' ||
        bookingStatus === 'cancelled';
      if (completedOrCancelled) continue;

      const alreadyMissed =
        workflowStatus === 'missed' ||
        normalizeLower(data.meetingStatus).includes('missed') ||
        bookingStatus === 'missed';
      if (alreadyMissed) continue;

      if (now <= scheduledAt.getTime() + graceMs) continue;

      overdueRows.push({
        id: doc.id,
        studentUid: normalizeString(data.studentUid),
        caseCode: normalizeString(data.caseCode) || doc.id,
        slotId: normalizeString(data.bookingSlotId),
      });

      caseBatch.update(doc.ref, {
        workflowStatus: 'missed',
        meetingStatus: 'meeting_missed',
        bookingStatus: 'missed',
        missedCount: FieldValue.increment(1),
        meetingMissedAt: FieldValue.serverTimestamp(),
        bookingMissedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const slotId = normalizeString(data.bookingSlotId);
      if (slotId) {
        hasSlotUpdates = true;
        slotBatch.set(
          db.collection('counseling_meeting_slots').doc(slotId),
          {
            status: 'missed',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    if (overdueRows.length === 0) {
      return { processed: 0, message: 'No overdue counseling meetings.' };
    }

    await caseBatch.commit();
    if (hasSlotUpdates) {
      await slotBatch.commit();
    }

    for (const row of overdueRows) {
      if (!row.studentUid) continue;
      await queueCounselingNotification({
        caseId: row.id,
        studentUid: row.studentUid,
        title: 'Counseling Appointment Missed',
        body:
          `You did not attend your scheduled counseling appointment for case ${row.caseCode}. ` +
          'Please book again when available.',
        payload: {
          module: 'counseling',
          workflowStatus: 'missed',
          meetingStatus: 'meeting_missed',
        },
      });
      await appendCounselingActivity({
        caseId: row.id,
        event: 'appointment_auto_missed',
        title: 'Appointment auto-marked missed',
        description:
          'Scheduled counseling appointment was not attended and was auto-marked missed.',
        actorRole: 'system',
        meta: {
          caseCode: row.caseCode,
          slotId: row.slotId,
          workflowStatus: 'missed',
          meetingStatus: 'meeting_missed',
        },
      });
    }

    return { processed: overdueRows.length };
  },
);

exports.sweepOverdueViolationMeetings = onSchedule(
  {
    region: 'asia-east1',
    schedule: 'every 15 minutes',
    timeZone: 'Asia/Manila',
    retryCount: 0,
  },
  async () => {
    const now = new Date();
    const nowMs = now.getTime();

    const snap = await db
      .collection('violation_cases')
      .where('status', '==', 'Action Set')
      .limit(500)
      .get();

    if (snap.empty) {
      return { processed: 0, message: 'No action-set violation cases.' };
    }

    const graceExtensions = [];
    const overdueBooking = [];
    const scheduledMissed = [];

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (data.meetingRequired !== true) continue;

      const meetingStatus = normalizeLower(data.meetingStatus);
      const bookingStatus = normalizeLower(data.bookingStatus);

      const pendingBooking =
        !meetingStatus ||
        meetingStatus === 'pending' ||
        meetingStatus === 'pending_student_booking';

      const scheduledAt =
        data.scheduledAt && typeof data.scheduledAt.toDate === 'function'
          ? data.scheduledAt.toDate()
          : null;
      const booked = meetingStatus.includes('scheduled') || bookingStatus === 'booked';
      const completed =
        meetingStatus.includes('completed') || bookingStatus === 'completed';
      const missedAlready = meetingStatus.includes('missed');

      if (
        scheduledAt &&
        booked &&
        !completed &&
        !missedAlready &&
        nowMs > scheduledAt.getTime() + 60 * 60 * 1000
      ) {
        scheduledMissed.push({
          id: doc.id,
          slotId: normalizeString(data.bookingSlotId),
          studentUid: normalizeString(data.studentUid),
          caseCode: normalizeString(data.caseCode) || doc.id,
        });
        continue;
      }

      if (!pendingBooking) continue;
      if (scheduledAt) continue;

      const bookingDeadlineAt =
        data.bookingDeadlineAt &&
        typeof data.bookingDeadlineAt.toDate === 'function'
          ? data.bookingDeadlineAt.toDate()
          : null;
      const meetingDueBy =
        data.meetingDueBy && typeof data.meetingDueBy.toDate === 'function'
          ? data.meetingDueBy.toDate()
          : null;
      const deadline = bookingDeadlineAt || meetingDueBy;
      if (!deadline || nowMs <= deadline.getTime()) continue;

      const graceCount =
        typeof data.bookingGraceCount === 'number'
          ? Math.trunc(data.bookingGraceCount)
          : 0;
      if (graceCount < 1) {
        const nextBookingDeadline = new Date(nowMs + 2 * 24 * 60 * 60 * 1000);
        const nextMeetingDueBy =
          !meetingDueBy || meetingDueBy.getTime() < nextBookingDeadline.getTime()
            ? nextBookingDeadline
            : meetingDueBy;

        graceExtensions.push({
          id: doc.id,
          studentUid: normalizeString(data.studentUid),
          caseCode: normalizeString(data.caseCode) || doc.id,
          nextBookingDeadline,
          nextMeetingDueBy,
          nextGraceCount: graceCount + 1,
        });
      } else {
        overdueBooking.push({
          id: doc.id,
          studentUid: normalizeString(data.studentUid),
          caseCode: normalizeString(data.caseCode) || doc.id,
        });
      }
    }

    if (graceExtensions.length > 0) {
      const batch = db.batch();
      for (const row of graceExtensions) {
        batch.update(db.collection('violation_cases').doc(row.id), {
          meetingStatus: 'pending_student_booking',
          bookingStatus: 'pending',
          bookingGraceCount: row.nextGraceCount,
          bookingGraceExtendedAt: FieldValue.serverTimestamp(),
          bookingDeadlineAt: row.nextBookingDeadline,
          meetingDueBy: row.nextMeetingDueBy,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    if (overdueBooking.length > 0) {
      const batch = db.batch();
      for (const row of overdueBooking) {
        batch.update(db.collection('violation_cases').doc(row.id), {
          meetingStatus: 'booking_missed',
          bookingStatus: 'missed',
          bookingMissedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    if (scheduledMissed.length > 0) {
      const caseBatch = db.batch();
      const slotBatch = db.batch();
      let hasSlotUpdates = false;

      for (const row of scheduledMissed) {
        caseBatch.update(db.collection('violation_cases').doc(row.id), {
          status: 'Unresolved',
          workflowStep: 'monitoring',
          workflowAction: 'meeting_required',
          meetingStatus: 'meeting_missed',
          bookingStatus: 'missed',
          meetingMissedAt: FieldValue.serverTimestamp(),
          unresolvedAt: FieldValue.serverTimestamp(),
          unresolvedReason: 'meeting_absence',
          updatedAt: FieldValue.serverTimestamp(),
        });

        if (row.slotId) {
          hasSlotUpdates = true;
          slotBatch.set(
            db.collection('osa_meeting_slots').doc(row.slotId),
            {
              status: 'missed',
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      await caseBatch.commit();
      if (hasSlotUpdates) {
        await slotBatch.commit();
      }
    }

    for (const row of graceExtensions) {
      if (!row.studentUid) continue;
      await queueViolationNotification({
        caseId: row.id,
        studentUid: row.studentUid,
        title: 'Booking Window Extended',
        body:
          `You still have 2 more days to book your OSA meeting slot for case ${row.caseCode}.`,
        payload: { meetingStatus: 'pending_student_booking' },
      });
    }

    for (const row of overdueBooking) {
      if (!row.studentUid) continue;
      await queueViolationNotification({
        caseId: row.id,
        studentUid: row.studentUid,
        title: 'Booking Window Missed',
        body:
          `You did not book an OSA meeting slot within the allowed 5-day window for case ${row.caseCode}. Please wait for OSA follow-up.`,
        payload: { meetingStatus: 'booking_missed' },
      });
    }

    for (const row of scheduledMissed) {
      if (!row.studentUid) continue;
      await queueViolationNotification({
        caseId: row.id,
        studentUid: row.studentUid,
        title: 'Meeting Missed',
        body:
          `You did not attend the scheduled OSA meeting for case ${row.caseCode}. The case is now marked unresolved.`,
        payload: {
          status: 'Unresolved',
          meetingStatus: 'meeting_missed',
        },
      });
    }

    return {
      processed:
        graceExtensions.length + overdueBooking.length + scheduledMissed.length,
      graceExtended: graceExtensions.length,
      bookingMissed: overdueBooking.length,
      meetingMissed: scheduledMissed.length,
    };
  },
);
