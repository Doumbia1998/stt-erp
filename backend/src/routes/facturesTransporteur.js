const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict, notFound } = require('../errors');
const { requireModule } = require('../auth');
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

const MODULES = ['Prestation', 'Transport', 'Comptabilité', 'Recouvrement'];
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;
const round = (value) => Math.round(value * 100) / 100;

async function loadFacturesTransporteur(db) {
  const [factures, lignes, reglements] = await Promise.all([
    db.query(`SELECT *, ${saisieSql('cree_le')} AS saisie FROM factures_transporteur ORDER BY numero`),
    db.query('SELECT * FROM facture_transporteur_lignes ORDER BY facture_id, position'),
    db.query(
      `SELECT *, ${saisieSql('saisi_le')} AS saisie FROM facture_transporteur_reglements ORDER BY id`,
    ),
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
    transporteurId: f.transporteur_id ?? '',
    plaque: f.plaque,
    dateEmission: sqlDateToFr(f.date_emission),
    observations: f.observations,
    montant: f.montant,
    avance: f.avance,
    journalAvance: f.journal_avance ?? '',
    version: f.version,
    auteur: f.auteur,
    dateSaisie: f.saisie,
    lignes: (lignesBy.get(f.id) ?? []).map((l) => ({
      dossierId: l.dossier_id ?? '',
      bl: l.bl,
      numeroConteneur: l.numero_conteneur,
      montant: l.montant,
    })),
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
  const lignes = list(b, 'lignes', { max: 500 }).map((l) => ({
    dossierId: optionalRef(l, 'dossierId'),
    bl: text(l, 'bl'),
    numeroConteneur: text(l, 'numeroConteneur').toUpperCase(),
    montant: amount(l, 'montant', { min: 0 }),
  }));
  if (lignes.length === 0) throw badRequest('La facture doit contenir au moins un conteneur.');
  const montant = round(lignes.reduce((s, l) => s + l.montant, 0));
  const avance = amount(b, 'avance', { min: 0 });
  if (avance > montant + 0.001) {
    throw badRequest('L’avance camion dépasse le montant de la facture.');
  }
  const dateEmission = frDateToSql(b.dateEmission, 'dateEmission');
  if (!dateEmission) throw badRequest('La date de facture est obligatoire.');
  return {
    reference: text(b, 'reference', { required: true, max: 120 }),
    transporteurId: text(b, 'transporteurId', { required: true }),
    plaque: text(b, 'plaque', { max: 30 }).toUpperCase(),
    dateEmission,
    observations: text(b, 'observations', { max: 5000 }),
    journalAvance: optionalRef(b, 'journalAvance'),
    version: b.version === undefined || b.version === null ? 0 : integer(b, 'version'),
    montant,
    avance,
    lignes,
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
    'SELECT version, montant, avance FROM factures_transporteur WHERE id = $1 FOR UPDATE',
    [id],
  );
  const existing = rows[0];
  const { rows: oldPayments } = await client.query(
    `SELECT uid, montant, to_char(date, 'YYYY-MM-DD HH24:MI:SS') AS date
     FROM facture_transporteur_reglements WHERE facture_id = $1`,
    [id],
  );
  if (existing && existing.version !== f.version) {
    throw conflict(
      'Cette facture a été modifiée par un autre utilisateur. Rechargez la page pour récupérer la dernière version.',
    );
  }
  // Une facture déjà réglée ne change plus : seuls ses règlements évoluent.
  const locked = existing && oldPayments.length > 0 && f.reglements.length > 0;
  if (locked && (existing.montant !== f.montant || existing.avance !== f.avance)) {
    throw conflict('Cette facture a déjà des règlements : elle ne peut plus être modifiée.');
  }
  const paid = f.reglements.reduce((s, r) => s + r.montant, 0);
  if (paid > f.montant - f.avance + 0.001) {
    throw badRequest('Le total des règlements dépasse le net à payer (montant moins avance).');
  }
  let saved;
  if (existing) {
    if (!locked) {
      await client.query('DELETE FROM facture_transporteur_lignes WHERE facture_id = $1', [id]);
    }
    ({ rows: [saved] } = await client.query(
      locked
        ? `UPDATE factures_transporteur SET version = version + 1, modifie_le = now()
           WHERE id = $1 RETURNING version, numero`
        : `UPDATE factures_transporteur SET reference = $2, transporteur_id = $3, plaque = $4,
             date_emission = $5, observations = $6, montant = $7, avance = $8,
             journal_avance = $9, version = version + 1, modifie_le = now()
           WHERE id = $1 RETURNING version, numero`,
      locked
        ? [id]
        : [id, f.reference, f.transporteurId, f.plaque, f.dateEmission, f.observations,
            f.montant, f.avance, f.journalAvance],
    ));
  } else {
    ({ rows: [saved] } = await client.query(
      `INSERT INTO factures_transporteur (id, reference, transporteur_id, plaque, date_emission,
         observations, montant, avance, journal_avance, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING version, numero`,
      [id, f.reference, f.transporteurId, f.plaque, f.dateEmission, f.observations,
        f.montant, f.avance, f.journalAvance, user.nom],
    ));
  }
  if (!locked) {
    for (const [position, l] of f.lignes.entries()) {
      await client.query(
        `INSERT INTO facture_transporteur_lignes (facture_id, position, dossier_id, bl,
           numero_conteneur, montant)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [id, position, l.dossierId, l.bl, l.numeroConteneur, l.montant],
      );
    }
  }
  // Règlements : ajout ou suppression, jamais de modification.
  const incoming = new Map(f.reglements.map((r) => [r.id, r]));
  for (const old of oldPayments) {
    const next = incoming.get(old.uid);
    if (!next) {
      await client.query(
        'DELETE FROM facture_transporteur_reglements WHERE facture_id = $1 AND uid = $2',
        [id, old.uid],
      );
    } else if (next.montant !== old.montant || next.date !== old.date) {
      throw conflict('Un règlement déjà enregistré ne peut pas être modifié.');
    }
  }
  const known = new Set(oldPayments.map((p) => p.uid));
  for (const r of f.reglements) {
    if (known.has(r.id)) continue;
    await client.query(
      `INSERT INTO facture_transporteur_reglements (facture_id, uid, date, montant, code_journal,
         mode_paiement, numero_cheque, observations, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, r.id, r.date, r.montant, r.codeJournal, r.modePaiement, r.numeroCheque, r.observations, user.nom],
    );
  }
  return { id, version: saved.version, numero: Number(saved.numero), montant: f.montant };
}

function facturesTransporteurRouter(pool) {
  const router = express.Router();

  router.put('/factures-transporteur/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      const facture = parseFacture(req.body);
      res.json(await withTransaction(pool, (client) => saveFacture(client, id, facture, req.user)));
    } catch (error) {
      if (error.constraint === 'facture_transporteur_lignes_conteneur') {
        return next(conflict('Un des conteneurs est déjà facturé dans une autre facture transporteur.'));
      }
      next(error);
    }
  });

  router.delete('/factures-transporteur/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      await withTransaction(pool, async (client) => {
        const { rows } = await client.query(
          `SELECT (SELECT count(*) FROM facture_transporteur_reglements WHERE facture_id = $1)::int AS n,
             EXISTS (SELECT 1 FROM factures_transporteur WHERE id = $1) AS exists`,
          [id],
        );
        if (!rows[0].exists) throw notFound('Facture introuvable.');
        if (rows[0].n > 0) throw conflict('Cette facture a des règlements : supprimez-les d’abord.');
        await client.query('DELETE FROM factures_transporteur WHERE id = $1', [id]);
      });
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = { facturesTransporteurRouter, loadFacturesTransporteur };
