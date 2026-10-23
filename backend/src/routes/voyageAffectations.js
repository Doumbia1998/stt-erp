const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict, forbidden, notFound } = require('../errors');
const { isAdmin, requireModule } = require('../auth');
const { text, optionalRef, integer, frDateToSql, sqlDateToFr } = require('../format');

// Frais saisis par chaque module sur un voyage qui lui est affecté.
const FRAIS_PAR_MODULE = {
  Frontière: ['T1', 'Frais de passage', 'TS Frontière', 'Client'],
  'Bureau DD': ['Frais de circuit', 'DD conteneur ou camion', 'TS'],
  Enquête: ['Amende', 'LS', 'TS spécial', 'TS ordinaire'],
};
const MODULES_VOYAGE = Object.keys(FRAIS_PAR_MODULE);
// Le responsable des voyages affecte ; les agents des modules saisissent leurs frais.
const RESPONSABLE = 'Transport';

const round = (value) => Math.round(value * 100) / 100;
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;

const affectationJson = (r) => ({
  id: r.id,
  voyageCle: r.voyage_cle,
  module: r.module,
  agentId: r.agent_id ?? '',
  dateDepart: sqlDateToFr(r.date_depart),
  plaque: r.plaque,
  transporteur: r.transporteur,
  chauffeur: r.chauffeur,
  telephone: r.telephone,
  dossiers: r.dossiers,
  clients: r.clients,
  transitaire: r.transitaire,
  conteneurs: r.conteneurs,
  frais: r.frais ?? {},
  total: r.total,
  observations: r.observations,
  assignePar: r.assigne_par,
  saisiPar: r.saisi_par,
  saisiLe: r.saisie ?? '',
  version: r.version,
});

async function loadAffectations(db) {
  const { rows } = await db.query(
    `SELECT *, ${saisieSql('saisi_le')} AS saisie FROM voyage_affectations
     ORDER BY date_depart, cree_le, id`,
  );
  return rows.map(affectationJson);
}

function parseFrais(module, raw) {
  const allowed = FRAIS_PAR_MODULE[module];
  const frais = {};
  if (raw === undefined || raw === null) return frais;
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    throw badRequest('Les frais doivent être une liste de montants.');
  }
  for (const [label, value] of Object.entries(raw)) {
    if (!allowed.includes(label)) {
      throw badRequest(`Frais « ${label} » inconnu pour le module ${module}.`);
    }
    const amount = Number(value);
    if (!Number.isFinite(amount) || amount < 0) {
      throw badRequest(`Montant invalide pour « ${label} ».`);
    }
    if (amount > 0) frais[label] = round(amount);
  }
  return frais;
}

function voyageAffectationsRouter(pool) {
  const router = express.Router();

  router.put(
    '/voyage-affectations/:id',
    requireModule(RESPONSABLE, ...MODULES_VOYAGE),
    async (req, res, next) => {
      try {
        const b = req.body ?? {};
        const id = text(req.params, 'id', { required: true, max: 120 });
        const module = text(b, 'module', { required: true });
        if (!MODULES_VOYAGE.includes(module)) throw badRequest('Module de voyage inconnu.');
        const user = req.user;
        const responsable = isAdmin(user) || user.modules.includes(RESPONSABLE);
        if (!responsable && !user.modules.includes(module)) {
          throw forbidden(`Accès réservé au module ${module}.`);
        }
        const frais = parseFrais(module, b.frais);
        const total = round(Object.values(frais).reduce((s, v) => s + v, 0));
        const version = b.version === undefined || b.version === null ? 0 : integer(b, 'version');
        const saved = await withTransaction(pool, async (client) => {
          const { rows } = await client.query(
            'SELECT module, version, frais, total FROM voyage_affectations WHERE id = $1 FOR UPDATE',
            [id],
          );
          const existing = rows[0];
          if (existing && existing.version !== version) {
            throw conflict(
              'Ce voyage a été modifié par un autre utilisateur. Rechargez la page pour récupérer la dernière version.',
            );
          }
          if (existing && existing.module !== module) {
            throw badRequest('Le module d’une affectation ne change pas.');
          }
          const fraisChanged =
            !existing || JSON.stringify(existing.frais ?? {}) !== JSON.stringify(frais);
          if (!existing) {
            // Seul le responsable des voyages crée une affectation.
            if (!responsable) throw forbidden('Seul le responsable des voyages peut affecter un voyage.');
            const { rows: created } = await client.query(
              `INSERT INTO voyage_affectations (id, voyage_cle, module, agent_id, date_depart, plaque,
                 transporteur, chauffeur, telephone, dossiers, clients, transitaire, conteneurs,
                 frais, total, observations, assigne_par, saisi_par, saisi_le)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17,
                 $18, $19)
               RETURNING *, ${saisieSql('saisi_le')} AS saisie`,
              [
                id,
                text(b, 'voyageCle', { required: true, max: 200 }),
                module,
                optionalRef(b, 'agentId'),
                frDateToSql(b.dateDepart, 'dateDepart'),
                text(b, 'plaque', { max: 30 }).toUpperCase(),
                text(b, 'transporteur'),
                text(b, 'chauffeur'),
                text(b, 'telephone'),
                text(b, 'dossiers', { max: 2000 }),
                text(b, 'clients', { max: 2000 }),
                text(b, 'transitaire'),
                text(b, 'conteneurs', { max: 2000 }),
                JSON.stringify(frais),
                total,
                text(b, 'observations', { max: 5000 }),
                user.nom,
                total > 0 ? user.nom : '',
                total > 0 ? new Date() : null,
              ],
            );
            return created[0];
          }
          // Le responsable peut réaffecter l'agent ; l'agent ne touche qu'à ses frais.
          const { rows: updated } = await client.query(
            `UPDATE voyage_affectations SET
               agent_id = CASE WHEN $2 THEN $3 ELSE agent_id END,
               frais = $4, total = $5, observations = $6,
               saisi_par = CASE WHEN $7 THEN $8 ELSE saisi_par END,
               saisi_le = CASE WHEN $7 THEN now() ELSE saisi_le END,
               version = version + 1, modifie_le = now()
             WHERE id = $1
             RETURNING *, ${saisieSql('saisi_le')} AS saisie`,
            [
              id,
              responsable,
              optionalRef(b, 'agentId'),
              JSON.stringify(frais),
              total,
              text(b, 'observations', { max: 5000 }),
              fraisChanged,
              user.nom,
            ],
          );
          return updated[0];
        });
        res.json(affectationJson(saved));
      } catch (error) {
        if (error.constraint === 'voyage_affectations_voyage_cle_module_key') {
          return next(conflict('Ce voyage est déjà affecté à ce module.'));
        }
        next(error);
      }
    },
  );

  router.delete(
    '/voyage-affectations/:id',
    requireModule(RESPONSABLE),
    async (req, res, next) => {
      try {
        const id = text(req.params, 'id', { required: true, max: 120 });
        const { rows } = await pool.query('SELECT total FROM voyage_affectations WHERE id = $1', [id]);
        if (!rows[0]) throw notFound('Affectation introuvable.');
        if (rows[0].total > 0) {
          throw conflict('Des frais sont déjà saisis sur ce voyage : l’affectation ne peut plus être retirée.');
        }
        await pool.query('DELETE FROM voyage_affectations WHERE id = $1', [id]);
        res.status(204).end();
      } catch (error) {
        next(error);
      }
    },
  );

  return router;
}

module.exports = { voyageAffectationsRouter, loadAffectations, FRAIS_PAR_MODULE };
