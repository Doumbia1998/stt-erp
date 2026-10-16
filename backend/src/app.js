const express = require('express');
const { ApiError, fromDatabaseError } = require('./errors');
const { login, requireAuth, isAdmin, publicUser } = require('./auth');
const {
  referentielsRouter,
  clientJson,
  prestataireJson,
  compteJson,
  journalJson,
  voyageJson,
  modeReglementJson,
  typeFraisJson,
} = require('./routes/referentiels');
const { comptabiliteRouter } = require('./routes/comptabilite');
const {
  facturesTransitaireRouter,
  loadFacturesTransitaire,
} = require('./routes/facturesTransitaire');
const { dossiersRouter, loadDossiers } = require('./routes/dossiers');

function createApp({ pool, corsOrigins = process.env.CORS_ORIGINS }) {
  const app = express();
  const allowedOrigins = new Set(
    (corsOrigins || '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  );

  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(express.json({ limit: '5mb' }));

  app.use((req, res, next) => {
    const origin = req.get('origin');
    if (origin && allowedOrigins.has(origin)) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Vary', 'Origin');
      res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
      res.set('Access-Control-Allow-Headers', 'Content-Type,Authorization');
    }

    if (req.method === 'OPTIONS') {
      return res.sendStatus(origin && allowedOrigins.has(origin) ? 204 : 403);
    }

    next();
  });

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', service: 'stt-erp-api' });
  });

  app.get('/ready', async (_req, res, next) => {
    if (!pool) {
      return res.status(503).json({
        status: 'not_ready',
        reason: 'DATABASE_URL is not configured',
      });
    }

    try {
      await pool.query('SELECT 1');
      return res.json({ status: 'ready', database: 'connected' });
    } catch (error) {
      return next(error);
    }
  });

  app.get('/api/v1', (_req, res) => {
    res.json({ service: 'stt-erp-api', version: 'v1' });
  });

  const api = express.Router();
  api.use((_req, _res, next) =>
    next(pool ? undefined : new ApiError(503, 'Base de données non configurée.')),
  );

  api.post('/auth/connexion', async (req, res, next) => {
    try {
      res.json(await login(pool, req.body?.identifiant, req.body?.motDePasse));
    } catch (error) {
      next(error);
    }
  });

  api.use((req, res, next) => requireAuth(pool)(req, res, next));

  api.post('/auth/deconnexion', async (req, res, next) => {
    try {
      await pool.query('DELETE FROM sessions WHERE jeton_hash = $1', [req.tokenHash]);
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  // Toutes les données de l'ERP, chargées après la connexion.
  api.get('/donnees', async (req, res, next) => {
    try {
      const [clients, prestataires, comptes, journaux, voyages, dossiers, users, modes, frais,
        vehicules, facturesTransitaire] =
        await Promise.all([
          pool.query('SELECT * FROM clients ORDER BY cree_le, id'),
          pool.query('SELECT * FROM prestataires ORDER BY cree_le, id'),
          pool.query('SELECT * FROM plan_comptable ORDER BY code'),
          pool.query('SELECT * FROM journaux ORDER BY cree_le, code'),
          pool.query('SELECT * FROM voyages ORDER BY cree_le, id'),
          loadDossiers(pool),
          isAdmin(req.user)
            ? pool.query('SELECT * FROM utilisateurs ORDER BY cree_le, id')
            : { rows: [] },
          pool.query('SELECT * FROM modes_reglement ORDER BY lower(intitule)'),
          pool.query('SELECT * FROM types_frais ORDER BY lower(libelle)'),
          pool.query('SELECT * FROM vehicules ORDER BY transporteur_id, position'),
          loadFacturesTransitaire(pool),
        ]);
      const vehiculesBy = new Map();
      for (const v of vehicules.rows) {
        if (!vehiculesBy.has(v.transporteur_id)) vehiculesBy.set(v.transporteur_id, []);
        vehiculesBy.get(v.transporteur_id).push(v);
      }
      res.json({
        utilisateur: req.user,
        utilisateurs: users.rows.map(publicUser),
        clients: clients.rows.map(clientJson),
        prestataires: prestataires.rows.map((p) =>
          prestataireJson(p, vehiculesBy.get(p.id) ?? []),
        ),
        comptes: comptes.rows.map(compteJson),
        journaux: journaux.rows.map(journalJson),
        voyages: voyages.rows.map(voyageJson),
        modesReglement: modes.rows.map(modeReglementJson),
        typesFrais: frais.rows.map(typeFraisJson),
        facturesTransitaire,
        dossiers,
      });
    } catch (error) {
      next(error);
    }
  });

  api.use(referentielsRouter(pool));
  api.use(dossiersRouter(pool));
  api.use(comptabiliteRouter(pool));
  api.use(facturesTransitaireRouter(pool));
  app.use('/api/v1', api);

  app.use((_req, res) => {
    res.status(404).json({ error: 'Route introuvable' });
  });

  app.use((error, _req, res, _next) => {
    if (error instanceof SyntaxError && 'body' in error) {
      return res.status(400).json({ error: 'Corps JSON invalide' });
    }
    const known = error instanceof ApiError ? error : fromDatabaseError(error);
    if (known) {
      return res.status(known.status).json({ error: known.message });
    }

    console.error('Erreur API :', error);
    return res.status(500).json({ error: 'Erreur interne du serveur' });
  });

  return app;
}

module.exports = { createApp };
