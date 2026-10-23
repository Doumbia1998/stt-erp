const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict, forbidden, notFound } = require('../errors');
const { isAdmin, requireModule } = require('../auth');
const {
  text,
  optionalRef,
  amount,
  integer,
  list,
  frDateToSql,
  frDateTimeToSql,
  sqlDateToFr,
  sqlDateTimeToFr,
} = require('../format');
const { MODULES_VOYAGE } = require('./voyageAffectations');

// La Direction règle les factures des agents (Frontière, Bureau DD, Enquête).
const DIRECTION_ROLES = ['Direction', 'Gérant', 'Comptable'];
const isDirection = (user) =>
  isAdmin(user) ||
  DIRECTION_ROLES.includes(user.role) ||
  user.modules.includes('Comptabilité');

const round = (value) => Math.round(value * 100) / 100;
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;

async function loadFacturesAgent(db) {
  const [factures, lignes, reglements] = await Promise.all([
    db.query(`SELECT *, ${saisieSql('cree_le')} AS saisie FROM factures_agent ORDER BY numero`),
    db.query(
      'SELECT id, facture_id FROM voyage_affectations WHERE facture_id IS NOT NULL ORDER BY date_depart, id',
    ),
    db.query(`SELECT *, ${saisieSql('saisi_le')} AS saisie FROM facture_agent_reglements ORDER BY id`),
  ]);
  const group = (rows) => {
    const map = new Map();
    for (const row of rows) {
      if (!map.has(row.facture_id)) map.set(row.facture_id, []);
      map.get(row.facture_id).push(row);
    }
    return map;
  };
  const lignesBy = group(lignes.rows);
  const reglementsBy = group(reglements.rows);
  return factures.rows.map((f) => ({
    id: f.id,
    numero: Number(f.numero),
    reference: f.reference,
    module: f.module,
    agentId: f.agent_id ?? '',
    agentNom: f.agent_nom,
    dateEmission: sqlDateToFr(f.date_emission),
    observations: f.observations,
    montant: f.montant,
    auteur: f.auteur,
    dateSaisie: f.saisie,
    version: f.version,
    affectations: (lignesBy.get(f.id) ?? []).map((l) => l.id),
    reglements: (reglementsBy.get(f.id) ?? []).map((r) => ({
      id: r.uid,
      date: sqlDateTimeToFr(r.date),
      montant: r.montant,
      codeJournal: r.code_journal ?? '',
      modePaiement: r.mode_paiement,
      numeroCheque: r.numero_cheque,
      observations: r.observations,
      auteur: r.auteur,
      saisiLe: r.saisie,
    })),
  }));
}

function parseFacture(b) {
  const module = text(b, 'module', { required: true });
  if (!MODULES_VOYAGE.includes(module)) throw badRequest('Module inconnu.');
  const affectations = list(b, 'affectations', { max: 2000 }).map((id) => {
    if (typeof id !== 'string' || !id) throw badRequest('Saisie de voyage invalide.');
    return id;
  });
  if (affectations.length === 0) throw badRequest('Cochez au moins une saisie validée.');
  const dateEmission = frDateToSql(b.dateEmission, 'dateEmission');
  if (!dateEmission) throw badRequest('La date de facture est obligatoire.');
  return {
    module,
    reference: text(b, 'reference', { required: true, max: 120 }),
    agentId: optionalRef(b, 'agentId'),
    agentNom: text(b, 'agentNom', { max: 200 }),
    dateEmission,
    observations: text(b, 'observations', { max: 5000 }),
    version: b.version === undefined || b.version === null ? 0 : integer(b, 'version'),
    affectations: [...new Set(affectations)],
    reglements: list(b, 'reglements', { max: 1000 }).map((r) => ({
      id: text(r, 'id', { required: true, max: 120 }),
      date: frDateTimeToSql(r.date, 'date'),
      montant: amount(r, 'montant', { min: 0.01 }),
      codeJournal: optionalRef(r, 'codeJournal'),
      modePaiement: text(r, 'modePaiement'),
      numeroCheque: text(r, 'numeroCheque'),
      observations: text(r, 'observations', { max: 2000 }),
    })),
  };
}

