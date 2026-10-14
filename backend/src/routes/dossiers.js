const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict } = require('../errors');
const { requireModule } = require('../auth');
const {
  text,
  optionalRef,
  amount,
  integer,
  list,
  oneOf,
  frDateToSql,
  frDateTimeToSql,
  sqlDateToFr,
  sqlDateTimeToFr,
} = require('../format');

const INVOICE_KINDS = ['client', 'provider', 'forwarder', 'carrier'];
const INVOICE_STATUSES = ['Brouillon', 'En cours', 'Clôturée'];
const DOSSIER_STATUSES = ['Ouvert', 'Clôturé'];
const OPERATION_TYPES = [
  'expense',
  'clientInvoice',
  'clientPayment',
  'providerInvoice',
  'providerAdvance',
  'providerPayment',
];
const CLOSED_INVOICE = 'Clôturée';
const CLOSED_DOSSIER = 'Clôturé';

// --- Lecture : reconstitue les dossiers complets tels que l'ERP les manipule ---

function groupBy(rows, key) {
  const groups = new Map();
  for (const row of rows) {
    if (!groups.has(row[key])) groups.set(row[key], []);
    groups.get(row[key]).push(row);
  }
  return groups;
}

const ligneJson = (r) => ({
  description: r.description,
  quantite: r.quantite,
  prixUnitaire: r.prix_unitaire,
  numeroConteneur: r.numero_conteneur,
  bl: r.bl,
  marchandise: r.marchandise,
  typeConteneur: r.type_conteneur,
  fraisTransit: r.frais_transit,
  volumePoids: r.volume_poids,
  surestariesMagasinage: r.surestaries_magasinage,
  fraisPeage: r.frais_peage,
  autresFrais: r.autres_frais,
  avanceCamion: r.avance_camion,
  plaqueVehicule: r.plaque_vehicule,
});

async function loadDossiers(db, dossierId = null) {
  const filter = dossierId ? 'WHERE dossier_id = $1' : '';
  const params = dossierId ? [dossierId] : [];
  const [dossiers, conteneurs, factures, lignes, operations, depenses] =
    await Promise.all([
      db.query(
        `SELECT * FROM dossiers ${dossierId ? 'WHERE id = $1' : ''} ORDER BY cree_le, id`,
        params,
      ),
      db.query(`SELECT * FROM dossier_conteneurs ${filter} ORDER BY position`, params),
      db.query(`SELECT * FROM factures ${filter}`, params),
      db.query(
        `SELECT l.*, f.dossier_id FROM facture_lignes l
         JOIN factures f ON f.id = l.facture_id ${filter} ORDER BY l.position`,
        params,
      ),
      db.query(`SELECT * FROM dossier_operations ${filter} ORDER BY position`, params),
      db.query(`SELECT * FROM dossier_depenses ${filter} ORDER BY position`, params),
    ]);
  const conteneursBy = groupBy(conteneurs.rows, 'dossier_id');
  const facturesBy = groupBy(factures.rows, 'dossier_id');
  const lignesBy = groupBy(lignes.rows, 'facture_id');
  const operationsBy = groupBy(operations.rows, 'dossier_id');
  const depensesBy = groupBy(depenses.rows, 'dossier_id');

  return dossiers.rows.map((d) => {
    const invoices = {};
    for (const f of facturesBy.get(d.id) ?? []) {
      invoices[f.type] = {
        id: f.id,
        reference: f.reference,
        description: f.description,
        montant: f.montant,
        statut: f.statut,
        dateEmission: sqlDateToFr(f.date_emission),
        lignes: (lignesBy.get(f.id) ?? []).map(ligneJson),
      };
    }
    return {
      id: d.id,
      numDossier: d.num_dossier,
      numBL: d.num_bl,
      numLB: d.num_lb,
      clientId: d.client_id,
      nbConteneurs: d.nb_conteneurs,
      transitaire: d.transitaire,
      dateCreation: sqlDateToFr(d.date_creation),
      typeFacturation: d.type_facturation,
      priorite: d.priorite,
      typeMarchandise: d.type_marchandise,
      lieuMarchandise: d.lieu_marchandise,
      lieuLivraison: d.lieu_livraison,
      dateArriveeBateau: sqlDateToFr(d.date_arrivee_bateau),
      description: d.description,
      prestataireId: d.prestataire_id,
      transitaireAffecteId: d.transitaire_affecte_id,
      transporteurAffecteId: d.transporteur_affecte_id,
      dateDebut: sqlDateToFr(d.date_debut),
      dateFin: sqlDateToFr(d.date_fin, '-'),
      statut: d.statut,
      version: d.version,
      conteneurs: (conteneursBy.get(d.id) ?? []).map((c) => ({
        numero: c.numero,
        type: c.type,
        marchandise: c.marchandise,
      })),
      factures: invoices,
      operations: (operationsBy.get(d.id) ?? []).map((o) => ({
        type: o.type,
        titre: o.titre,
        categorie: o.categorie,
        montant: o.montant,
        date: sqlDateTimeToFr(o.date),
        codeJournal: o.code_journal ?? '',
      })),
      depenses: (depensesBy.get(d.id) ?? []).map((e) => ({
        titre: e.titre,
        categorie: e.categorie,
        montant: e.montant,
        date: sqlDateTimeToFr(e.date),
      })),
    };
  });
}

