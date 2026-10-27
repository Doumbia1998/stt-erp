class ErpUser {
  final String id;
  String name;
  String login;
  String password;
  String role;
  Set<String> accessModules;
  // Photo de profil (JPEG en base64), null si aucune.
  String? photo;
  // Vrai quand la photo a été changée ou retirée et doit être envoyée.
  bool photoModifiee;

  ErpUser({
    required this.id,
    required this.name,
    required this.login,
    required this.password,
    required this.role,
    required this.accessModules,
    this.photo,
    this.photoModifiee = false,
  });
}

class Client {
  final String id, nom, telephone;
  final String societe;
  final String adresse;
  final String email;
  final String rccm;
  final double soldeInitial;
  final bool assujettiTva;
  String compteComptable;

  Client({
    required this.id,
    required this.nom,
    required this.telephone,
    this.societe = '',
    this.adresse = '',
    this.email = '',
    this.rccm = '',
    this.soldeInitial = 0,
    this.assujettiTva = false,
    this.compteComptable = '',
  });
}

class PlanAccount {
  final String id;
  String code;
  String libelle;
  String nature;
  String? tiersId;
  final double soldeInitial;
  final bool assujettiTva;

  PlanAccount({
    required this.id,
    required this.code,
    required this.libelle,
    required this.nature,
    this.tiersId,
    this.soldeInitial = 0,
    this.assujettiTva = false,
  });
}

class Depense {
  final String titre, categorie, date;
  final double montant;
  final String auteur;
  final String saisiLe;
  Depense({
    required this.titre,
    required this.montant,
    required this.categorie,
    required this.date,
    this.auteur = '',
    this.saisiLe = '',
  });
}

enum DossierOperationType {
  expense,
  clientInvoice,
  clientPayment,
  providerInvoice,
  providerAdvance,
  providerPayment,
}

enum DossierInvoiceKind { client, provider, forwarder, carrier }

enum SettlementKind { client, supplier, forwarder, carrier }

class Voyage {
  final String id;
  String dossierId;
  String plaque;
  String chauffeur;
  String origine;
  String destination;
  String depart;
  String arriveePrevue;
  String statut;

  Voyage({
    required this.id,
    required this.dossierId,
    required this.plaque,
    required this.chauffeur,
    required this.origine,
    required this.destination,
    required this.depart,
    required this.arriveePrevue,
    required this.statut,
  });
}

class InvoiceLine {
  final String description;
  final double quantite;
  final double prixUnitaire;
  final String numeroConteneur;
  final String bl;
  final String marchandise;
  final String typeConteneur;
  final double fraisTransit;
  final double volumePoids;
  final double surestariesMagasinage;
  final double fraisPeage;
  final double autresFrais;
  final double avanceCamion;
  final String plaqueVehicule;
  final String telephoneChauffeur;

  const InvoiceLine({
    required this.description,
    required this.quantite,
    required this.prixUnitaire,
    this.numeroConteneur = '',
    this.bl = '',
    this.marchandise = '',
    this.typeConteneur = '',
    this.fraisTransit = 0,
    this.volumePoids = 0,
    this.surestariesMagasinage = 0,
    this.fraisPeage = 0,
    this.autresFrais = 0,
    this.avanceCamion = 0,
    this.plaqueVehicule = '',
    this.telephoneChauffeur = '',
  });

  double get total => quantite * prixUnitaire;
  double get totalPrestataire =>
      fraisTransit +
      volumePoids +
      surestariesMagasinage +
      fraisPeage +
      autresFrais;
}

class DossierInvoice {
  final String id;
  // Numéro affiché dans les grilles (attribué par le serveur).
  int numero;
  String reference;
  final DossierInvoiceKind kind;
  String description;
  String observations;
  double montant;
  String statut;
  String dateEmission;
  List<InvoiceLine> lignes;

