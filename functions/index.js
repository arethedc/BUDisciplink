const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { genkit } = require('genkit');
const { googleAI } = require('@genkit-ai/googleai');

initializeApp();

const db = getFirestore();

const HANDBOOK_MODEL = 'googleai/gemini-2.5-flash-lite';
const OSA_MODEL = 'googleai/gemini-2.5-flash-lite';
const MAX_CONTEXT_CHARS = 16000;
const MAX_SOURCE_CHARS = 1200;
const MAX_IN_QUERY_VALUES = 10;

function normalizeString(value) {
  return (value ?? '').toString().trim();
}

function normalizeLower(value) {
  return normalizeString(value).toLowerCase();
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
  const snap = await db.collection('handbook_meta').doc('current').get();
  const versionId = normalizeString(snap.data()?.activeVersionId);
  if (!versionId) {
    throw new HttpsError(
      'failed-precondition',
      'Missing handbook_meta/current.activeVersionId',
    );
  }
  return versionId;
}

async function loadHandbookEntries() {
  const versionId = await getActiveVersionId();

  const [sectionSnap, topicSnap] = await Promise.all([
    db.collection('handbook_sections').where('versionId', '==', versionId).get(),
    db.collection('handbook_topics').where('versionId', '==', versionId).get(),
  ]);

  const sections = sectionSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((row) => row.isPublished === true)
    .sort((a, b) => orderValue(a.order) - orderValue(b.order));

  const sectionByCode = new Map();
  for (const section of sections) {
    const code = normalizeString(section.code);
    if (!code) continue;
    sectionByCode.set(code, {
      code,
      title: normalizeString(section.title),
    });
  }

  const topics = topicSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((row) => row.isPublished === true)
    .sort((a, b) => {
      const sectionCompare = normalizeString(a.sectionCode).localeCompare(
        normalizeString(b.sectionCode),
      );
      if (sectionCompare !== 0) return sectionCompare;
      return orderValue(a.order) - orderValue(b.order);
    });

  if (topics.length === 0) return [];

  const topicIds = topics.map((topic) => topic.id);
  const blocksByTopicId = new Map();

  for (let i = 0; i < topicIds.length; i += MAX_IN_QUERY_VALUES) {
    const chunk = topicIds.slice(i, i + MAX_IN_QUERY_VALUES);
    const contentSnap = await db
      .collection('handbook_contents')
      .where('topicId', 'in', chunk)
      .get();
    for (const doc of contentSnap.docs) {
      const data = doc.data() || {};
      const topicId = normalizeString(data.topicId) || doc.id;
      const blocks = Array.isArray(data.publishedBlocks)
        ? data.publishedBlocks
        : Array.isArray(data.blocks)
          ? data.blocks
          : [];
      blocksByTopicId.set(topicId, blocks);
    }
  }

  const entries = [];
  for (const topic of topics) {
    const sectionCode = normalizeString(topic.sectionCode);
    const section = sectionByCode.get(sectionCode);
    if (!section) continue;

    const blocks = blocksByTopicId.get(topic.id) || [];
    const textParts = [];
    for (const rawBlock of blocks) {
      const block = rawBlock || {};
      const type = normalizeLower(block.type);
      const text = normalizeString(block.text);
      const caption = normalizeString(block.caption);
      const number = normalizeString(block.number);
      const title = normalizeString(block.title);
      if (number) textParts.push(number);
      if (title) textParts.push(title);
      if (text) textParts.push(text);
      if (type === 'image' && caption) textParts.push(caption);
    }

    const content = textParts.join('\n').trim();
    entries.push({
      sectionCode: section.code,
      sectionTitle: section.title,
      topicCode: normalizeString(topic.code),
      topicTitle: normalizeString(topic.title),
      content,
      searchable: `${section.code} ${section.title} ${topic.code || ''} ${topic.title || ''} ${content}`.toLowerCase(),
      source: `${normalizeString(topic.code)} ${normalizeString(topic.title)}`.trim(),
    });
  }
  return entries;
}

function buildHandbookPrompt(question, entries) {
  const ranked = [...entries].sort((a, b) => scoreEntry(b, question) - scoreEntry(a, question));
  const picked = ranked.slice(0, 8);

  let context = '';
  const used = [];
  for (let i = 0; i < picked.length; i += 1) {
    const entry = picked[i];
    const body = entry.content.length > MAX_SOURCE_CHARS
      ? `${entry.content.slice(0, MAX_SOURCE_CHARS)}...`
      : entry.content;
    const block = `[Source ${i + 1}]
Section: ${entry.sectionCode}. ${entry.sectionTitle}
Topic: ${entry.topicCode} ${entry.topicTitle}
Content:
${body}

`;
    if (context.length + block.length > MAX_CONTEXT_CHARS) break;
    context += block;
    used.push(entry.source);
  }

  return {
    prompt: `You are the official student handbook assistant.
Answer ONLY from the handbook context.
If not in context, explicitly say it is not stated.
Keep response concise, clear, and student-friendly.
Finish with: Source: <topic names>

Question:
${question}

Handbook context:
${context.trim()}`,
    sources: [...new Set(used)],
  };
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
Prioritize direct answers with numbers first.
When presenting metrics, cite where they came from:
- "Summary counts" for aggregate stats
- "Case rows" for case-level references
Keep answer concise and operational.
If user asks a follow-up, use Conversation context.

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

      let mailQueued = false;
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
        mailQueued = true;
      } catch (error) {
        console.error('mail queue write failed (optional)', error);
      }

      return {
        customLink,
        verifyOobCode,
        mailQueued,
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

      let mailQueued = false;
      try {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Verify Email',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Your account was created by the administrator.\n` +
              `Please verify your email using this link:\n${verifyLink}\n\n` +
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
              buttonUrl: verifyLink,
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
        mailQueued = true;
      } catch (error) {
        console.error('mail queue write failed (optional)', error);
      }

      return {
        verifyLink,
        mailQueued,
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

      let mailQueued = false;
      try {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: 'Baliuag University: Disciplink | Verify Email',
            text:
              `Baliuag University: Disciplink\n\n` +
              `Please verify your email using this link:\n${verifyLink}\n\n` +
              `Login Email: ${email}\n\n` +
              `If you did not request this, you can ignore this message.`,
            html: buildBrandedEmailHtml({
              title: 'Verify Your Email',
              subtitle:
                'Please verify your email before continuing to your account.',
              buttonLabel: 'Verify Email',
              buttonUrl: verifyLink,
              details: [
                { label: 'Login Email', value: email },
              ],
              note:
                'If you did not request this email, you can ignore this message.',
            }),
          },
          meta: {
            kind: 'verify_email_self',
          },
          createdAt: new Date().toISOString(),
        });
        mailQueued = true;
      } catch (error) {
        console.error('mail queue write failed (optional)', error);
      }

      return {
        verifyLink,
        mailQueued,
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
          answer: 'No published handbook content is available right now.',
          sources: [],
        };
      }

      const { prompt, sources } = buildHandbookPrompt(question, entries);
      const answer = await generateText(HANDBOOK_MODEL, prompt);
      return {
        answer: answer || 'I could not generate a handbook answer right now.',
        sources,
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
      const answer = await generateText(OSA_MODEL, prompt);
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