// --- Validation du corps de requête ---

function parseInvoice(raw, kind) {
  if (raw === null || typeof raw !== 'object') {
    throw badRequest(`Facture « ${kind} » manquante.`);
  }
  return {
    id: text(raw, 'id', { required: true, max: 120 }),
    reference: text(raw, 'reference', { required: true, max: 120 }),
    description: text(raw, 'description', { max: 5000 }),
    montant: amount(raw, 'montant'),
    statut: oneOf(raw, 'statut', INVOICE_STATUSES),
    dateEmission: frDateToSql(raw.dateEmission, 'dateEmission'),
    lignes: list(raw, 'lignes').map((l) => ({
      description: text(l, 'description', { max: 1000 }),
      quantite: amount(l, 'quantite'),
      prixUnitaire: amount(l, 'prixUnitaire'),
      numeroConteneur: text(l, 'numeroConteneur'),
      bl: text(l, 'bl'),
      marchandise: text(l, 'marchandise'),
      typeConteneur: text(l, 'typeConteneur'),
      fraisTransit: amount(l, 'fraisTransit'),
      volumePoids: amount(l, 'volumePoids'),
      surestariesMagasinage: amount(l, 'surestariesMagasinage'),
      fraisPeage: amount(l, 'fraisPeage'),
      autresFrais: amount(l, 'autresFrais'),
      avanceCamion: amount(l, 'avanceCamion'),
      plaqueVehicule: text(l, 'plaqueVehicule'),
    })),
  };
}

function parseDossier(b) {
  const factures = b.factures ?? {};
  return {
    numDossier: text(b, 'numDossier', { required: true, max: 60 }),
    numBL: text(b, 'numBL'),
    numLB: text(b, 'numLB'),
    clientId: text(b, 'clientId', { required: true }),
    nbConteneurs: integer(b, 'nbConteneurs'),
    transitaire: text(b, 'transitaire'),
    dateCreation: frDateToSql(b.dateCreation, 'dateCreation'),
    typeFacturation: text(b, 'typeFacturation'),
    priorite: text(b, 'priorite'),
    typeMarchandise: text(b, 'typeMarchandise'),
    lieuMarchandise: text(b, 'lieuMarchandise'),
    lieuLivraison: text(b, 'lieuLivraison'),
    dateArriveeBateau: frDateToSql(b.dateArriveeBateau, 'dateArriveeBateau'),
    description: text(b, 'description', { max: 5000 }),
    prestataireId: optionalRef(b, 'prestataireId'),
    transitaireAffecteId: optionalRef(b, 'transitaireAffecteId'),
    transporteurAffecteId: optionalRef(b, 'transporteurAffecteId'),
    dateDebut: frDateToSql(b.dateDebut, 'dateDebut'),
    dateFin: frDateToSql(b.dateFin, 'dateFin'),
    statut: oneOf(b, 'statut', DOSSIER_STATUSES),
    version: b.version === undefined || b.version === null ? 0 : integer(b, 'version'),
    conteneurs: list(b, 'conteneurs').map((c) => ({
      numero: text(c, 'numero'),
      type: text(c, 'type'),
      marchandise: text(c, 'marchandise'),
    })),
    factures: Object.fromEntries(
      INVOICE_KINDS.map((kind) => [kind, parseInvoice(factures[kind], kind)]),
    ),
    operations: list(b, 'operations', { max: 5000 }).map((o) => ({
      type: oneOf(o, 'type', OPERATION_TYPES),
      titre: text(o, 'titre', { required: true }),
      categorie: text(o, 'categorie'),
      montant: amount(o, 'montant', { min: 0 }),
      date: frDateTimeToSql(o.date, 'date'),
      codeJournal: optionalRef(o, 'codeJournal'),
    })),
    depenses: list(b, 'depenses', { max: 5000 }).map((e) => ({
      titre: text(e, 'titre', { required: true }),
      categorie: text(e, 'categorie'),
      montant: amount(e, 'montant', { min: 0 }),
      date: frDateTimeToSql(e.date, 'date'),
    })),
  };
}