  DossierInvoice({
    required this.id,
    this.numero = 0,
    required this.reference,
    required this.kind,
    this.description = '',
    this.observations = '',
    this.montant = 0,
    this.statut = 'Brouillon',
    this.dateEmission = '',
    List<InvoiceLine>? lignes,
  }) : lignes = lignes ?? [];

  bool get estValidee => statut == 'Clôturée';
}

class JournalCode {
  String code;
  String intitule;
  String type;
  String compteTresorerie;

  JournalCode({
    required this.code,
    required this.intitule,
    required this.type,
    required this.compteTresorerie,
  });
}

int _idCounter = 0;

// Identifiant unique généré côté ERP (horodatage + compteur).
String newLocalId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

class DossierOperation {
  // Identifiant stable : permet de supprimer un règlement précis.
  final String id;
  final DossierOperationType type;
  final String titre;
  final String categorie;
  final double montant;
  final String date;
  final String codeJournal;
  final String modePaiement;
  final String numeroCheque;
  final String observations;
  final String auteur;
  // « jj/mm/aaaa hh:mm » de la saisie.
  final String saisiLe;

  DossierOperation({
    String? id,
    required this.type,
    required this.titre,
    this.categorie = '',
    required this.montant,
    required this.date,
    this.codeJournal = '',
    this.modePaiement = '',
    this.numeroCheque = '',
    this.observations = '',
    this.auteur = '',
    this.saisiLe = '',
  }) : id = id ?? newLocalId('op');
}

class TransitDossier {
  final String id, numDossier, numBL, numLB;
  final Client client;
  final int nbConteneurs;
  final String transitaire;
  final String dateCreation;
  final String typeFacturation;
  final String priorite;
  final String typeMarchandise;
  final String lieuMarchandise;
  final String lieuLivraison;
  final String dateArriveeBateau;
  final String description;
  final List<TransitContainer> conteneurs;
  Prestataire? prestataire;
  Prestataire? transitaireAffecte;
  Prestataire? transporteurAffecte;
  final DossierInvoice factureClient;
  final DossierInvoice facturePrestataire;
  final DossierInvoice factureTransitaire;
  final DossierInvoice factureTransporteur;
  String dateDebut, dateFin, statut;
  List<Depense> depenses;
  List<DossierOperation> operations;

  // Version enregistrée côté serveur (0 = dossier pas encore enregistré).
  int version;

  // Attribués par le serveur à l'enregistrement.
  int numero;
  String auteurSaisie;
  // « jj/mm/aaaa hh:mm » de la création.
  String dateSaisie;
  String dateLivraisonSouhaitee;

  TransitDossier({
    required this.id,
    required this.numDossier,
    required this.numBL,
    required this.numLB,
    required this.client,
    required this.nbConteneurs,
    required this.dateDebut,
    this.transitaire = '',
    this.dateCreation = '',
    this.typeFacturation = 'Tarif complet',
    this.priorite = 'Priorité normale',
    this.typeMarchandise = '',
    this.lieuMarchandise = '',
    this.lieuLivraison = '',
    this.dateArriveeBateau = '',
    this.description = '',
    this.prestataire,
    DossierInvoice? factureClient,
    DossierInvoice? facturePrestataire,
    DossierInvoice? factureTransitaire,
    DossierInvoice? factureTransporteur,
    List<TransitContainer>? conteneurs,
    this.dateFin = "-",
    this.statut = "Ouvert",
    List<Depense>? depenses,
    List<DossierOperation>? operations,
    this.version = 0,
    this.numero = 0,
    this.auteurSaisie = '',
    this.dateSaisie = '',
    this.dateLivraisonSouhaitee = '',
  }) : factureClient =
           factureClient ??
           DossierInvoice(
             id: '$id-client',
             reference: 'FC-$numDossier',
             kind: DossierInvoiceKind.client,
           ),
       facturePrestataire =
           facturePrestataire ??
           DossierInvoice(
             id: '$id-provider',
             reference: 'FP-$numDossier',
             kind: DossierInvoiceKind.provider,
           ),
       factureTransitaire =
           factureTransitaire ??
           DossierInvoice(
             id: '$id-forwarder',
             reference: 'FT-$numDossier',
             kind: DossierInvoiceKind.forwarder,
           ),
       factureTransporteur =
           factureTransporteur ??
           DossierInvoice(
             id: '$id-carrier',
             reference: 'FTR-$numDossier',
             kind: DossierInvoiceKind.carrier,
           ),
       conteneurs = conteneurs ?? [],
       depenses = depenses ?? [],
       operations = operations ?? [];

