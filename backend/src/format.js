const { badRequest } = require('./errors');

// L'ERP échange les dates au format français : « jj/mm/aaaa » et « jj/mm/aaaa hh:mm ».
const frDatePattern = /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/;

function parseFr(value, field, { withTime }) {
  const raw = typeof value === 'string' ? value.trim() : '';
  if (raw === '' || raw === '-') return null;
  const match = frDatePattern.exec(raw);
  if (!match) throw badRequest(`Date invalide pour « ${field} » : ${raw}`);
  const [, d, m, y, hh = '0', mm = '0'] = match;
  const day = Number(d);
  const month = Number(m);
  const year = Number(y);
  const check = new Date(Date.UTC(year, month - 1, day));
  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day ||
    Number(hh) > 23 ||
    Number(mm) > 59
  ) {
    throw badRequest(`Date invalide pour « ${field} » : ${raw}`);
  }
  const date = `${y}-${pad(month)}-${pad(day)}`;
  return withTime ? `${date} ${pad(hh)}:${pad(mm)}:00` : date;
}

const pad = (value) => String(value).padStart(2, '0');

const frDateToSql = (value, field) => parseFr(value, field, { withTime: false });

function frDateTimeToSql(value, field) {
  const result = parseFr(value, field, { withTime: true });
  if (result === null) throw badRequest(`Date obligatoire pour « ${field} »`);
  return result;
}

// '2026-10-09' -> '09/10/2026' ; null -> fallback
function sqlDateToFr(value, fallback = '') {
  if (!value) return fallback;
  const [y, m, d] = value.slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

// '2026-10-09 14:05:00' -> '09/10/2026 14:05'
const sqlDateTimeToFr = (value) =>
  `${sqlDateToFr(value)} ${value.slice(11, 16)}`;

function text(source, key, { required = false, max = 500 } = {}) {
  const value = source?.[key];
  if (value === undefined || value === null) {
    if (required) throw badRequest(`Le champ « ${key} » est obligatoire.`);
    return '';
  }
  if (typeof value !== 'string') {
    throw badRequest(`Le champ « ${key} » doit être un texte.`);
  }
  const trimmed = value.trim();
  if (required && trimmed === '') {
    throw badRequest(`Le champ « ${key} » est obligatoire.`);
  }
  if (trimmed.length > max) {
    throw badRequest(`Le champ « ${key} » est trop long.`);
  }
  return trimmed;
}

// Texte optionnel : '' devient NULL (références vers un compte ou un journal).
function optionalRef(source, key) {
  const value = text(source, key);
  return value === '' ? null : value;
}

function amount(source, key, { min } = {}) {
  const value = source?.[key] ?? 0;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw badRequest(`Le montant « ${key} » est invalide.`);
  }
  if (min !== undefined && value < min) {
    throw badRequest(`Le montant « ${key} » doit être supérieur ou égal à ${min}.`);
  }
  return Math.round(value * 100) / 100;
}

function integer(source, key, { min = 0 } = {}) {
  const value = source?.[key] ?? 0;
  if (!Number.isInteger(value) || value < min) {
    throw badRequest(`Le nombre « ${key} » est invalide.`);
  }
  return value;
}

function bool(source, key) {
  const value = source?.[key] ?? false;
  if (typeof value !== 'boolean') {
    throw badRequest(`Le champ « ${key} » doit être vrai ou faux.`);
  }
  return value;
}

function list(source, key, { max = 500 } = {}) {
  const value = source?.[key] ?? [];
  if (!Array.isArray(value)) {
    throw badRequest(`Le champ « ${key} » doit être une liste.`);
  }
  if (value.length > max) {
    throw badRequest(`La liste « ${key} » contient trop d’éléments.`);
  }
  return value;
}

function oneOf(source, key, allowed) {
  const value = text(source, key, { required: true });
  if (!allowed.includes(value)) {
    throw badRequest(`Valeur non autorisée pour « ${key} » : ${value}`);
  }
  return value;
}

// Photo de profil : undefined = inchangée, null = supprimée, sinon image JPEG/PNG en base64.
const MAX_PHOTO_BYTES = 300 * 1024;
function photo(source, key = 'photo') {
  if (!(key in (source ?? {}))) return undefined;
  const value = source[key];
  if (value === null || value === '') return null;
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw badRequest('Photo invalide.');
  }
  const bytes = Buffer.from(value, 'base64');
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  if (!isJpeg && !isPng) throw badRequest('La photo doit être une image JPEG ou PNG.');
  if (bytes.length > MAX_PHOTO_BYTES) throw badRequest('La photo est trop lourde (300 Ko maximum).');
  return value;
}

module.exports = {
  photo,
  frDateToSql,
  frDateTimeToSql,
  sqlDateToFr,
  sqlDateTimeToFr,
  text,
  optionalRef,
  amount,
  integer,
  bool,
  list,
  oneOf,
};