// Les mouvements déjà enregistrés ne peuvent être ni supprimés ni modifiés : seulement complétés.
function assertAppendOnly(existing, incoming, label, same) {
  if (incoming.length < existing.length) {
    throw conflict(`Des ${label} déjà enregistrés ne peuvent pas être supprimés.`);
  }
  existing.forEach((row, index) => {
    if (!same(row, incoming[index])) {
      throw conflict(`Des ${label} déjà enregistrés ne peuvent pas être modifiés.`);
    }
  });
}

const sameMovement = (row, next) =>
  row.titre === next.titre &&
  row.montant === next.montant &&
  row.date === next.date &&
  (row.type === undefined || row.type === next.type);

// --- Écriture ---

async function saveDossier(client, dossierId, d) {
  const current = await client.query(
    'SELECT statut, version FROM dossiers WHERE id = $1 FOR UPDATE',
    [dossierId],
  );
  const exists = current.rows.length > 0;
  if (exists) {
    if (current.rows[0].version !== d.version) {
      throw conflict(
        'Ce dossier a été modifié par un autre utilisateur. Rechargez la page pour récupérer la dernière version.',
      );
    }
    if (current.rows[0].statut === CLOSED_DOSSIER) {
      throw conflict('Ce dossier est clôturé : il ne peut plus être modifié.');
    }
    const [operations, depenses] = await Promise.all([
      client.query(
        `SELECT type, titre, montant, to_char(date, 'YYYY-MM-DD HH24:MI:SS') AS date
         FROM dossier_operations WHERE dossier_id = $1 ORDER BY position`,
        [dossierId],
      ),
      client.query(
        `SELECT titre, montant, to_char(date, 'YYYY-MM-DD HH24:MI:SS') AS date
         FROM dossier_depenses WHERE dossier_id = $1 ORDER BY position`,
        [dossierId],
      ),
    ]);
    assertAppendOnly(operations.rows, d.operations, 'mouvements', sameMovement);
    assertAppendOnly(depenses.rows, d.depenses, 'frais', sameMovement);
  }

  const fields = [
    d.numDossier, d.numBL, d.numLB, d.clientId, d.nbConteneurs, d.transitaire,
    d.dateCreation, d.typeFacturation, d.priorite, d.typeMarchandise,
    d.lieuMarchandise, d.lieuLivraison, d.dateArriveeBateau, d.description,
    d.prestataireId, d.transitaireAffecteId, d.transporteurAffecteId,
    d.dateDebut, d.dateFin, d.statut,
  ];
  let version;
  if (exists) {
    const { rows } = await client.query(
      `UPDATE dossiers SET num_dossier = $2, num_bl = $3, num_lb = $4, client_id = $5,
         nb_conteneurs = $6, transitaire = $7, date_creation = $8,
         type_facturation = $9, priorite = $10, type_marchandise = $11,
         lieu_marchandise = $12, lieu_livraison = $13, date_arrivee_bateau = $14,
         description = $15, prestataire_id = $16, transitaire_affecte_id = $17,
         transporteur_affecte_id = $18, date_debut = $19, date_fin = $20,
         statut = $21, version = version + 1, modifie_le = now()
       WHERE id = $1 RETURNING version`,
      [dossierId, ...fields],
    );
    version = rows[0].version;
  } else {
    const { rows } = await client.query(
      `INSERT INTO dossiers (id, num_dossier, num_bl, num_lb, client_id, nb_conteneurs,
         transitaire, date_creation, type_facturation, priorite, type_marchandise,
         lieu_marchandise, lieu_livraison, date_arrivee_bateau, description,
         prestataire_id, transitaire_affecte_id, transporteur_affecte_id,
         date_debut, date_fin, statut)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
         $16, $17, $18, $19, $20, $21)
       RETURNING version`,
      [dossierId, ...fields],
    );
    version = rows[0].version;
  }

  await client.query('DELETE FROM dossier_conteneurs WHERE dossier_id = $1', [dossierId]);
  for (const [position, c] of d.conteneurs.entries()) {
    await client.query(
      `INSERT INTO dossier_conteneurs (dossier_id, position, numero, type, marchandise)
       VALUES ($1, $2, $3, $4, $5)`,
      [dossierId, position, c.numero, c.type, c.marchandise],
    );
  }

  for (const kind of INVOICE_KINDS) {
    await saveInvoice(client, dossierId, kind, d.factures[kind]);
  }

  // Seuls les nouveaux mouvements sont insérés (les précédents sont vérifiés plus haut).
  const insertMovements = async (table, rows, columns) => {
    const { rows: count } = await client.query(
      `SELECT count(*)::int AS n FROM ${table} WHERE dossier_id = $1`,
      [dossierId],
    );
    for (let position = count[0].n; position < rows.length; position++) {
      const values = columns.map((column) => rows[position][column]);
      await client.query(
        `INSERT INTO ${table} (dossier_id, position, ${columns
          .map((column) => column.replace(/[A-Z]/g, (l) => `_${l.toLowerCase()}`))
          .join(', ')})
         VALUES ($1, $2, ${columns.map((_, i) => `$${i + 3}`).join(', ')})`,
        [dossierId, position, ...values],
      );
    }
  };
  await insertMovements('dossier_operations', d.operations, [
    'type', 'titre', 'categorie', 'montant', 'date', 'codeJournal',
  ]);
  await insertMovements('dossier_depenses', d.depenses, [
    'titre', 'categorie', 'montant', 'date',
  ]);

  return version;
}