  double get totalDepenses =>
      depenses.fold(0, (sum, item) => sum + item.montant);

  double get totalFacturesClient =>
      (factureClient.statut == 'Clôturée' ? factureClient.montant : 0) +
      operations
          .where((entry) => entry.type == DossierOperationType.clientInvoice)
          .fold(0, (sum, entry) => sum + entry.montant);

  double get totalReglementsClient => operations
      .where((entry) => entry.type == DossierOperationType.clientPayment)
      .fold(0, (sum, entry) => sum + entry.montant);

  double get soldeClient => totalFacturesClient - totalReglementsClient;

  double get totalFacturesPrestataire =>
      (facturePrestataire.statut == 'Clôturée'
          ? facturePrestataire.montant
          : 0) +
      (factureTransitaire.statut == 'Clôturée'
          ? factureTransitaire.montant
          : 0) +
      (factureTransporteur.statut == 'Clôturée'
          ? factureTransporteur.montant
          : 0) +
      operations
          .where((entry) => entry.type == DossierOperationType.providerInvoice)
          .fold(0, (sum, entry) => sum + entry.montant);

  double get totalAvancesPrestataire => operations
      .where((entry) => entry.type == DossierOperationType.providerAdvance)
      .fold(0, (sum, entry) => sum + entry.montant);

  double get totalReglementsPrestataire => operations
      .where((entry) => entry.type == DossierOperationType.providerPayment)
      .fold(0, (sum, entry) => sum + entry.montant);

  double get soldePrestataire =>
      totalFacturesPrestataire -
      totalAvancesPrestataire -
      totalReglementsPrestataire;

  // Un dossier sans prestataire (transitaire « LUI MEME ») n'a que la facture client.
  bool get peutCloturer =>
      statut != 'Clôturé' &&
      factureClient.statut == 'Clôturée' &&
      (prestataire == null ||
          (prestataire!.type == 'Transitaire'
              ? true
              : prestataire!.type == 'Transporteur'
              ? factureTransporteur.statut == 'Clôturée'
              : facturePrestataire.statut == 'Clôturée')) &&
      soldeClient <= 0 &&
      soldePrestataire <= 0;

  bool get estFacture => factureClient.estValidee;
  bool get estCloture => statut == 'Clôturé';
  int get nbConteneurs20 => conteneurs.where((c) => c.isVingtPieds).length;
  int get nbConteneurs40 => conteneurs.where((c) => c.isQuarantePieds).length;

  // Nom affiché du transitaire (« LUI MEME » quand le client est son propre transitaire).
  String get nomTransitaire =>
      transitaireAffecte?.entreprise ??
      (transitaire.isEmpty ? '' : transitaire);

  // Règlements rattachés à une facture fournisseur (même règle que le serveur).
  Iterable<DossierOperation> reglementsDe(DossierInvoiceKind kind) {
    const categories = {
      DossierInvoiceKind.forwarder: 'Règlement Transitaire',
      DossierInvoiceKind.carrier: 'Règlement Transporteur',
    };
    return operations.where((op) {
      if (kind == DossierInvoiceKind.client) {
        return op.type == DossierOperationType.clientPayment;
      }
      if (op.type != DossierOperationType.providerPayment &&
          op.type != DossierOperationType.providerAdvance) {
        return false;
      }
      if (kind == DossierInvoiceKind.provider) {
        return !categories.values.contains(op.categorie);
      }
      return op.categorie == categories[kind];
    });
  }

