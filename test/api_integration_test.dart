// Test de bout en bout contre une vraie API (ignoré sans adresse) :
// flutter test test/api_integration_test.dart --dart-define=API_TEST_URL=http://127.0.0.1:3099 --dart-define=API_TEST_PASSWORD=...
import 'package:flutter_test/flutter_test.dart';
import 'package:stt/erp_backend.dart';
import 'package:stt/models.dart';

const _url = String.fromEnvironment('API_TEST_URL');
const _password = String.fromEnvironment('API_TEST_PASSWORD');

void main() {
  test(
    'Data saved through the API is found again after a new login',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final backend = HttpErpBackend(_url);
      await backend.login('admin', _password);

      final account = PlanAccount(
        id: 'acc-$suffix',
        code: '411$suffix',
        libelle: 'Client intégration',
        nature: 'Client',
      );
      await backend.saveAccount(account);
      final journalAccount = PlanAccount(
        id: 'acc-bq-$suffix',
        code: '521$suffix',
        libelle: 'Banque intégration',
        nature: 'Banque',
      );
      await backend.saveAccount(journalAccount);
      await backend.saveJournal(
        JournalCode(
          code: 'BQ$suffix',
          intitule: 'Banque',
          type: 'Banque',
          compteTresorerie: journalAccount.code,
        ),
      );
      final client = Client(
        id: 'client-$suffix',
        nom: 'Client intégration $suffix',
        telephone: '+223 70 00 00 00',
        compteComptable: account.code,
      );
      await backend.saveClient(client);

      final dossier = TransitDossier(
        id: 'dossier-$suffix',
        numDossier: 'STT-$suffix',
        numBL: 'BL-1',
        numLB: '',
        client: client,
        nbConteneurs: 1,
        dateDebut: '09/10/2026',
        dateCreation: '09/10/2026',
        conteneurs: const [
          TransitContainer(
            numero: 'MSKU1234567',
            type: '40 pieds',
            marchandise: 'Riz',
          ),
        ],
      );
      await backend.saveDossier(dossier);
      expect(dossier.version, 1);

      dossier.factureClient
        ..lignes = const [
          InvoiceLine(
            description: 'Transport Bamako',
            quantite: 1,
            prixUnitaire: 75000,
          ),
        ]
        ..montant = 75000
        ..statut = 'Clôturée'
        ..dateEmission = '10/10/2026';
      dossier.operations.add(
        DossierOperation(
          type: DossierOperationType.clientPayment,
          titre: 'Règlement espèces',
          montant: 75000,
          date: '10/10/2026 14:05',
          codeJournal: 'BQ$suffix',
        ),
      );
      await backend.saveDossier(dossier);
      expect(dossier.version, 2);

      // Mise à jour comptable : facture et règlement déversés et équilibrés.
      final update = await backend.miseAJourComptable(
        du: '01/10/2026',
        au: '31/10/2026',
        categories: const ['ventes', 'reglements'],
      );
      expect(update.ecritures, greaterThanOrEqualTo(2));
      final synthese = await backend.journauxComptables(2026);
      for (final periode in synthese.periodes) {
        expect(periode.debit, periode.credit);
      }
      final ventes = await backend.ecritures('VEN', '2026-10');
      expect(
        ventes.any((l) => l.compte == account.code && l.debit == 75000),
        isTrue,
      );
      expect(synthese.derniereMiseAJour, contains('31/10/2026'));

      // Une seconde session (autre poste) retrouve tout.
      final data = await HttpErpBackend(_url).login('admin', _password);
      final reloaded = data.dossiers.singleWhere((d) => d.id == dossier.id);
      expect(reloaded.client.nom, client.nom);
      expect(reloaded.version, 2);
      expect(reloaded.conteneurs.single.numero, 'MSKU1234567');
      expect(reloaded.factureClient.statut, 'Clôturée');
      expect(
        reloaded.factureClient.lignes.single.description,
        'Transport Bamako',
      );
      expect(reloaded.operations.single.date, '10/10/2026 14:05');
      expect(reloaded.soldeClient, 0);
      expect(
        data.comptes.singleWhere((a) => a.id == account.id).tiersId,
        client.id,
      );

      // Une modification depuis une version périmée est refusée.
      final stale = data.dossiers.singleWhere((d) => d.id == dossier.id)
        ..version = 1;
      await expectLater(
        HttpErpBackend(
          _url,
        ).login('admin', _password).then((_) => backend.saveDossier(stale)),
        throwsA(
          isA<ErpBackendException>().having((e) => e.status, 'status', 409),
        ),
      );
      // Un règlement peut être supprimé ; un dossier vide aussi.
      dossier.operations.clear();
      await backend.saveDossier(dossier);
      expect(dossier.version, 3);
      expect(dossier.numero, greaterThan(0));
      expect(dossier.auteurSaisie, 'Administrateur');
      final empty = TransitDossier(
        id: 'vide-$suffix',
        numDossier: 'VIDE-$suffix',
        numBL: '',
        numLB: '',
        client: client,
        nbConteneurs: 0,
        dateDebut: '09/10/2026',
      );
      await backend.saveDossier(empty);
      await backend.deleteDossier(empty);
      final after = await backend.reload();
      expect(after.dossiers.where((d) => d.id == empty.id), isEmpty);
      expect(
        after.dossiers.singleWhere((d) => d.id == dossier.id).operations,
        isEmpty,
      );
      // Transporteur avec camions et facture transitaire sur le conteneur du dossier.
      final transitaire = Prestataire(
        id: 'transit-$suffix',
        entreprise: 'Transitaire $suffix',
        type: 'Transitaire',
        pays: 'Mali',
        villePort: 'Bamako',
        contact: '',
        telephone: '',
        email: '',
        services: '',
      );
      final carrier = Prestataire(
        id: 'carrier-$suffix',
        entreprise: 'Transport $suffix',
        type: 'Transporteur',
        pays: 'Mali',
        villePort: 'Bamako',
        contact: '',
        telephone: '',
        email: '',
        services: '',
        vehicules: [
          Vehicule(
            id: 'veh-$suffix',
            plaque: 'T$suffix'.substring(0, 9),
            chauffeur: 'Moussa',
            telephone: '70000001',
          ),
        ],
      );
      await backend.savePrestataire(transitaire);
      await backend.savePrestataire(carrier);
      final facture = FactureTransitaire(
        id: 'ftr-$suffix',
        reference: 'FAC-TRS-$suffix',
        transitaireId: transitaire.id,
        dateEmission: '16/10/2026',
        lignes: [
          FactureTransitaireLigne(
            dossierId: dossier.id,
            bl: dossier.numBL,
            numeroConteneur: 'MSKU1234567',
            transporteurId: carrier.id,
            plaque: carrier.vehicules.single.plaque,
            fraisTransit: 40000,
            montantTransport: 250000,
            avanceCamion: 50000,
          ),
        ],
      );
      await backend.saveFactureTransitaire(facture);
      expect(facture.version, 1);
      expect(facture.numero, greaterThan(0));
      final withInvoice = await backend.reload();
      final reloadedInvoice = withInvoice.facturesTransitaire.singleWhere(
        (f) => f.id == facture.id,
      );
      expect(reloadedInvoice.montant, 40000);
      expect(reloadedInvoice.lignes.single.avanceCamion, 50000);
      expect(
        withInvoice.prestataires
            .singleWhere((p) => p.id == carrier.id)
            .vehicules
            .single
            .chauffeur,
        'Moussa',
      );
      await backend.deleteFactureTransitaire(facture);

      await backend.logout();
    },
    skip: _url.isEmpty ? 'API_TEST_URL non défini' : null,
  );
}
