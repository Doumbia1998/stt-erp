class ErpUser {
  final String id;
  String name;
  String login;
  String password;
  String role;
  Set<String> accessModules;

  ErpUser({
    required this.id,
    required this.name,
    required this.login,
    required this.password,
    required this.role,
    required this.accessModules,
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
              ? factureTransitaire.statut == 'Clôturée'
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
  });
}