  double totalRegleDe(DossierInvoiceKind kind) =>
      reglementsDe(kind).fold(0, (sum, op) => sum + op.montant);
}

class TransitContainer {
  final String numero;
  final String type;
  final String marchandise;
  final String observation;

  const TransitContainer({
    required this.numero,
    required this.type,
    required this.marchandise,
    this.observation = '',
  });

  bool get isVingtPieds => type.trim().startsWith('20');
  bool get isQuarantePieds => type.trim().startsWith('40');
}

class Prestataire {
  final String id;
  final String entreprise;
  final String type;
  final String pays;
  final String villePort;
  final String contact;
  final String telephone;
  final String email;
  final String services;
  final String adresse;
  final String rccm;
  final int nombreVehicules;
  final double soldeInitial;
  String compteComptable;
  // Camions du transporteur (plaque, chauffeur, téléphone).
  List<Vehicule> vehicules;

  Prestataire({
    required this.id,
    required this.entreprise,
    required this.type,
    required this.pays,
    required this.villePort,
    required this.contact,
    required this.telephone,
    required this.email,
    required this.services,
    this.adresse = '',
    this.rccm = '',
    this.nombreVehicules = 0,
    this.soldeInitial = 0,
    this.compteComptable = '',
    List<Vehicule>? vehicules,
  }) : vehicules = vehicules ?? [];
}

// Mode de règlement (espèces, chèque, virement…) relié aux journaux comptables.
class ModeReglement {
  final String id;
  String intitule;
  String type;
  String journalClient;
  String journalFournisseur;
  String compteTresorerie;

  ModeReglement({
    required this.id,
    required this.intitule,
    required this.type,
    this.journalClient = '',
    this.journalFournisseur = '',
    this.compteTresorerie = '',
  });

  bool get estCheque => type == 'Chèque';
}

// Type de frais (AMENDE, DROIT DE DOUANE…) et son sous-compte comptable.
class TypeFrais {
  final String id;
  int numero;
  String libelle;
  double montant;
  String compteGeneral;
  String compte;

  TypeFrais({
    required this.id,
    this.numero = 0,
    required this.libelle,
    this.montant = 0,
    this.compteGeneral = '',
    this.compte = '',
  });
}

// Prochain sous-compte d'un compte général : 65880000 -> 65880001, 41100000 -> 41100002…
// Les sous-comptes occupent au plus les 4 derniers chiffres « à zéro » du compte général.
String nextSubAccountCode(String general, Iterable<String> existingCodes) {
  general = general.trim();
  final codes = existingCodes.map((c) => c.trim().toUpperCase()).toSet()
    ..add(general);
  final trimmed = general.replaceFirst(RegExp(r'0+$'), '');
  final trailingZeros = general.length - trimmed.length;
  if (!RegExp(r'^\d+$').hasMatch(general) || trailingZeros == 0) {
    for (var n = 1; n < 1000; n++) {
      final candidate = '$general${n.toString().padLeft(3, '0')}';
      if (!codes.contains(candidate)) return candidate;
    }
    return '${general}999';
  }
  final base = int.parse(general);
  var span = 1;
  for (var i = 0; i < (trailingZeros < 4 ? trailingZeros : 4); i++) {
    span *= 10;
  }
  var last = base;
  for (final code in codes) {
    if (code.length != general.length) continue;
    final value = int.tryParse(code);
    if (value == null || value <= base || value >= base + span) continue;
    if (value > last) last = value;
  }
  // Le numéro proposé n'est jamais un code déjà présent dans le plan.
  var next = last + 1;
  while (codes.contains(next.toString().padLeft(general.length, '0'))) {
    next++;
  }
  return next.toString().padLeft(general.length, '0');
}