async function saveFacture(client, id, f, user) {
  const { rows } = await client.query(
    'SELECT version, module FROM factures_agent WHERE id = $1 FOR UPDATE',
    [id],
  );
  const existing = rows[0];
  if (existing && existing.version !== f.version) {
    throw conflict('Cette facture a été modifiée par un autre utilisateur. Rechargez la page.');
  }
  if (existing && existing.module !== f.module) throw badRequest('Le module d’une facture ne change pas.');
  const { rows: oldPayments } = await client.query(
    `SELECT uid, montant, to_char(date, 'YYYY-MM-DD HH24:MI:SS') AS date
     FROM facture_agent_reglements WHERE facture_id = $1`,
    [id],
  );
  const { rows: oldLines } = await client.query(
    'SELECT id FROM voyage_affectations WHERE facture_id = $1 ORDER BY id',
    [id],
  );
  const sameLines =
    JSON.stringify(oldLines.map((l) => l.id).sort()) === JSON.stringify([...f.affectations].sort());
  const paymentsChanged =
    oldPayments.length !== f.reglements.length ||
    f.reglements.some((r) => !oldPayments.some((p) => p.uid === r.id));
  // Seule la Direction enregistre ou supprime un règlement.
  if (paymentsChanged && !isDirection(user)) {
    throw forbidden('Les règlements des agents sont saisis par la Direction.');
  }
  if (existing && oldPayments.length > 0 && !sameLines) {
    throw conflict('Cette facture a déjà des règlements : elle ne peut plus être modifiée.');
  }
  // Les saisies facturées : du module, validées, pas déjà sur une autre facture.
  const { rows: lines } = await client.query(
    `SELECT id, module, statut, total, facture_id FROM voyage_affectations
     WHERE id = ANY($1::text[]) FOR UPDATE`,
    [f.affectations],
  );
  if (lines.length !== f.affectations.length) throw badRequest('Une saisie de voyage est introuvable.');
  for (const l of lines) {
    if (l.module !== f.module) throw badRequest('Toutes les saisies doivent être du même module.');
    if (l.statut !== 'Validé') throw badRequest('Seules les saisies validées peuvent être facturées.');
    if (l.facture_id && l.facture_id !== id) {
      throw conflict('Une des saisies est déjà facturée dans une autre facture.');
    }
  }
  const montant = round(lines.reduce((s, l) => s + Number(l.total), 0));
  const paid = f.reglements.reduce((s, r) => s + r.montant, 0);
  if (paid > montant + 0.001) throw badRequest('Le total des règlements dépasse le montant de la facture.');

  let saved;
  if (existing) {
    ({ rows: [saved] } = await client.query(
      `UPDATE factures_agent SET reference = $2, agent_id = $3, agent_nom = $4, date_emission = $5,
         observations = $6, montant = $7, version = version + 1, modifie_le = now()
       WHERE id = $1 RETURNING version, numero`,
      [id, f.reference, f.agentId, f.agentNom, f.dateEmission, f.observations, montant],
    ));
  } else {
    ({ rows: [saved] } = await client.query(
      `INSERT INTO factures_agent (id, reference, module, agent_id, agent_nom, date_emission,
         observations, montant, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING version, numero`,
      [id, f.reference, f.module, f.agentId, f.agentNom, f.dateEmission, f.observations, montant, user.nom],
    ));
  }
  if (!sameLines) {
    await client.query('UPDATE voyage_affectations SET facture_id = NULL WHERE facture_id = $1', [id]);
    await client.query(
      'UPDATE voyage_affectations SET facture_id = $1 WHERE id = ANY($2::text[])',
      [id, f.affectations],
    );
  }
  const incoming = new Map(f.reglements.map((r) => [r.id, r]));
  for (const old of oldPayments) {
    const next = incoming.get(old.uid);
    if (!next) {
      await client.query('DELETE FROM facture_agent_reglements WHERE facture_id = $1 AND uid = $2', [
        id,
        old.uid,
      ]);
    } else if (next.montant !== old.montant || next.date !== old.date) {
      throw conflict('Un règlement déjà enregistré ne peut pas être modifié.');
    }
  }
  const known = new Set(oldPayments.map((p) => p.uid));
  for (const r of f.reglements) {
    if (known.has(r.id)) continue;
    await client.query(
      `INSERT INTO facture_agent_reglements (facture_id, uid, date, montant, code_journal,
         mode_paiement, numero_cheque, observations, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, r.id, r.date, r.montant, r.codeJournal, r.modePaiement, r.numeroCheque, r.observations, user.nom],
    );
  }
  return { id, version: saved.version, numero: Number(saved.numero), montant };
}

function facturesAgentRouter(pool) {
  const router = express.Router();
  const allowed = requireModule(...MODULES_VOYAGE, 'Transport', 'Comptabilité');
  const canUse = (user, module) =>
    isDirection(user) || user.modules.includes('Transport') || user.modules.includes(module);

  router.put('/factures-agent/:id', allowed, async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      const facture = parseFacture(req.body ?? {});
      if (!canUse(req.user, facture.module)) throw forbidden(`Accès réservé au module ${facture.module}.`);
      res.json(await withTransaction(pool, (client) => saveFacture(client, id, facture, req.user)));
    } catch (error) {
      if (error.constraint === 'factures_agent_reference') {
        return next(conflict('Ce numéro de facture existe déjà.'));
      }
      next(error);
    }
  });

  router.delete('/factures-agent/:id', allowed, async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      await withTransaction(pool, async (client) => {
        const { rows } = await client.query(
          `SELECT module, (SELECT count(*) FROM facture_agent_reglements WHERE facture_id = $1)::int AS n
           FROM factures_agent WHERE id = $1`,
          [id],
        );
        if (!rows[0]) throw notFound('Facture introuvable.');
        if (!canUse(req.user, rows[0].module)) throw forbidden('Accès refusé.');
        if (rows[0].n > 0) throw conflict('Cette facture a des règlements : elle ne peut pas être supprimée.');
        await client.query('DELETE FROM factures_agent WHERE id = $1', [id]);
      });
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = { facturesAgentRouter, loadFacturesAgent, isDirection };
