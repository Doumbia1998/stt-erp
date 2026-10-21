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

const MODULES = ['Prestation', 'Transitaire', 'Comptabilité', 'Recouvrement'];
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;

const lineAmount = (l) =>
  l.frais_transit + l.surestaries_magasinage + l.volume_poids + l.autres_frais + l.frais_peage;

async function loadFacturesTransitaire(db) {
  const [factures, lignes, reglements] = await Promise.all([
    db.query(`SELECT *, ${saisieSql('cree_le')} AS saisie FROM factures_transitaire ORDER BY numero`),
    db.query('SELECT * FROM facture_transitaire_lignes ORDER BY facture_id, position'),
    db.query(
      `SELECT *, ${saisieSql('saisi_le')} AS saisie FROM facture_transitaire_reglements ORDER BY id`,
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
    transitaireId: f.transitaire_id ?? '',
    dateEmission: sqlDateToFr(f.date_emission),
    observations: f.observations,
    montant: f.montant,
    version: f.version,
    auteur: f.auteur,
    dateSaisie: f.saisie,
    lignes: (lignesBy.get(f.id) ?? []).map((l) => ({
      dossierId: l.dossier_id ?? '',
      bl: l.bl,
      numeroConteneur: l.numero_conteneur,
      marchandise: l.marchandise,
      typeConteneur: l.type_conteneur,
      dateDepart: sqlDateToFr(l.date_depart),
      transporteurId: l.transporteur_id ?? '',
      plaque: l.plaque,
      telephoneChauffeur: l.telephone_chauffeur,
      fraisTransit: l.frais_transit,
      surestariesMagasinage: l.surestaries_magasinage,
      volumePoids: l.volume_poids,
      autresFrais: l.autres_frais,
      fraisPeage: l.frais_peage,
      montantTransport: l.montant_transport,
      avanceCamion: l.avance_camion,
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
  const lignes = list(b, 'lignes', { max: 2000 }).map((l) => ({
    dossierId: optionalRef(l, 'dossierId'),
    bl: text(l, 'bl'),
    numeroConteneur: text(l, 'numeroConteneur').toUpperCase(),
    marchandise: text(l, 'marchandise'),
    typeConteneur: text(l, 'typeConteneur'),
    dateDepart: frDateToSql(l.dateDepart, 'dateDepart'),
    transporteurId: optionalRef(l, 'transporteurId'),
    plaque: text(l, 'plaque').toUpperCase(),
    telephoneChauffeur: text(l, 'telephoneChauffeur'),
    frais_transit: amount(l, 'fraisTransit', { min: 0 }),
    surestaries_magasinage: amount(l, 'surestariesMagasinage', { min: 0 }),
    volume_poids: amount(l, 'volumePoids', { min: 0 }),
    autres_frais: amount(l, 'autresFrais', { min: 0 }),
    frais_peage: amount(l, 'fraisPeage', { min: 0 }),
    montantTransport: amount(l, 'montantTransport', { min: 0 }),
    avanceCamion: amount(l, 'avanceCamion', { min: 0 }),
  }));
  if (lignes.length === 0) throw badRequest('La facture doit contenir au moins un conteneur.');
  const reglements = list(b, 'reglements', { max: 1000 }).map((r) => ({
    id: text(r, 'id', { required: true, max: 120 }),
    date: frDateTimeToSql(r.date, 'date'),
    montant: amount(r, 'montant', { min: 0.01 }),
    codeJournal: optionalRef(r, 'codeJournal'),
    modePaiement: text(r, 'modePaiement'),
    numeroCheque: text(r, 'numeroCheque'),
    observations: text(r, 'observations', { max: 2000 }),
  }));
  const dateEmission = frDateToSql(b.dateEmission, 'dateEmission');
  if (!dateEmission) throw badRequest('La date de facture est obligatoire.');
  return {
    reference: text(b, 'reference', { required: true, max: 120 }),
    transitaireId: text(b, 'transitaireId', { required: true }),
    dateEmission,
    observations: text(b, 'observations', { max: 5000 }),
    version: b.version === undefined || b.version === null ? 0 : integer(b, 'version'),
    lignes,
    reglements,
    // L'avance camion payée par le transitaire lui est due en plus de ses frais.
    montant:
      Math.round(lignes.reduce((s, l) => s + lineAmount(l) + l.avanceCamion, 0) * 100) / 100,
  };
}

async function saveFacture(client, id, f, user) {
  const { rows } = await client.query(
    'SELECT version, montant FROM factures_transitaire WHERE id = $1 FOR UPDATE',
    [id],
  );
  const existing = rows[0];
  const { rows: oldPayments } = await client.query(
    `SELECT uid, montant, to_char(date, 'YYYY-MM-DD HH24:MI:SS') AS date
     FROM facture_transitaire_reglements WHERE facture_id = $1`,
    [id],
  );
  if (existing && existing.version !== f.version) {
    throw conflict(
      'Cette facture a été modifiée par un autre utilisateur. Rechargez la page pour récupérer la dernière version.',
    );
  }
  // Une facture déjà réglée ne change plus : seuls ses règlements évoluent.
  const locked = existing && oldPayments.length > 0 && f.reglements.length > 0;
  if (locked && existing.montant !== f.montant) {
    throw conflict('Cette facture a déjà des règlements : elle ne peut plus être modifiée.');
  }
  const paid = f.reglements.reduce((s, r) => s + r.montant, 0);
  if (paid > f.montant + 0.001) {
    throw badRequest('Le total des règlements dépasse le montant de la facture.');
  }
  let version;
  if (existing) {
    if (!locked) {
      await client.query('DELETE FROM facture_transitaire_lignes WHERE facture_id = $1', [id]);
    }
    const updated = await client.query(
      locked
        ? `UPDATE factures_transitaire SET version = version + 1, modifie_le = now()
           WHERE id = $1 RETURNING version, numero`
        : `UPDATE factures_transitaire SET reference = $2, transitaire_id = $3,
             date_emission = $4, observations = $5, montant = $6,
             version = version + 1, modifie_le = now()
           WHERE id = $1 RETURNING version, numero`,
      locked
        ? [id]
        : [id, f.reference, f.transitaireId, f.dateEmission, f.observations, f.montant],
    );
    version = updated.rows[0];
  } else {
    const inserted = await client.query(
      `INSERT INTO factures_transitaire (id, reference, transitaire_id, date_emission,
         observations, montant, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING version, numero`,
      [id, f.reference, f.transitaireId, f.dateEmission, f.observations, f.montant, user.nom],
    );
    version = inserted.rows[0];
  }
  if (!locked) {
    for (const [position, l] of f.lignes.entries()) {
      await client.query(
        `INSERT INTO facture_transitaire_lignes (facture_id, position, dossier_id, bl,
           numero_conteneur, marchandise, type_conteneur, date_depart, transporteur_id,
           plaque, telephone_chauffeur, frais_transit, surestaries_magasinage, volume_poids,
           autres_frais, frais_peage, montant_transport, avance_camion)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`,
        [
          id, position, l.dossierId, l.bl, l.numeroConteneur, l.marchandise, l.typeConteneur,
          l.dateDepart, l.transporteurId, l.plaque, l.telephoneChauffeur, l.frais_transit,
          l.surestaries_magasinage, l.volume_poids, l.autres_frais, l.frais_peage,
          l.montantTransport, l.avanceCamion,
        ],
      );
    }
  }

  // Règlements : ajout ou suppression, jamais de modification.
  const incoming = new Map(f.reglements.map((r) => [r.id, r]));
  for (const old of oldPayments) {
    const next = incoming.get(old.uid);
    if (!next) {
      await client.query(
        'DELETE FROM facture_transitaire_reglements WHERE facture_id = $1 AND uid = $2',
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
      `INSERT INTO facture_transitaire_reglements (facture_id, uid, date, montant, code_journal,
         mode_paiement, numero_cheque, observations, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, r.id, r.date, r.montant, r.codeJournal, r.modePaiement, r.numeroCheque, r.observations, user.nom],
    );
  }
  return { id, version: version.version, numero: Number(version.numero), montant: f.montant };
}

function facturesTransitaireRouter(pool) {
  const router = express.Router();

  router.put('/factures-transitaire/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      const facture = parseFacture(req.body);
      res.json(await withTransaction(pool, (client) => saveFacture(client, id, facture, req.user)));
    } catch (error) {
      if (error.constraint === 'facture_transitaire_lignes_conteneur') {
        return next(conflict('Un des conteneurs est déjà facturé dans une autre facture transitaire.'));
      }
      next(error);
    }
  });

  router.delete('/factures-transitaire/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      await withTransaction(pool, async (client) => {
        const { rows } = await client.query(
          `SELECT (SELECT count(*) FROM facture_transitaire_reglements WHERE facture_id = $1)::int AS n,
             EXISTS (SELECT 1 FROM factures_transitaire WHERE id = $1) AS exists`,
          [id],
        );
        if (!rows[0].exists) throw notFound('Facture introuvable.');
        if (rows[0].n > 0) {
          throw conflict('Cette facture a des règlements : supprimez-les d’abord.');
        }
        await client.query('DELETE FROM factures_transitaire WHERE id = $1', [id]);
      });
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = { facturesTransitaireRouter, loadFacturesTransitaire };