// Compte « général » : numérique, au moins deux zéros finaux (41100000, 65880000…).
bool isGeneralAccountCode(String code) =>
    RegExp(r'^\d{4,}$').hasMatch(code) && code.endsWith('00');

class Vehicule {
  final String id;
  String plaque;
  String chauffeur;
  String telephone;

  Vehicule({
    required this.id,
    required this.plaque,
    this.chauffeur = '',
    this.telephone = '',
  });
}

// Conteneur facturé par un transitaire (un BL d'un dossier), avec son camion.
class FactureTransitaireLigne {
  String dossierId;
  String bl;
  String numeroConteneur;
  String marchandise;
  String typeConteneur;
  String dateDepart;
  String transporteurId;
  String plaque;
  String telephoneChauffeur;
  double fraisTransit;
  double surestariesMagasinage;
  double volumePoids;
  double autresFrais;
  double fraisPeage;
  // Transport dû au transporteur et avance déjà versée au camion.
  double montantTransport;
  double avanceCamion;

  FactureTransitaireLigne({
    this.dossierId = '',
    this.bl = '',
    this.numeroConteneur = '',
    this.marchandise = '',
    this.typeConteneur = '',
    this.dateDepart = '',
    this.transporteurId = '',
    this.plaque = '',
    this.telephoneChauffeur = '',
    this.fraisTransit = 0,
    this.surestariesMagasinage = 0,
    this.volumePoids = 0,
    this.autresFrais = 0,
    this.fraisPeage = 0,
    this.montantTransport = 0,
    this.avanceCamion = 0,
  });

  double get montant =>
      fraisTransit +
      surestariesMagasinage +
      volumePoids +
      autresFrais +
      fraisPeage;

  // Identifie le conteneur d'un dossier (facturé une seule fois).
  String get cleConteneur => '$dossierId|${numeroConteneur.toUpperCase()}';
}

class ReglementFacture {
  final String id;
  final String date;
  final double montant;
  final String codeJournal;
  final String modePaiement;
  final String numeroCheque;
  final String observations;
  final String auteur;
  final String saisiLe;

  ReglementFacture({
    String? id,
    required this.date,
    required this.montant,
    this.codeJournal = '',
    this.modePaiement = '',
    this.numeroCheque = '',
    this.observations = '',
    this.auteur = '',
    this.saisiLe = '',
  }) : id = id ?? newLocalId('reg');
}

// Facture d'un transitaire regroupant les conteneurs de plusieurs BL / dossiers.
class FactureTransitaire {
  final String id;
  int numero;
  String reference;
  String transitaireId;
  String dateEmission;
  String observations;
  List<FactureTransitaireLigne> lignes;
  List<ReglementFacture> reglements;
  int version;
  String auteur;
  String dateSaisie;

  FactureTransitaire({
    required this.id,
    this.numero = 0,
    required this.reference,
    required this.transitaireId,
    required this.dateEmission,
    this.observations = '',
    List<FactureTransitaireLigne>? lignes,
    List<ReglementFacture>? reglements,
    this.version = 0,
    this.auteur = '',
    this.dateSaisie = '',
  }) : lignes = lignes ?? [],
       reglements = reglements ?? [];

  // Frais facturés par le transitaire (transit, surestaries, volume, autres, péage).
  double get totalFrais => lignes.fold(0, (s, l) => s + l.montant);
  // Avances camion versées par le transitaire : elles lui sont remboursées.
  double get totalAvances => lignes.fold(0, (s, l) => s + l.avanceCamion);
  double get montant => totalFrais + totalAvances;
  double get totalRegle => reglements.fold(0, (s, r) => s + r.montant);
  double get reliquat => montant - totalRegle;
  bool get estAcquittee => montant > 0 && reliquat <= 0.001;
}

