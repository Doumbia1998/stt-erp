const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict, forbidden, notFound } = require('../errors');
const { requireModule } = require('../auth');
const { text, optionalRef, amount, oneOf, list, sqlDateToFr, sqlDateTimeToFr } = require('../format');
const { isAdmin } = require('../auth');
const { isDirection } = require('./facturesAgent');

const PRINCIPALE = 'Principale';
const DEPENSES = 'Dépenses';
const CAISSES = [PRINCIPALE, DEPENSES];
const CAISSIER_PRINCIPAL = 'Caissier Principal';
const CAISSIER_DEPENSES = 'Caissier Dépenses';
const STATUTS = ['Payé', 'Commencement'];
const VIREMENTS = ['Approvisionnement', 'Reversement'];
const round = (value) => Math.round(Number(value) * 100) / 100;
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;
// Les mouvements de caisse sont datés du jour (heure du Mali = UTC).
const today = () => new Date().toISOString().slice(0, 10);
const nowSql = () => new Date().toISOString().slice(0, 19).replace('T', ' ');
const recu = (numero) => `RC-${String(numero).padStart(5, '0')}`;

// La caissière des dépenses ne fait pas d'encaissement, et inversement.
const peutPrincipale = (user) => user.role !== CAISSIER_DEPENSES;
const peutDepenses = (user) => user.role !== CAISSIER_PRINCIPAL;
const exiger = (allowed, caisse) => {
  if (!allowed) throw forbidden(`Opération réservée à la caisse ${caisse.toLowerCase()}.`);
};

function mouvementJson(m) {
  return {
    id: m.id,
    type: m.type,
    date: sqlDateToFr(m.date),
    montant: m.montant,
    recuNumero: m.recu_numero === null ? 0 : Number(m.recu_numero),
    dossierId: m.dossier_id ?? '',
    operationUid: m.operation_uid ?? '',
    statutReglement: m.statut_reglement,
    modePaiement: m.mode_paiement,
    bonId: m.bon_id ?? '',
    receptionneLe: sqlDateToFr(m.receptionne_le),
    receptionnePar: m.receptionne_par,
    imputeLe: sqlDateToFr(m.impute_le),
    imputePar: m.impute_par,
    observations: m.observations,
    auteur: m.auteur,
    dateSaisie: m.saisie,
  };
}

async function loadCaisse(db) {
  const [params, mouvements, clotures] = await Promise.all([
    db.query('SELECT code, journal_code FROM caisses'),
    db.query(
      `SELECT *, ${saisieSql('cree_le')} AS saisie FROM caisse_mouvements ORDER BY cree_le, id`,
    ),
    db.query('SELECT * FROM caisse_clotures ORDER BY date, caisse'),
  ]);
  const journal = (code) => params.rows.find((p) => p.code === code)?.journal_code ?? '';
  return {
    parametres: { principale: journal(PRINCIPALE), depenses: journal(DEPENSES) },
    mouvements: mouvements.rows.map(mouvementJson),
    clotures: clotures.rows.map((c) => ({
      caisse: c.caisse,
      date: sqlDateToFr(c.date),
      recettes: c.recettes,
      depenses: c.depenses,
      solde: c.solde,
      auteur: c.auteur,
    })),
  };
}

// Recettes et dépenses d'une caisse : un virement sort de la caisse d'origine à
// sa date et n'entre dans l'autre caisse qu'à sa réception.
function evenements(caisse, mouvements) {
  const events = [];
  for (const m of mouvements) {
    const montant = Number(m.montant);
    const recu = m.receptionne_le;
    if (caisse === PRINCIPALE) {
      if (m.type === 'Encaissement') events.push({ date: m.date, recette: montant, depense: 0 });
      if (m.type === 'Approvisionnement') events.push({ date: m.date, recette: 0, depense: montant });
      if (m.type === 'Reversement' && recu) events.push({ date: recu, recette: montant, depense: 0 });
    } else {
      if (m.type === 'Paiement bon') events.push({ date: m.date, recette: 0, depense: montant });
      if (m.type === 'Reversement') events.push({ date: m.date, recette: 0, depense: montant });
      if (m.type === 'Approvisionnement' && recu) events.push({ date: recu, recette: montant, depense: 0 });
    }
  }
  return events;
}

