// Conversion JSON des modèles pour les échanges avec l'API (api.stt-ml.com).
import 'models.dart';

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;
String _str(Object? value) => value as String? ?? '';
String? _ref(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

ErpUser erpUserFromJson(Map<String, dynamic> json) => ErpUser(
  id: json['id'] as String,
  name: _str(json['nom']),
  login: _str(json['identifiant']),
  password: '',
  role: _str(json['role']),
  accessModules: {...(json['modules'] as List? ?? const []).cast<String>()},
  photo: json['photo'] as String?,
);

// Le mot de passe n'est envoyé que s'il a été saisi (sinon le serveur garde l'ancien).
Map<String, dynamic> erpUserToJson(ErpUser user) => {
  'nom': user.name,
  'identifiant': user.login,
  'role': user.role,
  'modules': user.accessModules.toList(),
  if (user.password.isNotEmpty) 'motDePasse': user.password,
  if (user.photoModifiee) 'photo': user.photo,
};

Client clientFromJson(Map<String, dynamic> json) => Client(
  id: json['id'] as String,
  nom: _str(json['nom']),
  telephone: _str(json['telephone']),
  societe: _str(json['societe']),
  adresse: _str(json['adresse']),
  email: _str(json['email']),
  rccm: _str(json['rccm']),
  soldeInitial: _num(json['soldeInitial']),
  assujettiTva: json['assujettiTva'] as bool? ?? false,
  compteComptable: _str(json['compteComptable']),
);

Map<String, dynamic> clientToJson(Client client) => {
  'nom': client.nom,
  'telephone': client.telephone,
  'societe': client.societe,
  'adresse': client.adresse,
  'email': client.email,
  'rccm': client.rccm,
  'soldeInitial': client.soldeInitial,
  'assujettiTva': client.assujettiTva,
  'compteComptable': client.compteComptable,
};

Prestataire prestataireFromJson(Map<String, dynamic> json) => Prestataire(
  id: json['id'] as String,
  entreprise: _str(json['entreprise']),
  type: _str(json['type']),
  pays: _str(json['pays']),
  villePort: _str(json['villePort']),
  contact: _str(json['contact']),
  telephone: _str(json['telephone']),
  email: _str(json['email']),
  services: _str(json['services']),
  adresse: _str(json['adresse']),
  rccm: _str(json['rccm']),
  nombreVehicules: (json['nombreVehicules'] as num?)?.toInt() ?? 0,
  soldeInitial: _num(json['soldeInitial']),
  compteComptable: _str(json['compteComptable']),
  vehicules: [
    for (final v in (json['vehicules'] as List? ?? const []))
      Vehicule(
        id: v['id'] as String,
        plaque: _str(v['plaque']),
        chauffeur: _str(v['chauffeur']),
        telephone: _str(v['telephone']),
      ),
  ],
);

Map<String, dynamic> prestataireToJson(Prestataire provider) => {
  'vehicules': [
    for (final v in provider.vehicules)
      {
        'id': v.id,
        'plaque': v.plaque,
        'chauffeur': v.chauffeur,
        'telephone': v.telephone,
      },
  ],
  'entreprise': provider.entreprise,
  'type': provider.type,
  'pays': provider.pays,
  'villePort': provider.villePort,
  'contact': provider.contact,
  'telephone': provider.telephone,
  'email': provider.email,
  'services': provider.services,
  'adresse': provider.adresse,
  'rccm': provider.rccm,
  'nombreVehicules': provider.nombreVehicules,
  'soldeInitial': provider.soldeInitial,
  'compteComptable': provider.compteComptable,
};

PlanAccount planAccountFromJson(Map<String, dynamic> json) => PlanAccount(
  id: json['id'] as String,
  code: _str(json['code']),
  libelle: _str(json['libelle']),
  nature: _str(json['nature']),
  tiersId: _ref(json['tiersId']),
  soldeInitial: _num(json['soldeInitial']),
  assujettiTva: json['assujettiTva'] as bool? ?? false,
);

Map<String, dynamic> planAccountToJson(PlanAccount account) => {
  'code': account.code,
  'libelle': account.libelle,
  'nature': account.nature,
  'tiersId': account.tiersId,
  'soldeInitial': account.soldeInitial,
  'assujettiTva': account.assujettiTva,
};

JournalCode journalFromJson(Map<String, dynamic> json) => JournalCode(
  code: _str(json['code']),
  intitule: _str(json['intitule']),
  type: _str(json['type']),
  compteTresorerie: _str(json['compteTresorerie']),
);

Map<String, dynamic> journalToJson(JournalCode journal) => {
  'code': journal.code,
  'intitule': journal.intitule,
  'type': journal.type,
  'compteTresorerie': journal.compteTresorerie,
};

Voyage voyageFromJson(Map<String, dynamic> json) => Voyage(
  id: json['id'] as String,
  dossierId: _str(json['dossierId']),
  plaque: _str(json['plaque']),
  chauffeur: _str(json['chauffeur']),
  origine: _str(json['origine']),
  destination: _str(json['destination']),
  depart: _str(json['depart']),
  arriveePrevue: _str(json['arriveePrevue']),
  statut: _str(json['statut']),
);

Map<String, dynamic> voyageToJson(Voyage voyage) => {
  'dossierId': voyage.dossierId,
  'plaque': voyage.plaque,
  'chauffeur': voyage.chauffeur,
  'origine': voyage.origine,
  'destination': voyage.destination,
  'depart': voyage.depart,
  'arriveePrevue': voyage.arriveePrevue,
  'statut': voyage.statut,
};

InvoiceLine _invoiceLineFromJson(Map<String, dynamic> json) => InvoiceLine(
  description: _str(json['description']),
  quantite: _num(json['quantite']),
  prixUnitaire: _num(json['prixUnitaire']),
  numeroConteneur: _str(json['numeroConteneur']),
  bl: _str(json['bl']),
  marchandise: _str(json['marchandise']),
  typeConteneur: _str(json['typeConteneur']),
  fraisTransit: _num(json['fraisTransit']),
  volumePoids: _num(json['volumePoids']),
  surestariesMagasinage: _num(json['surestariesMagasinage']),
  fraisPeage: _num(json['fraisPeage']),
  autresFrais: _num(json['autresFrais']),
  avanceCamion: _num(json['avanceCamion']),
  plaqueVehicule: _str(json['plaqueVehicule']),
  telephoneChauffeur: _str(json['telephoneChauffeur']),
);

Map<String, dynamic> _invoiceLineToJson(InvoiceLine line) => {
  'description': line.description,
  'quantite': line.quantite,
  'prixUnitaire': line.prixUnitaire,
  'numeroConteneur': line.numeroConteneur,
  'bl': line.bl,
  'marchandise': line.marchandise,
  'typeConteneur': line.typeConteneur,
  'fraisTransit': line.fraisTransit,
  'volumePoids': line.volumePoids,
  'surestariesMagasinage': line.surestariesMagasinage,
  'fraisPeage': line.fraisPeage,
  'autresFrais': line.autresFrais,
  'avanceCamion': line.avanceCamion,
  'plaqueVehicule': line.plaqueVehicule,
  'telephoneChauffeur': line.telephoneChauffeur,
};

DossierInvoice? _invoiceFromJson(Object? json, DossierInvoiceKind kind) {
  if (json is! Map<String, dynamic>) return null;
  return DossierInvoice(
    id: json['id'] as String,
    numero: (json['numero'] as num?)?.toInt() ?? 0,
    reference: _str(json['reference']),
    kind: kind,
    description: _str(json['description']),
    observations: _str(json['observations']),
    montant: _num(json['montant']),
    statut: _str(json['statut']),
    dateEmission: _str(json['dateEmission']),
    lignes: [
      for (final line in json['lignes'] as List? ?? const [])
        _invoiceLineFromJson(line as Map<String, dynamic>),
    ],
  );
}

Map<String, dynamic> _invoiceToJson(DossierInvoice invoice) => {
  'id': invoice.id,
  'reference': invoice.reference,
  'description': invoice.description,
  'observations': invoice.observations,
  'montant': invoice.montant,
  'statut': invoice.statut,
  'dateEmission': invoice.dateEmission,
  'lignes': invoice.lignes.map(_invoiceLineToJson).toList(),
};

TransitDossier dossierFromJson(
  Map<String, dynamic> json, {
  required Map<String, Client> clients,
  required Map<String, Prestataire> prestataires,
}) {
  final client = clients[json['clientId']];
  if (client == null) {
    throw FormatException('Client introuvable pour le dossier ${json['id']}');
  }
  final invoices = json['factures'] as Map<String, dynamic>? ?? const {};
  return TransitDossier(
      id: json['id'] as String,
      numDossier: _str(json['numDossier']),
      numBL: _str(json['numBL']),
      numLB: _str(json['numLB']),
      client: client,
      nbConteneurs: (json['nbConteneurs'] as num?)?.toInt() ?? 0,
      dateDebut: _str(json['dateDebut']),
      transitaire: _str(json['transitaire']),
      dateCreation: _str(json['dateCreation']),
      typeFacturation: _str(json['typeFacturation']),
      priorite: _str(json['priorite']),
      typeMarchandise: _str(json['typeMarchandise']),
      lieuMarchandise: _str(json['lieuMarchandise']),
      lieuLivraison: _str(json['lieuLivraison']),
      dateArriveeBateau: _str(json['dateArriveeBateau']),
      dateLivraisonSouhaitee: _str(json['dateLivraisonSouhaitee']),
      description: _str(json['description']),
      prestataire: prestataires[json['prestataireId']],
      factureClient: _invoiceFromJson(
        invoices[DossierInvoiceKind.client.name],
        DossierInvoiceKind.client,
      ),
      facturePrestataire: _invoiceFromJson(
        invoices[DossierInvoiceKind.provider.name],
        DossierInvoiceKind.provider,
      ),
      factureTransitaire: _invoiceFromJson(
        invoices[DossierInvoiceKind.forwarder.name],
        DossierInvoiceKind.forwarder,
      ),
      factureTransporteur: _invoiceFromJson(
        invoices[DossierInvoiceKind.carrier.name],
        DossierInvoiceKind.carrier,
      ),
      conteneurs: [
        for (final container in json['conteneurs'] as List? ?? const [])
          TransitContainer(
            numero: _str(container['numero']),
            type: _str(container['type']),
            marchandise: _str(container['marchandise']),
            observation: _str(container['observation']),
          ),
      ],
      dateFin: _str(json['dateFin']).isEmpty ? '-' : _str(json['dateFin']),
      statut: _str(json['statut']),
      depenses: [
        for (final expense in json['depenses'] as List? ?? const [])
          Depense(
            titre: _str(expense['titre']),
            montant: _num(expense['montant']),
            categorie: _str(expense['categorie']),
            date: _str(expense['date']),
            auteur: _str(expense['auteur']),
            saisiLe: _str(expense['saisiLe']),
          ),
      ],
      operations: [
        for (final operation in json['operations'] as List? ?? const [])
          dossierOperationFromJson(operation as Map<String, dynamic>),
      ],
      version: (json['version'] as num?)?.toInt() ?? 0,
      numero: (json['numero'] as num?)?.toInt() ?? 0,
      auteurSaisie: _str(json['auteurSaisie']),
      dateSaisie: _str(json['dateSaisie']),
    )
    ..transitaireAffecte = prestataires[json['transitaireAffecteId']]
    ..transporteurAffecte = prestataires[json['transporteurAffecteId']];
}

Map<String, dynamic> dossierToJson(TransitDossier dossier) => {
  'numDossier': dossier.numDossier,
  'numBL': dossier.numBL,
  'numLB': dossier.numLB,
  'clientId': dossier.client.id,
  'nbConteneurs': dossier.nbConteneurs,
  'transitaire': dossier.transitaire,
  'dateCreation': dossier.dateCreation,
  'typeFacturation': dossier.typeFacturation,
  'priorite': dossier.priorite,
  'typeMarchandise': dossier.typeMarchandise,
  'lieuMarchandise': dossier.lieuMarchandise,
  'lieuLivraison': dossier.lieuLivraison,
  'dateArriveeBateau': dossier.dateArriveeBateau,
  'dateLivraisonSouhaitee': dossier.dateLivraisonSouhaitee,
  'description': dossier.description,
  'prestataireId': dossier.prestataire?.id,
  'transitaireAffecteId': dossier.transitaireAffecte?.id,
  'transporteurAffecteId': dossier.transporteurAffecte?.id,
  'dateDebut': dossier.dateDebut,
  'dateFin': dossier.dateFin,
  'statut': dossier.statut,
  'version': dossier.version,
  'conteneurs': [
    for (final container in dossier.conteneurs)
      {
        'numero': container.numero,
        'type': container.type,
        'marchandise': container.marchandise,
        'observation': container.observation,
      },
  ],
  'factures': {
    DossierInvoiceKind.client.name: _invoiceToJson(dossier.factureClient),
    DossierInvoiceKind.provider.name: _invoiceToJson(
      dossier.facturePrestataire,
    ),
    DossierInvoiceKind.forwarder.name: _invoiceToJson(
      dossier.factureTransitaire,
    ),
    DossierInvoiceKind.carrier.name: _invoiceToJson(
      dossier.factureTransporteur,
    ),
  },
  'operations': [
    for (final operation in dossier.operations)
      {
        'type': operation.type.name,
        'titre': operation.titre,
        'categorie': operation.categorie,
        'montant': operation.montant,
        'date': operation.date,
        'id': operation.id,
        'codeJournal': operation.codeJournal,
        'modePaiement': operation.modePaiement,
        'numeroCheque': operation.numeroCheque,
        'observations': operation.observations,
      },
  ],
  'depenses': [
    for (final expense in dossier.depenses)
      {
        'titre': expense.titre,
        'categorie': expense.categorie,
        'montant': expense.montant,
        'date': expense.date,
      },
  ],
};

ModeReglement modeReglementFromJson(Map<String, dynamic> json) => ModeReglement(
  id: json['id'] as String,
  intitule: _str(json['intitule']),
  type: _str(json['type']),
  journalClient: _str(json['journalClient']),
  journalFournisseur: _str(json['journalFournisseur']),
  compteTresorerie: _str(json['compteTresorerie']),
);

Map<String, dynamic> modeReglementToJson(ModeReglement mode) => {
  'intitule': mode.intitule,
  'type': mode.type,
  'journalClient': mode.journalClient,
  'journalFournisseur': mode.journalFournisseur,
  'compteTresorerie': mode.compteTresorerie,
};

TypeFrais typeFraisFromJson(Map<String, dynamic> json) => TypeFrais(
  id: json['id'] as String,
  numero: (json['numero'] as num?)?.toInt() ?? 0,
  libelle: _str(json['libelle']),
  montant: _num(json['montant']),
  compteGeneral: _str(json['compteGeneral']),
  compte: _str(json['compte']),
);

Map<String, dynamic> typeFraisToJson(TypeFrais type) => {
  'libelle': type.libelle,
  'montant': type.montant,
  'compteGeneral': type.compteGeneral,
};

FactureTransitaire factureTransitaireFromJson(Map<String, dynamic> json) =>
    FactureTransitaire(
      id: json['id'] as String,
      numero: (json['numero'] as num?)?.toInt() ?? 0,
      reference: _str(json['reference']),
      transitaireId: _str(json['transitaireId']),
      dateEmission: _str(json['dateEmission']),
      observations: _str(json['observations']),
      version: (json['version'] as num?)?.toInt() ?? 0,
      auteur: _str(json['auteur']),
      dateSaisie: _str(json['dateSaisie']),
      lignes: [
        for (final l in (json['lignes'] as List? ?? const []))
          FactureTransitaireLigne(
            dossierId: _str(l['dossierId']),
            bl: _str(l['bl']),
            numeroConteneur: _str(l['numeroConteneur']),
            marchandise: _str(l['marchandise']),
            typeConteneur: _str(l['typeConteneur']),
            dateDepart: _str(l['dateDepart']),
            transporteurId: _str(l['transporteurId']),
            plaque: _str(l['plaque']),
            telephoneChauffeur: _str(l['telephoneChauffeur']),
            fraisTransit: _num(l['fraisTransit']),
            surestariesMagasinage: _num(l['surestariesMagasinage']),
            volumePoids: _num(l['volumePoids']),
            autresFrais: _num(l['autresFrais']),
            fraisPeage: _num(l['fraisPeage']),
            montantTransport: _num(l['montantTransport']),
            avanceCamion: _num(l['avanceCamion']),
          ),
      ],
      reglements: [
        for (final r in (json['reglements'] as List? ?? const []))
          ReglementFacture(
            id: r['id'] as String,
            date: _str(r['date']),
            montant: _num(r['montant']),
            codeJournal: _str(r['codeJournal']),
            modePaiement: _str(r['modePaiement']),
            numeroCheque: _str(r['numeroCheque']),
            observations: _str(r['observations']),
            auteur: _str(r['auteur']),
            saisiLe: _str(r['saisiLe']),
          ),
      ],
    );

Map<String, dynamic> factureTransitaireToJson(FactureTransitaire f) => {
  'reference': f.reference,
  'transitaireId': f.transitaireId,
  'dateEmission': f.dateEmission,
  'observations': f.observations,
  'version': f.version,
  'lignes': [
    for (final l in f.lignes)
      {
        'dossierId': l.dossierId,
        'bl': l.bl,
        'numeroConteneur': l.numeroConteneur,
        'marchandise': l.marchandise,
        'typeConteneur': l.typeConteneur,
        'dateDepart': l.dateDepart,
        'transporteurId': l.transporteurId,
        'plaque': l.plaque,
        'telephoneChauffeur': l.telephoneChauffeur,
        'fraisTransit': l.fraisTransit,
        'surestariesMagasinage': l.surestariesMagasinage,
        'volumePoids': l.volumePoids,
        'autresFrais': l.autresFrais,
        'fraisPeage': l.fraisPeage,
        'montantTransport': l.montantTransport,
        'avanceCamion': l.avanceCamion,
      },
  ],
  'reglements': [
    for (final r in f.reglements)
      {
        'id': r.id,
        'date': r.date,
        'montant': r.montant,
        'codeJournal': r.codeJournal,
        'modePaiement': r.modePaiement,
        'numeroCheque': r.numeroCheque,
        'observations': r.observations,
      },
  ],
};

FactureTransporteur factureTransporteurFromJson(Map<String, dynamic> json) =>
    FactureTransporteur(
      id: json['id'] as String,
      numero: (json['numero'] as num?)?.toInt() ?? 0,
      reference: _str(json['reference']),
      transporteurId: _str(json['transporteurId']),
      plaque: _str(json['plaque']),
      dateEmission: _str(json['dateEmission']),
      observations: _str(json['observations']),
      montant: _num(json['montant']),
      avance: _num(json['avance']),
      journalAvance: _str(json['journalAvance']),
      version: (json['version'] as num?)?.toInt() ?? 0,
      auteur: _str(json['auteur']),
      dateSaisie: _str(json['dateSaisie']),
      lignes: [
        for (final l in (json['lignes'] as List? ?? const []))
          FactureTransporteurLigne(
            dossierId: _str(l['dossierId']),
            bl: _str(l['bl']),
            numeroConteneur: _str(l['numeroConteneur']),
            montant: _num(l['montant']),
          ),
      ],
      reglements: [
        for (final r in (json['reglements'] as List? ?? const []))
          ReglementFacture(
            id: r['id'] as String,
            date: _str(r['date']),
            montant: _num(r['montant']),
            codeJournal: _str(r['codeJournal']),
            modePaiement: _str(r['modePaiement']),
            numeroCheque: _str(r['numeroCheque']),
            observations: _str(r['observations']),
            auteur: _str(r['auteur']),
            saisiLe: _str(r['saisiLe']),
          ),
      ],
    );

Map<String, dynamic> factureTransporteurToJson(FactureTransporteur f) => {
  'reference': f.reference,
  'transporteurId': f.transporteurId,
  'plaque': f.plaque,
  'dateEmission': f.dateEmission,
  'observations': f.observations,
  'montant': f.montant,
  'avance': f.avance,
  'journalAvance': f.journalAvance,
  'version': f.version,
  'lignes': [
    for (final l in f.lignes)
      {
        'dossierId': l.dossierId,
        'bl': l.bl,
        'numeroConteneur': l.numeroConteneur,
        'montant': l.montant,
      },
  ],
  'reglements': [
    for (final r in f.reglements)
      {
        'id': r.id,
        'date': r.date,
        'montant': r.montant,
        'codeJournal': r.codeJournal,
        'modePaiement': r.modePaiement,
        'numeroCheque': r.numeroCheque,
        'observations': r.observations,
      },
  ],
};

AffectationVoyage affectationVoyageFromJson(Map<String, dynamic> json) =>
    AffectationVoyage(
      id: json['id'] as String,
      voyageCle: _str(json['voyageCle']),
      module: _str(json['module']),
      agentId: _str(json['agentId']),
      dateDepart: _str(json['dateDepart']),
      plaque: _str(json['plaque']),
      transporteur: _str(json['transporteur']),
      chauffeur: _str(json['chauffeur']),
      telephone: _str(json['telephone']),
      dossiers: _str(json['dossiers']),
      clients: _str(json['clients']),
      transitaire: _str(json['transitaire']),
      conteneurs: _str(json['conteneurs']),
      frais: {
        for (final e in ((json['frais'] as Map?) ?? const {}).entries)
          e.key as String: _num(e.value),
      },
      observations: _str(json['observations']),
      assignePar: _str(json['assignePar']),
      saisiPar: _str(json['saisiPar']),
      saisiLe: _str(json['saisiLe']),
      statut: json['statut'] as String? ?? 'Brouillon',
      validePar: _str(json['validePar']),
      valideLe: _str(json['valideLe']),
      creeLe: _str(json['creeLe']),
      aT1: json['aT1'] as bool? ?? false,
      factureId: _str(json['factureId']),
      version: (json['version'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> affectationVoyageToJson(
  AffectationVoyage a, {
  bool valider = false,
}) => {
  'voyageCle': a.voyageCle,
  'module': a.module,
  'agentId': a.agentId,
  'dateDepart': a.dateDepart,
  'plaque': a.plaque,
  'transporteur': a.transporteur,
  'chauffeur': a.chauffeur,
  'telephone': a.telephone,
  'dossiers': a.dossiers,
  'clients': a.clients,
  'transitaire': a.transitaire,
  'conteneurs': a.conteneurs,
  'frais': a.frais,
  'observations': a.observations,
  'version': a.version,
  if (a.t1Image != null) 't1Image': a.t1Image,
  if (valider) 'valider': true,
};

// Reprend dans l'affectation locale ce que le serveur a enregistré.
void applyAffectationVoyageJson(
  AffectationVoyage a,
  Map<String, dynamic> json,
) {
  final saved = affectationVoyageFromJson(json);
  a
    ..agentId = saved.agentId
    ..frais = saved.frais
    ..observations = saved.observations
    ..assignePar = saved.assignePar
    ..saisiPar = saved.saisiPar
    ..saisiLe = saved.saisiLe
    ..statut = saved.statut
    ..validePar = saved.validePar
    ..valideLe = saved.valideLe
    ..creeLe = saved.creeLe
    ..aT1 = saved.aT1
    ..t1Image = null
    ..factureId = saved.factureId
    ..version = saved.version;
}

AgentVoyage agentVoyageFromJson(Map<String, dynamic> json) => AgentVoyage(
  id: json['id'] as String,
  nom: _str(json['nom']),
  modules: {...((json['modules'] as List?) ?? const []).cast<String>()},
);

FactureAgent factureAgentFromJson(Map<String, dynamic> json) => FactureAgent(
  id: json['id'] as String,
  numero: (json['numero'] as num?)?.toInt() ?? 0,
  reference: _str(json['reference']),
  module: _str(json['module']),
  agentId: _str(json['agentId']),
  agentNom: _str(json['agentNom']),
  dateEmission: _str(json['dateEmission']),
  observations: _str(json['observations']),
  montant: _num(json['montant']),
  affectations: ((json['affectations'] as List?) ?? const []).cast<String>(),
  reglements: [
    for (final r in (json['reglements'] as List? ?? const []))
      ReglementFacture(
        id: r['id'] as String,
        date: _str(r['date']),
        montant: _num(r['montant']),
        codeJournal: _str(r['codeJournal']),
        modePaiement: _str(r['modePaiement']),
        numeroCheque: _str(r['numeroCheque']),
        observations: _str(r['observations']),
        auteur: _str(r['auteur']),
        saisiLe: _str(r['saisiLe']),
      ),
  ],
  version: (json['version'] as num?)?.toInt() ?? 0,
  auteur: _str(json['auteur']),
  dateSaisie: _str(json['dateSaisie']),
);

Map<String, dynamic> factureAgentToJson(FactureAgent f) => {
  'reference': f.reference,
  'module': f.module,
  'agentId': f.agentId,
  'agentNom': f.agentNom,
  'dateEmission': f.dateEmission,
  'observations': f.observations,
  'version': f.version,
  'affectations': f.affectations,
  'reglements': [
    for (final r in f.reglements)
      {
        'id': r.id,
        'date': r.date,
        'montant': r.montant,
        'codeJournal': r.codeJournal,
        'modePaiement': r.modePaiement,
        'numeroCheque': r.numeroCheque,
        'observations': r.observations,
      },
  ],
};

BonCaisse bonCaisseFromJson(Map<String, dynamic> json) => BonCaisse(
  id: json['id'] as String,
  numero: (json['numero'] as num?)?.toInt() ?? 0,
  categorie: _str(json['categorie']),
  date: _str(json['date']),
  codeJournal: _str(json['codeJournal']),
  beneficiaire: _str(json['beneficiaire']),
  motif: _str(json['motif']),
  referenceManuelle: _str(json['referenceManuelle']),
  observations: _str(json['observations']),
  lignes: [
    for (final l in (json['lignes'] as List? ?? const []))
      BonCaisseLigne(
        dossierId: _str(l['dossierId']),
        plaque: _str(l['plaque']),
        proprietaire: _str(l['proprietaire']),
        transporteurId: _str(l['transporteurId']),
        chauffeur: _str(l['chauffeur']),
        telephone: _str(l['telephone']),
        typeFraisId: _str(l['typeFraisId']),
        compte: _str(l['compte']),
        libelle: _str(l['libelle']),
        montant: _num(l['montant']),
      ),
  ],
  auteur: _str(json['auteur']),
  dateSaisie: _str(json['dateSaisie']),
  version: (json['version'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> bonCaisseToJson(BonCaisse b) => {
  'categorie': b.categorie,
  'date': b.date,
  'codeJournal': b.codeJournal,
  'beneficiaire': b.beneficiaire,
  'motif': b.motif,
  'referenceManuelle': b.referenceManuelle,
  'observations': b.observations,
  'version': b.version,
  'lignes': [
    for (final l in b.lignes)
      {
        'dossierId': l.dossierId,
        'plaque': l.plaque,
        'proprietaire': l.proprietaire,
        'transporteurId': l.transporteurId,
        'chauffeur': l.chauffeur,
        'telephone': l.telephone,
        'typeFraisId': l.typeFraisId,
        'compte': l.compte,
        'libelle': l.libelle,
        'montant': l.montant,
      },
  ],
};

DossierOperation dossierOperationFromJson(Map<String, dynamic> operation) =>
    DossierOperation(
      id: operation['id'] as String?,
      type: DossierOperationType.values.byName(operation['type'] as String),
      titre: _str(operation['titre']),
      categorie: _str(operation['categorie']),
      montant: _num(operation['montant']),
      date: _str(operation['date']),
      codeJournal: _str(operation['codeJournal']),
      modePaiement: _str(operation['modePaiement']),
      numeroCheque: _str(operation['numeroCheque']),
      observations: _str(operation['observations']),
      auteur: _str(operation['auteur']),
      saisiLe: _str(operation['saisiLe']),
    );

CaisseMouvement caisseMouvementFromJson(Map<String, dynamic> json) =>
    CaisseMouvement(
      id: json['id'] as String,
      type: _str(json['type']),
      date: _str(json['date']),
      montant: _num(json['montant']),
      recuNumero: (json['recuNumero'] as num?)?.toInt() ?? 0,
      dossierId: _str(json['dossierId']),
      operationUid: _str(json['operationUid']),
      statutReglement: _str(json['statutReglement']),
      modePaiement: _str(json['modePaiement']),
      bonId: _str(json['bonId']),
      receptionneLe: _str(json['receptionneLe']),
      receptionnePar: _str(json['receptionnePar']),
      observations: _str(json['observations']),
      auteur: _str(json['auteur']),
      dateSaisie: _str(json['dateSaisie']),
    );

CaisseCloture caisseClotureFromJson(Map<String, dynamic> json) => CaisseCloture(
  caisse: _str(json['caisse']),
  date: _str(json['date']),
  recettes: _num(json['recettes']),
  depenses: _num(json['depenses']),
  solde: _num(json['solde']),
  auteur: _str(json['auteur']),
);

CaisseParametres caisseParametresFromJson(Map<String, dynamic>? json) =>
    CaisseParametres(
      principale: _str(json?['principale']),
      depenses: _str(json?['depenses']),
    );