class FactureTransporteurLigne {
  String dossierId;
  String bl;
  String numeroConteneur;
  double montant;

  FactureTransporteurLigne({
    this.dossierId = '',
    this.bl = '',
    this.numeroConteneur = '',
    this.montant = 0,
  });

  String get cleConteneur => '$dossierId|${numeroConteneur.toUpperCase()}';
}

// Facture d'un transporteur pour un camion : conteneurs transportés, avance, règlements.
class FactureTransporteur {
  final String id;
  int numero;
  String reference;
  String transporteurId;
  String plaque;
  String dateEmission;
  String observations;
  // Total TTC (somme des conteneurs ou prix convenu avec le transporteur).
  double montant;
  double avance;
  String journalAvance;
  List<FactureTransporteurLigne> lignes;
  List<ReglementFacture> reglements;
  int version;
  String auteur;
  String dateSaisie;

  FactureTransporteur({
    required this.id,
    this.numero = 0,
    required this.reference,
    required this.transporteurId,
    this.plaque = '',
    required this.dateEmission,
    this.observations = '',
    this.montant = 0,
    this.avance = 0,
    this.journalAvance = '',
    List<FactureTransporteurLigne>? lignes,
    List<ReglementFacture>? reglements,
    this.version = 0,
    this.auteur = '',
    this.dateSaisie = '',
  }) : lignes = lignes ?? [],
       reglements = reglements ?? [];

  double get netAPayer => montant - avance;
  double get totalRegle => reglements.fold(0, (s, r) => s + r.montant);
  double get reliquat => netAPayer - totalRegle;
  bool get estPayee => montant > 0 && reliquat <= 0.001;
}

// Frais saisis par chaque module sur un voyage qui lui est affecté.
const fraisParModuleVoyage = <String, List<String>>{
  'Frontière': ['Frais de passage', 'TS Frontière'],
  'Bureau DD': ['Frais de circuit', 'DD conteneur ou camion', 'TS'],
  'Enquête': ['Amende', 'LS', 'TS spécial', 'TS ordinaire'],
};

// Modules qui joignent la photo du T1 à leur saisie.
const modulesAvecT1 = {'Frontière'};

// Préfixe des factures d'agents par module.
const prefixeFactureAgent = <String, String>{
  'Frontière': 'FAC-FRT',
  'Bureau DD': 'FAC-BDD',
  'Enquête': 'FAC-ENQ',
};

// Voyage confié à un module (Frontière, Bureau DD, Enquête) et frais de l'agent.
class AffectationVoyage {
  final String id;
  final String voyageCle;
  final String module;
  String agentId;
  final String dateDepart;
  final String plaque;
  final String transporteur;
  final String chauffeur;
  final String telephone;
  final String dossiers;
  final String clients;
  final String transitaire;
  final String conteneurs;
  Map<String, double> frais;
  String observations;
  String assignePar;
  String saisiPar;
  String saisiLe;
  // « Brouillon » puis « Validé » : une saisie validée ne se modifie plus.
  String statut;
  String validePar;
  String valideLe;
  String creeLe;
  // Vrai quand la photo du T1 est enregistrée sur le serveur.
  bool aT1;
  // Photo du T1 à envoyer : null = inchangée, '' = retirée.
  String? t1Image;
  String factureId;
  int version;

  AffectationVoyage({
    required this.id,
    required this.voyageCle,
    required this.module,
    this.agentId = '',
    this.dateDepart = '',
    this.plaque = '',
    this.transporteur = '',
    this.chauffeur = '',
    this.telephone = '',
    this.dossiers = '',
    this.clients = '',
    this.transitaire = '',
    this.conteneurs = '',
    Map<String, double>? frais,
    this.observations = '',
    this.assignePar = '',
    this.saisiPar = '',
    this.saisiLe = '',
    this.statut = 'Brouillon',
    this.validePar = '',
    this.valideLe = '',
    this.creeLe = '',
    this.aT1 = false,
    this.t1Image,
    this.factureId = '',
    this.version = 0,
  }) : frais = frais ?? {};