async function soldeCaisse(client, caisse) {
  const { rows } = await client.query('SELECT type, date, montant, receptionne_le FROM caisse_mouvements');
  return round(evenements(caisse, rows).reduce((s, e) => s + e.recette - e.depense, 0));
}

async function journalDe(client, caisse) {
  const { rows } = await client.query('SELECT journal_code FROM caisses WHERE code = $1', [caisse]);
  const code = rows[0]?.journal_code;
  if (!code) {
    throw conflict(
      `Aucun journal n'est choisi pour la caisse ${caisse.toLowerCase()} : la Direction doit le définir dans « Paramètres des caisses ».`,
    );
  }
  return code;
}

async function verifierOuverte(client, caisse, date) {
  const { rows } = await client.query(
    'SELECT date FROM caisse_clotures WHERE caisse = $1 AND date >= $2 LIMIT 1',
    [caisse, date],
  );
  if (rows.length > 0) {
    throw conflict(
      `La caisse ${caisse.toLowerCase()} est clôturée au ${sqlDateToFr(rows[0].date)} : aucun mouvement ne peut plus y être fait à cette date.`,
    );
  }
}

// Verrou unique : les mouvements de caisse sont enregistrés l'un après l'autre.
const verrouiller = (client) => client.query('SELECT pg_advisory_xact_lock(4242)');

async function inserer(client, m, user) {
  const { rows: [saved] } = await client.query(
    `INSERT INTO caisse_mouvements (id, type, date, montant, recu_numero, dossier_id,
       operation_uid, statut_reglement, mode_paiement, bon_id, observations, auteur)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     RETURNING *, ${saisieSql('cree_le')} AS saisie`,
    [m.id, m.type, m.date, m.montant, m.recuNumero ?? null, m.dossierId ?? null,
      m.operationUid ?? null, m.statut ?? '', m.modePaiement ?? '', m.bonId ?? null,
      m.observations ?? '', user.nom],
  );
  return mouvementJson(saved);
}