async function saveInvoice(client, dossierId, kind, f) {
  const { rows } = await client.query(
    `SELECT id, statut, montant FROM factures WHERE dossier_id = $1 AND type = $2 FOR UPDATE`,
    [dossierId, kind],
  );
  const existing = rows[0];
  if (existing?.statut === CLOSED_INVOICE) {
    if (f.statut !== CLOSED_INVOICE || f.montant !== existing.montant) {
      throw conflict('Une facture clôturée ne peut plus être modifiée.');
    }
    return;
  }
  if (existing && existing.id !== f.id) {
    throw badRequest('Identifiant de facture incohérent.');
  }
  await client.query(
    `INSERT INTO factures (id, dossier_id, type, reference, description, montant, statut, date_emission)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO UPDATE SET
       reference = EXCLUDED.reference, description = EXCLUDED.description,
       montant = EXCLUDED.montant, statut = EXCLUDED.statut,
       date_emission = EXCLUDED.date_emission`,
    [f.id, dossierId, kind, f.reference, f.description, f.montant, f.statut, f.dateEmission],
  );
  await client.query('DELETE FROM facture_lignes WHERE facture_id = $1', [f.id]);
  for (const [position, l] of f.lignes.entries()) {
    await client.query(
      `INSERT INTO facture_lignes (facture_id, position, description, quantite,
         prix_unitaire, numero_conteneur, bl, marchandise, type_conteneur,
         frais_transit, volume_poids, surestaries_magasinage, frais_peage,
         autres_frais, avance_camion, plaque_vehicule)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
      [
        f.id, position, l.description, l.quantite, l.prixUnitaire,
        l.numeroConteneur, l.bl, l.marchandise, l.typeConteneur, l.fraisTransit,
        l.volumePoids, l.surestariesMagasinage, l.fraisPeage, l.autresFrais,
        l.avanceCamion, l.plaqueVehicule,
      ],
    );
  }
}

function dossiersRouter(pool) {
  const router = express.Router();

  router.put(
    '/dossiers/:id',
    requireModule('Transport', 'Prestation', 'Recouvrement', 'Comptabilité'),
    async (req, res, next) => {
      try {
        const dossierId = text(req.params, 'id', { required: true, max: 100 });
        const dossier = parseDossier(req.body);
        const version = await withTransaction(pool, (client) =>
          saveDossier(client, dossierId, dossier),
        );
        res.json({ id: dossierId, version });
      } catch (error) {
        next(error);
      }
    },
  );

  return router;
}

module.exports = { dossiersRouter, loadDossiers };