  double get total => frais.values.fold(0, (s, v) => s + v);
  bool get estValide => statut == 'Validé';
  bool get estSaisi => total > 0 || aT1;
  bool get estFacture => factureId.isNotEmpty;
}

// Utilisateur d'un module voyage, proposé comme agent à l'affectation.
class AgentVoyage {
  final String id;
  final String nom;
  final Set<String> modules;

  const AgentVoyage({
    required this.id,
    required this.nom,
    required this.modules,
  });
}

// Facture d'un agent (Frontière, Bureau DD, Enquête) : ses saisies validées,
// réglée par la Direction.
class FactureAgent {
  final String id;
  int numero;
  String reference;
  final String module;
  String agentId;
  String agentNom;
  String dateEmission;
  String observations;
  double montant;
  List<String> affectations;
  final List<ReglementFacture> reglements;
  int version;
  String auteur;
  String dateSaisie;

  FactureAgent({
    required this.id,
    this.numero = 0,
    required this.reference,
    required this.module,
    this.agentId = '',
    this.agentNom = '',
    required this.dateEmission,
    this.observations = '',
    this.montant = 0,
    List<String>? affectations,
    List<ReglementFacture>? reglements,
    this.version = 0,
    this.auteur = '',
    this.dateSaisie = '',
  }) : affectations = affectations ?? [],
       reglements = reglements ?? [];

  double get totalRegle => reglements.fold(0, (s, r) => s + r.montant);
  double get reliquat => montant - totalRegle;
  bool get estPayee => montant > 0 && reliquat <= 0.001;
  String get dernierReglement =>
      reglements.isEmpty ? '' : reglements.last.date.split(' ').first;
}

// Type de prestataire qui porte nos propres camions (flotte STT).
const typeFlotteStt = 'Flotte STT';

// Ligne d'un bon de caisse : un frais d'un camion ou une dépense administrative.
class BonCaisseLigne {
  String dossierId;
  String plaque;
  // « Transporteur » (camion d'un transporteur) ou « STT » (nos camions).
  String proprietaire;
  String transporteurId;
  String chauffeur;
  String telephone;
  String typeFraisId;
  String compte;
  String libelle;
  double montant;

  BonCaisseLigne({
    this.dossierId = '',
    this.plaque = '',
    this.proprietaire = '',
    this.transporteurId = '',
    this.chauffeur = '',
    this.telephone = '',
    this.typeFraisId = '',
    this.compte = '',
    this.libelle = '',
    this.montant = 0,
  });
}

// Bon de caisse numéroté : frais des camions ou dépense administrative.
class BonCaisse {
  final String id;
  int numero;
  final String categorie;
  String date;
  String codeJournal;
  String beneficiaire;
  String motif;
  String referenceManuelle;
  String observations;
  List<BonCaisseLigne> lignes;
  String auteur;
  String dateSaisie;
  int version;

  static const fraisCamion = 'Frais camion';
  static const depenseAdministrative = 'Dépense administrative';

  BonCaisse({
    required this.id,
    this.numero = 0,
    required this.categorie,
    required this.date,
    this.codeJournal = '',
    this.beneficiaire = '',
    this.motif = '',
    this.referenceManuelle = '',
    this.observations = '',
    List<BonCaisseLigne>? lignes,
    this.auteur = '',
    this.dateSaisie = '',
    this.version = 0,
  }) : lignes = lignes ?? [];

  String get reference =>
      numero == 0 ? 'BC-…' : 'BC-${numero.toString().padLeft(5, '0')}';
  double get montant => lignes.fold(0, (s, l) => s + l.montant);
  int get nbCamions =>
      lignes.map((l) => l.plaque).where((p) => p.isNotEmpty).toSet().length;
}
