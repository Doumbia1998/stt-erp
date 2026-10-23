const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const { ApiError, forbidden } = require('./errors');

const SESSION_HOURS = 12;
const BCRYPT_ROUNDS = 11;
const MAX_FAILURES = 5;
const LOCK_MINUTES = 15;
const MIN_PASSWORD_LENGTH = 8;
const ADMIN_ROLE = 'Administrateur';
const MODULES = [
  'Gestion',
  'Prestation',
  'Recouvrement',
  'Transport',
  'Transitaire',
  'Comptabilité',
  'RH & Paie',
  'Frontière',
  'Bureau DD',
  'Enquête',
];

// Sert à comparer un mot de passe même quand l'identifiant n'existe pas (temps constant).
const dummyHash = bcrypt.hashSync('mot-de-passe-factice', BCRYPT_ROUNDS);

const hashPassword = (password) => bcrypt.hash(password, BCRYPT_ROUNDS);
const hashToken = (token) =>
  crypto.createHash('sha256').update(token).digest('hex');
const normalizeLogin = (login) =>
  String(login ?? '').trim().toLowerCase().replace(/\s+/g, ' ');

// Tentatives échouées par identifiant (mémoire du processus, suffisant pour une instance).
const failures = new Map();

function lockedUntil(key) {
  const entry = failures.get(key);
  if (!entry || entry.count < MAX_FAILURES) return null;
  if (entry.until > Date.now()) return entry.until;
  failures.delete(key);
  return null;
}

function recordFailure(key) {
  const entry = failures.get(key) ?? { count: 0, until: 0 };
  entry.count += 1;
  if (entry.count >= MAX_FAILURES) {
    entry.until = Date.now() + LOCK_MINUTES * 60 * 1000;
  }
  failures.set(key, entry);
}

const publicUser = (row) => ({
  id: row.id,
  nom: row.nom,
  identifiant: row.identifiant,
  role: row.role,
  modules: row.modules,
  photo: row.photo ?? null,
});

async function login(pool, identifiant, motDePasse) {
  const key = normalizeLogin(identifiant);
  if (!key || typeof motDePasse !== 'string' || motDePasse === '') {
    throw new ApiError(400, 'Identifiant et mot de passe obligatoires.');
  }
  if (lockedUntil(key)) {
    throw new ApiError(
      429,
      `Trop de tentatives. Réessayez dans ${LOCK_MINUTES} minutes.`,
    );
  }
  const { rows } = await pool.query(
    'SELECT * FROM utilisateurs WHERE lower(identifiant) = $1',
    [key],
  );
  const user = rows[0];
  const valid = await bcrypt.compare(
    motDePasse,
    user?.mot_de_passe_hash ?? dummyHash,
  );
  if (!user || !valid) {
    recordFailure(key);
    throw new ApiError(401, 'Identifiant ou mot de passe incorrect.');
  }
  failures.delete(key);
  const token = crypto.randomBytes(32).toString('base64url');
  await pool.query(
    `INSERT INTO sessions (jeton_hash, utilisateur_id, expire_le)
     VALUES ($1, $2, now() + make_interval(hours => $3))`,
    [hashToken(token), user.id, SESSION_HOURS],
  );
  await pool.query('DELETE FROM sessions WHERE expire_le < now()');
  return { jeton: token, utilisateur: publicUser(user) };
}

function requireAuth(pool) {
  return async (req, res, next) => {
    try {
      const header = req.get('authorization') ?? '';
      const token = header.startsWith('Bearer ') ? header.slice(7) : '';
      if (!token) throw new ApiError(401, 'Session absente. Reconnectez-vous.');
      const { rows } = await pool.query(
        `SELECT u.* FROM sessions s
         JOIN utilisateurs u ON u.id = s.utilisateur_id
         WHERE s.jeton_hash = $1 AND s.expire_le > now()`,
        [hashToken(token)],
      );
      if (rows.length === 0) {
        throw new ApiError(401, 'Session expirée. Reconnectez-vous.');
      }
      req.user = publicUser(rows[0]);
      req.tokenHash = hashToken(token);
      next();
    } catch (error) {
      next(error);
    }
  };
}

const isAdmin = (user) => user.role === ADMIN_ROLE;

// Autorise l'administrateur, ou tout utilisateur ayant accès à l'un des modules donnés.
function requireModule(...modules) {
  return (req, _res, next) => {
    if (isAdmin(req.user) || modules.some((m) => req.user.modules.includes(m))) {
      return next();
    }
    next(forbidden(`Accès réservé au(x) module(s) : ${modules.join(', ')}.`));
  };
}

function requireAdmin(req, _res, next) {
  if (isAdmin(req.user)) return next();
  next(forbidden('Réservé aux administrateurs.'));
}

// Crée le premier compte « admin » si la base ne contient encore aucun utilisateur.
async function ensureInitialAdmin(pool, log = console.log) {
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM utilisateurs');
  if (rows[0].n > 0) return;
  let password = process.env.ADMIN_INITIAL_PASSWORD;
  if (!password || password.length < MIN_PASSWORD_LENGTH) {
    password = crypto.randomBytes(9).toString('base64url');
    log(
      `Aucun utilisateur : compte « admin » créé avec le mot de passe temporaire ${password} — changez-le depuis l’ERP.`,
    );
  } else {
    log('Aucun utilisateur : compte « admin » créé avec ADMIN_INITIAL_PASSWORD.');
  }
  await pool.query(
    `INSERT INTO utilisateurs (id, nom, identifiant, mot_de_passe_hash, role, modules)
     VALUES ('admin', 'Administrateur', 'admin', $1, $2, $3)
     ON CONFLICT DO NOTHING`,
    [await hashPassword(password), ADMIN_ROLE, MODULES],
  );
}

module.exports = {
  ADMIN_ROLE,
  MODULES,
  MIN_PASSWORD_LENGTH,
  hashPassword,
  normalizeLogin,
  publicUser,
  login,
  requireAuth,
  requireModule,
  requireAdmin,
  isAdmin,
  ensureInitialAdmin,
};
