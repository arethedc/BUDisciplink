const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sourcePath = path.join(root, 'config', 'firebase_target.json');
const appTargetPath = path.join(root, 'lib', 'services', 'app_firestore_target.dart');
const functionsTargetPath = path.join(root, 'functions', 'firestore_target.js');
const extensionEnvPath = path.join(root, 'extensions', 'firestore-send-email.env');

const DEFAULT_DATABASE_ID = '(default)';
const DEFAULT_DATABASE_REGION = 'asia-east1';

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function readSourceConfig() {
  try {
    return JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
  } catch (error) {
    fail(`Unable to read ${path.relative(root, sourcePath)}: ${error.message}`);
  }
}

function normalizeDatabaseId(value) {
  return String(value ?? DEFAULT_DATABASE_ID).trim() || DEFAULT_DATABASE_ID;
}

function normalizeDatabaseRegion(value) {
  const region = String(value ?? DEFAULT_DATABASE_REGION).trim() || DEFAULT_DATABASE_REGION;
  if (!/^[a-z0-9-]+$/.test(region)) {
    fail(`Invalid firestoreDatabaseRegion "${region}" in config/firebase_target.json`);
  }
  return region;
}

function writeIfChanged(filePath, content) {
  const previous = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  if (previous === content) return false;
  fs.writeFileSync(filePath, content);
  return true;
}

function upsertEnvLine(raw, key, value) {
  const pattern = new RegExp(`^${key}=.*$`, 'm');
  if (pattern.test(raw)) {
    return raw.replace(pattern, `${key}=${value}`);
  }
  const suffix = raw.endsWith('\n') ? '' : '\n';
  return `${raw}${suffix}${key}=${value}\n`;
}

function escapeSingleQuote(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function sync() {
  const config = readSourceConfig();
  const databaseId = normalizeDatabaseId(config.firestoreDatabaseId);
  const databaseRegion = normalizeDatabaseRegion(config.firestoreDatabaseRegion);

  const appTarget = `// GENERATED FILE. Do not edit by hand.
// Source: config/firebase_target.json

const String kFirestoreDatabaseId = '${escapeSingleQuote(databaseId)}';
const String kFirestoreDatabaseRegion = '${escapeSingleQuote(databaseRegion)}';
const bool kUseDefaultFirestoreDatabase = kFirestoreDatabaseId == '(default)';
`;

  const functionsTarget = `// GENERATED FILE. Do not edit by hand.
// Source: config/firebase_target.json

const FIRESTORE_DATABASE_ID = '${escapeSingleQuote(databaseId)}';
const FIRESTORE_DATABASE_REGION = '${escapeSingleQuote(databaseRegion)}';
const USE_DEFAULT_FIRESTORE_DATABASE = FIRESTORE_DATABASE_ID === '(default)';

module.exports = {
  FIRESTORE_DATABASE_ID,
  FIRESTORE_DATABASE_REGION,
  USE_DEFAULT_FIRESTORE_DATABASE,
};
`;

  const appChanged = writeIfChanged(appTargetPath, appTarget);
  const functionsChanged = writeIfChanged(functionsTargetPath, functionsTarget);

  const currentEnv = fs.readFileSync(extensionEnvPath, 'utf8');
  let nextEnv = upsertEnvLine(currentEnv, 'DATABASE', databaseId);
  nextEnv = upsertEnvLine(nextEnv, 'DATABASE_REGION', databaseRegion);
  const envChanged = writeIfChanged(extensionEnvPath, nextEnv);

  console.log(`Synced Firestore target from config/firebase_target.json
- databaseId: ${databaseId}
- databaseRegion: ${databaseRegion}
- lib/services/app_firestore_target.dart: ${appChanged ? 'updated' : 'no changes'}
- functions/firestore_target.js: ${functionsChanged ? 'updated' : 'no changes'}
- extensions/firestore-send-email.env: ${envChanged ? 'updated' : 'no changes'}`);
}

sync();