// Encaissement d'une facture client : la caissière pointe le règlement (payé ou
// commencement) ; la comptabilité l'impute lors de la mise à jour comptable.
async function encaisser(client, body, user) {
  exiger(peutPrincipale(user), PRINCIPALE);
  const id = text(body, 'id', { required: true, max: 120 });
  const dossierId = text(body, 'dossierId', { required: true, max: 120 });
  const statut = oneOf(body, 'statut', STATUTS);
  const modePaiement = text(body, 'modePaiement', { max: 120 });
  const observations = text(body, 'observations', { max: 2000 });
  await verrouiller(client);
  const journal = await journalDe(client, PRINCIPALE);
  const date = today();
  await verifierOuverte(client, PRINCIPALE, date);

  const { rows: [dossier] } = await client.query(
    'SELECT id, statut FROM dossiers WHERE id = $1 FOR UPDATE',
    [dossierId],
  );
  if (!dossier) throw notFound('Dossier introuvable.');
  const { rows: [facture] } = await client.query(
    `SELECT reference, montant FROM factures
     WHERE dossier_id = $1 AND type = 'client' AND statut = 'Clôturée'`,
    [dossierId],
  );
  if (!facture) throw conflict("La facture client de ce dossier n'est pas encore validée.");
  const { rows: [totaux] } = await client.query(
    `SELECT
       COALESCE(sum(montant) FILTER (WHERE type = 'clientInvoice'), 0) AS factures,
       COALESCE(sum(montant) FILTER (WHERE type = 'clientPayment'), 0) AS reglements
     FROM dossier_operations WHERE dossier_id = $1`,
    [dossierId],
  );
  const reste = round(Number(facture.montant) + Number(totaux.factures) - Number(totaux.reglements));
  if (reste <= 0) throw conflict(`La facture ${facture.reference} est déjà soldée.`);
  let montant;
  if (statut === 'Payé') {
    montant = reste;
  } else {
    montant = amount(body, 'montant', { min: 0.01 });
    if (montant >= reste) {
      throw badRequest(
        `Le commencement doit être inférieur au reste à payer (${reste}). Choisissez « Payé » pour solder la facture.`,
      );
    }
  }

  const { rows: [{ numero }] } = await client.query("SELECT nextval('recus_caisse_seq') AS numero");
  const reference = recu(numero);
  const { rows: [{ last }] } = await client.query(
    'SELECT COALESCE(max(position), -1)::int AS last FROM dossier_operations WHERE dossier_id = $1',
    [dossierId],
  );
  const operation = {
    id,
    type: 'clientPayment',
    titre: `Reçu de caisse ${reference}`,
    categorie: 'Règlement Client',
    montant,
    date: nowSql(),
    codeJournal: journal,
    modePaiement,
    numeroCheque: '',
    observations: [`${statut} • facture ${facture.reference}`, observations].filter(Boolean).join(' • '),
  };
  await client.query(
    `INSERT INTO dossier_operations (dossier_id, position, uid, type, titre, categorie,
       montant, date, code_journal, mode_paiement, numero_cheque, observations, auteur)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
    [dossierId, last + 1, operation.id, operation.type, operation.titre, operation.categorie,
      montant, operation.date, journal, modePaiement, '', operation.observations, user.nom],
  );
  const { rows: [{ version }] } = await client.query(
    'UPDATE dossiers SET version = version + 1, modifie_le = now() WHERE id = $1 RETURNING version',
    [dossierId],
  );
  const mouvement = await inserer(
    client,
    { id, type: 'Encaissement', date, montant, recuNumero: numero, dossierId, operationUid: id,
      statut, modePaiement, observations },
    user,
  );
  return {
    mouvement,
    version,
    operation: {
      ...operation,
      date: `${sqlDateToFr(operation.date)} ${operation.date.slice(11, 16)}`,
      auteur: user.nom,
    },
  };
}

// Paiement d'un bon de caisse (frais des camions ou dépense administrative) par
// la caisse des dépenses, retrouvé par son numéro.
async function payerBon(client, bonId, body, user) {
  exiger(peutDepenses(user), DEPENSES);
  const id = text(body, 'id', { required: true, max: 120 });
  await verrouiller(client);
  const journal = await journalDe(client, DEPENSES);
  const date = today();
  await verifierOuverte(client, DEPENSES, date);
  const { rows: [bon] } = await client.query(
    'SELECT id, numero, montant FROM bons_caisse WHERE id = $1 FOR UPDATE',
    [bonId],
  );
  if (!bon) throw notFound('Bon de caisse introuvable.');
  const piece = `BC-${String(bon.numero).padStart(5, '0')}`;
  const { rows: paid } = await client.query('SELECT 1 FROM caisse_mouvements WHERE bon_id = $1', [bonId]);
  if (paid.length > 0) throw conflict(`Le bon ${piece} est déjà payé.`);
  const solde = await soldeCaisse(client, DEPENSES);
  if (Number(bon.montant) > solde) {
    throw conflict(
      `Solde insuffisant dans la caisse des dépenses (${solde}) pour payer le bon ${piece} (${Number(bon.montant)}). Demandez un approvisionnement à la caisse principale.`,
    );
  }
  const { rows: [{ version }] } = await client.query(
    `UPDATE bons_caisse SET code_journal = $2, version = version + 1, modifie_le = now()
     WHERE id = $1 RETURNING version`,
    [bonId, journal],
  );
  const mouvement = await inserer(
    client,
    { id, type: 'Paiement bon', date, montant: Number(bon.montant), bonId,
      observations: text(body, 'observations', { max: 2000 }) },
    user,
  );
  return { mouvement, version, codeJournal: journal };
}

// Approvisionnement de la caisse des dépenses par la caisse principale, ou
// reversement du reliquat de la caisse des dépenses vers la caisse principale.
async function virement(client, body, user) {
  const id = text(body, 'id', { required: true, max: 120 });
  const type = oneOf(body, 'type', VIREMENTS);
  const montant = amount(body, 'montant', { min: 0.01 });
  const source = type === 'Approvisionnement' ? PRINCIPALE : DEPENSES;
  exiger(source === PRINCIPALE ? peutPrincipale(user) : peutDepenses(user), source);
  await verrouiller(client);
  await journalDe(client, PRINCIPALE);
  await journalDe(client, DEPENSES);
  const date = today();
  await verifierOuverte(client, source, date);
  const solde = await soldeCaisse(client, source);
  if (montant > solde) {
    throw conflict(`Solde insuffisant dans la caisse ${source.toLowerCase()} (${solde}).`);
  }
  const mouvement = await inserer(
    client,
    { id, type, date, montant, observations: text(body, 'observations', { max: 2000 }) },
    user,
  );
  return { mouvement };
}

async function receptionner(client, id, user) {
  await verrouiller(client);
  const { rows: [m] } = await client.query('SELECT * FROM caisse_mouvements WHERE id = $1 FOR UPDATE', [id]);
  if (!m || !VIREMENTS.includes(m.type)) throw notFound('Virement introuvable.');
  if (m.receptionne_le) throw conflict('Ce virement est déjà réceptionné.');
  const destination = m.type === 'Approvisionnement' ? DEPENSES : PRINCIPALE;
  exiger(destination === PRINCIPALE ? peutPrincipale(user) : peutDepenses(user), destination);
  const date = today();
  await verifierOuverte(client, destination, date);
  const { rows: [saved] } = await client.query(
    `UPDATE caisse_mouvements SET receptionne_le = $2, receptionne_par = $3
     WHERE id = $1 RETURNING *, ${saisieSql('cree_le')} AS saisie`,
    [id, date, user.nom],
  );
  return { mouvement: mouvementJson(saved) };
}

// Annulation d'un mouvement tant que sa caisse n'est pas clôturée.
async function annuler(client, id, user) {
  await verrouiller(client);
  const { rows: [m] } = await client.query('SELECT * FROM caisse_mouvements WHERE id = $1 FOR UPDATE', [id]);
  if (!m) throw notFound('Mouvement de caisse introuvable.');
  if (m.auteur !== user.nom && !isDirection(user)) {
    throw forbidden("Seul l'auteur du mouvement ou la Direction peut l'annuler.");
  }
  if (m.type === 'Encaissement') {
    if (m.impute_le) {
      throw conflict("Cet encaissement est déjà imputé par la comptabilité : il ne peut plus être annulé.");
    }
    await verifierOuverte(client, PRINCIPALE, m.date);
  } else if (m.type === 'Paiement bon') {
    await verifierOuverte(client, DEPENSES, m.date);
  } else {
    if (m.receptionne_le) {
      throw conflict('Ce virement est déjà réceptionné : il ne peut plus être annulé.');
    }
    await verifierOuverte(client, m.type === 'Approvisionnement' ? PRINCIPALE : DEPENSES, m.date);
  }
  await client.query('DELETE FROM caisse_mouvements WHERE id = $1', [id]);
  let version = null;
  if (m.type === 'Encaissement' && m.dossier_id) {
    await client.query('DELETE FROM dossier_operations WHERE dossier_id = $1 AND uid = $2', [
      m.dossier_id,
      m.operation_uid,
    ]);
    ({ rows: [{ version }] } = await client.query(
      'UPDATE dossiers SET version = version + 1, modifie_le = now() WHERE id = $1 RETURNING version',
      [m.dossier_id],
    ));
  }
  return { version };
}

// Clôture du jour : recettes, dépenses et solde de la caisse figés.
async function cloturer(client, body, user) {
  const caisse = oneOf(body, 'caisse', CAISSES);
  exiger(caisse === PRINCIPALE ? peutPrincipale(user) : peutDepenses(user), caisse);
  await verrouiller(client);
  const date = today();
  const { rows: existing } = await client.query(
    'SELECT 1 FROM caisse_clotures WHERE caisse = $1 AND date = $2',
    [caisse, date],
  );
  if (existing.length > 0) throw conflict(`La caisse ${caisse.toLowerCase()} est déjà clôturée aujourd'hui.`);
  const { rows } = await client.query('SELECT type, date, montant, receptionne_le FROM caisse_mouvements');
  const events = evenements(caisse, rows);
  const duJour = events.filter((e) => e.date === date);
  const recettes = round(duJour.reduce((s, e) => s + e.recette, 0));
  const depenses = round(duJour.reduce((s, e) => s + e.depense, 0));
  const solde = round(events.filter((e) => e.date <= date).reduce((s, e) => s + e.recette - e.depense, 0));
  await client.query(
    `INSERT INTO caisse_clotures (caisse, date, recettes, depenses, solde, auteur)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [caisse, date, recettes, depenses, solde, user.nom],
  );
  return { caisse, date: sqlDateToFr(date), recettes, depenses, solde, auteur: user.nom };
}

// Imputation par la comptabilité : le montant encaissé par la caisse est réparti
// sur les factures du client (la facture pointée par la caissière ou d'autres).
async function imputer(client, id, body, user) {
  const codeJournal = optionalRef(body, 'codeJournal');
  const imputations = list(body, 'imputations', { max: 200 })
    .map((i) => ({
      dossierId: text(i, 'dossierId', { required: true, max: 120 }),
      montant: amount(i, 'montant', { min: 0 }),
    }))
    .filter((i) => i.montant > 0);
  if (imputations.length === 0) throw badRequest('Indiquez au moins une facture à régler.');
  await verrouiller(client);
  const { rows: [m] } = await client.query('SELECT * FROM caisse_mouvements WHERE id = $1 FOR UPDATE', [id]);
  if (!m || m.type !== 'Encaissement') throw notFound('Encaissement introuvable.');
  if (m.impute_le) throw conflict('Cet encaissement est déjà imputé.');
  const total = round(imputations.reduce((s, i) => s + i.montant, 0));
  if (total !== round(m.montant)) {
    throw badRequest(`Le total imputé (${total}) doit être égal au montant encaissé (${round(m.montant)}).`);
  }
  const journal = codeJournal ?? (await journalDe(client, PRINCIPALE));
  const { rows: [origine] } = await client.query(
    `SELECT d.client_id, o.titre, o.mode_paiement, to_char(o.date, 'YYYY-MM-DD HH24:MI:SS') AS date
     FROM dossiers d LEFT JOIN dossier_operations o ON o.dossier_id = d.id AND o.uid = $2
     WHERE d.id = $1`,
    [m.dossier_id, m.operation_uid],
  );
  if (!origine) throw notFound('Dossier de l’encaissement introuvable.');
  await client.query('DELETE FROM dossier_operations WHERE dossier_id = $1 AND uid = $2', [
    m.dossier_id,
    m.operation_uid,
  ]);
  const versions = new Map();
  const operations = [];
  for (const [n, imp] of imputations.entries()) {
    const { rows: [dossier] } = await client.query(
      'SELECT id, client_id FROM dossiers WHERE id = $1 FOR UPDATE',
      [imp.dossierId],
    );
    if (!dossier) throw notFound('Dossier introuvable.');
    if (dossier.client_id !== origine.client_id) {
      throw badRequest('Les factures imputées doivent appartenir au client de l’encaissement.');
    }
    const { rows: [solde] } = await client.query(
      `SELECT
         COALESCE((SELECT montant FROM factures WHERE dossier_id = $1 AND type = 'client' AND statut = 'Clôturée'), 0)
         + COALESCE(sum(montant) FILTER (WHERE type = 'clientInvoice'), 0)
         - COALESCE(sum(montant) FILTER (WHERE type = 'clientPayment'), 0) AS reste
       FROM dossier_operations WHERE dossier_id = $1`,
      [imp.dossierId],
    );
    if (imp.montant > round(solde.reste) + 0.001) {
      throw badRequest(`Le montant imputé dépasse le solde de la facture du dossier (${round(solde.reste)}).`);
    }
    const { rows: [{ last }] } = await client.query(
      'SELECT COALESCE(max(position), -1)::int AS last FROM dossier_operations WHERE dossier_id = $1',
      [imp.dossierId],
    );
    const op = {
      id: `${id}-i${n + 1}`,
      type: 'clientPayment',
      titre: origine.titre || `Reçu de caisse ${recu(m.recu_numero)}`,
      categorie: 'Règlement Client',
      montant: imp.montant,
      date: origine.date || nowSql(),
      codeJournal: journal,
      modePaiement: origine.mode_paiement || m.mode_paiement,
      numeroCheque: '',
      observations: `Imputé par ${user.nom}`,
    };
    await client.query(
      `INSERT INTO dossier_operations (dossier_id, position, uid, type, titre, categorie,
         montant, date, code_journal, mode_paiement, numero_cheque, observations, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
      [imp.dossierId, last + 1, op.id, op.type, op.titre, op.categorie, op.montant, op.date,
        journal, op.modePaiement, '', op.observations, m.auteur],
    );
    operations.push({ dossierId: imp.dossierId, operation: { ...op, date: sqlDateTimeToFr(op.date), auteur: m.auteur } });
    versions.set(imp.dossierId, true);
  }
  versions.set(m.dossier_id, true);
  const dossiers = [];
  for (const dossierId of versions.keys()) {
    const { rows: [{ version }] } = await client.query(
      'UPDATE dossiers SET version = version + 1, modifie_le = now() WHERE id = $1 RETURNING version',
      [dossierId],
    );
    dossiers.push({ id: dossierId, version });
  }
  const { rows: [saved] } = await client.query(
    `UPDATE caisse_mouvements SET impute_le = $2, impute_par = $3, imputations = $4
     WHERE id = $1 RETURNING *, ${saisieSql('cree_le')} AS saisie`,
    [id, today(), user.nom, JSON.stringify(imputations)],
  );
  return { mouvement: mouvementJson(saved), operations, dossiers };
}

// Réouverture d'une caisse clôturée par erreur : réservée à l'administrateur.
async function rouvrir(client, body, user) {
  if (!isAdmin(user)) throw forbidden("Seul l'administrateur peut déclôturer une caisse.");
  const caisse = oneOf(body, 'caisse', CAISSES);
  const { rows: [last] } = await client.query(
    'SELECT date FROM caisse_clotures WHERE caisse = $1 ORDER BY date DESC LIMIT 1',
    [caisse],
  );
  if (!last) throw notFound("Cette caisse n'a aucune clôture.");
  await client.query('DELETE FROM caisse_clotures WHERE caisse = $1 AND date = $2', [caisse, last.date]);
  return { caisse, date: sqlDateToFr(last.date) };
}

function caisseRouter(pool) {
  const router = express.Router();
  const allowed = requireModule('Caisse');
  const handle = (fn) => async (req, res, next) => {
    try {
      res.json(await withTransaction(pool, (client) => fn(req, client)));
    } catch (error) {
      next(error);
    }
  };

  router.put(
    '/caisse/parametres',
    allowed,
    handle(async (req, client) => {
      if (!isDirection(req.user)) throw forbidden('Réservé à la Direction.');
      const principale = optionalRef(req.body ?? {}, 'principale');
      const depenses = optionalRef(req.body ?? {}, 'depenses');
      if (principale && principale === depenses) {
        throw badRequest('La caisse principale et la caisse des dépenses doivent avoir deux journaux différents.');
      }
      for (const [code, journal] of [[PRINCIPALE, principale], [DEPENSES, depenses]]) {
        await client.query(
          'UPDATE caisses SET journal_code = $2, modifie_le = now() WHERE code = $1',
          [code, journal],
        );
      }
      return { principale: principale ?? '', depenses: depenses ?? '' };
    }),
  );
  router.post('/caisse/encaissements', allowed, handle((req, client) => encaisser(client, req.body ?? {}, req.user)));
  router.post(
    '/caisse/bons/:id/paiement',
    allowed,
    handle((req, client) =>
      payerBon(client, text(req.params, 'id', { required: true, max: 120 }), req.body ?? {}, req.user),
    ),
  );
  router.post('/caisse/virements', allowed, handle((req, client) => virement(client, req.body ?? {}, req.user)));
  router.post(
    '/caisse/virements/:id/reception',
    allowed,
    handle((req, client) => receptionner(client, text(req.params, 'id', { required: true, max: 120 }), req.user)),
  );
  router.delete(
    '/caisse/mouvements/:id',
    allowed,
    handle((req, client) => annuler(client, text(req.params, 'id', { required: true, max: 120 }), req.user)),
  );
  router.post(
    '/caisse/encaissements/:id/imputation',
    requireModule('Comptabilité', 'Recouvrement'),
    handle((req, client) =>
      imputer(client, text(req.params, 'id', { required: true, max: 120 }), req.body ?? {}, req.user),
    ),
  );
  router.post('/caisse/clotures/annulation', allowed, handle((req, client) => rouvrir(client, req.body ?? {}, req.user)));
  router.post('/caisse/clotures', allowed, handle((req, client) => cloturer(client, req.body ?? {}, req.user)));
  return router;
}

module.exports = { caisseRouter, loadCaisse, PRINCIPALE, DEPENSES };
