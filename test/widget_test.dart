// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:stt/main.dart';
import 'package:stt/models_json.dart';

void main() {
  // Les tests n'appellent pas l'API : les données restent en mémoire.
  setUp(() => erpBackend = MemoryErpBackend());

  test('A dossier survives the JSON round trip used by the API', () {
    final client = Client(id: 'client-1', nom: 'Client test', telephone: '');
    final provider = Prestataire(
      id: 'provider-1',
      entreprise: 'Transport test',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
    );
    final dossier =
        TransitDossier(
            id: 'dossier-1',
            numDossier: 'STT-TEST',
            numBL: 'BL-1',
            numLB: '',
            client: client,
            prestataire: provider,
            nbConteneurs: 1,
            dateDebut: '09/10/2026',
            conteneurs: const [
              TransitContainer(
                numero: 'MSKU1234567',
                type: '40 pieds',
                marchandise: 'Riz',
              ),
            ],
            version: 3,
          )
          ..transporteurAffecte = provider
          ..depenses.add(
            Depense(
              titre: 'Péage',
              montant: 5000,
              categorie: 'Route',
              date: '10/10/2026 08:30',
            ),
          )
          ..operations.add(
            DossierOperation(
              type: DossierOperationType.clientPayment,
              titre: 'Règlement',
              montant: 100000,
              date: '10/10/2026 09:00',
              codeJournal: 'BQ',
            ),
          );
    dossier.factureClient
      ..statut = 'Clôturée'
      ..montant = 100000
      ..dateEmission = '10/10/2026'
      ..lignes = const [
        InvoiceLine(
          description: 'Transport Bamako',
          quantite: 1,
          prixUnitaire: 100000,
        ),
      ];

    final json = dossierToJson(dossier)..['id'] = dossier.id;
    final restored = dossierFromJson(
      json,
      clients: {client.id: client},
      prestataires: {provider.id: provider},
    );

    expect(restored.client, same(client));
    expect(restored.prestataire, same(provider));
    expect(restored.transporteurAffecte, same(provider));
    expect(restored.version, 3);
    expect(restored.conteneurs.single.numero, 'MSKU1234567');
    expect(restored.factureClient.statut, 'Clôturée');
    expect(restored.factureClient.lignes.single.total, 100000);
    expect(restored.depenses.single.date, '10/10/2026 08:30');
    expect(restored.operations.single.codeJournal, 'BQ');
    expect(restored.soldeClient, 0);
  });

  testWidgets('Wrong credentials keep the user on the login page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'mauvais');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('SE CONNECTER'), findsOneWidget);
  });

  testWidgets('ERP modules expose their pages from the top dropdowns', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TransitTrackerApp());

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Dépenses par catégorie'), findsOneWidget);
    expect(find.text('Modules de gestion'), findsOneWidget);
    await tester.tap(find.byTooltip('Alertes conteneurs'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi des conteneurs'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profil utilisateur'));
    await tester.pumpAndSettle();
    expect(find.text('Administrateur'), findsWidgets);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();

    expect(find.text('Gestion'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Comptabilité'));
    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Comptable').last);
    await tester.pumpAndSettle();

    expect(find.text('Plan Comptable'), findsWidgets);
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '411001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Client Test',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('411001 — Client Test'), findsOneWidget);
    expect(find.byTooltip('Modifier le compte'), findsOneWidget);
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '411001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Compte en double',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Doublon détecté'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '401001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Transport Dakar',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fournisseur').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '102001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Banque STT',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code journaux').last);
    await tester.pumpAndSettle();
    expect(find.text('Interrogation et Lettrage'), findsNothing);
    await tester.tap(find.text('NOUVEAU JOURNAL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-code')), 'BQ');
    await tester.enterText(
      find.byKey(const ValueKey('journal-intitule')),
      'Banque principale',
    );
    final journalAccountField = find.descendant(
      of: find.byKey(const ValueKey('journal-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(journalAccountField, '102001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('102001 • Banque STT').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BQ • Banque principale'), findsOneWidget);

    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Comptable').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Recouvrement'));
    await tester.tap(find.byTooltip('Recouvrement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etat des Impayés').last);
    await tester.pumpAndSettle();

    expect(find.text('Etat des Impayés'), findsWidgets);
    await tester.tap(find.byTooltip('Recouvrement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Règlement').last);
    await tester.pumpAndSettle();
    expect(find.text('Saisie des Règlements Clients'), findsOneWidget);
    expect(find.text('Saisie des Règlements Transporteurs'), findsOneWidget);
    await tester.tap(find.text('Saisie des Règlements Transporteurs'));
    await tester.pumpAndSettle();
    expect(find.text('Saisie des règlements transporteurs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dossier').last);
    await tester.pumpAndSettle();

    expect(find.text('Gestion des Dossiers'), findsOneWidget);
    // Sans client, la création de dossier est expliquée plutôt qu'ouverte.
    await tester.tap(find.byKey(const ValueKey('dossier-new')));
    await tester.pumpAndSettle();
    expect(find.text('Client requis'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Transitaire'));
    await tester.tap(find.byTooltip('Transitaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clients').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Client Test');
    await tester.enterText(find.byType(TextFormField).at(1), 'Société Test');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '+223 70 000 0000',
    );
    final clientAccountField = find.descendant(
      of: find.byKey(const ValueKey('client-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(clientAccountField, '411001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('411001 • Client Test').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Compte client : 411001'), findsOneWidget);
    expect(find.byTooltip('Modifier le client'), findsOneWidget);
    await tester.tap(find.byTooltip('Modifier le client'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '+223 76 111 2222',
    );
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+223 76 111 2222'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dossier').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dossier-new')));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau dossier client'), findsOneWidget);
    expect(find.text('Transitaire *'), findsOneWidget);
    expect(find.text('Prestataire affecté'), findsNothing);
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Type de facturation')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Type de priorité')),
      findsOneWidget,
    );

    Future<void> pick(String key, String query, String option) async {
      final field = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, query);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await pick('dossier-client-search', 'client', 'Client Test');
    await pick('dossier-transitaire-search', 'lui', 'LUI MEME');
    await tester.enterText(find.byKey(const ValueKey('dossier-bl')), 'BL-001');

    final addContainer = find.byKey(const ValueKey('container-add'));
    await tester.scrollUntilVisible(
      addContainer,
      300,
      scrollable: find
          .descendant(of: dialog, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('Liste des conteneurs'), findsOneWidget);
    expect(find.byKey(const ValueKey('container-row-0')), findsOneWidget);
    await tester.tap(addContainer);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('container-row-1')), findsOneWidget);
    final containerNumber = find.byKey(const ValueKey('container-number-0'));
    await tester.ensureVisible(containerNumber);
    await tester.enterText(containerNumber, 'MSKU1234567');
    await tester.tap(find.byKey(const ValueKey('dossier-save')));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau dossier client'), findsNothing);

    final grid = find.byKey(const ValueKey('dossiers-grid'));
    Finder inGrid(Finder finder) => find.descendant(of: grid, matching: finder);
    expect(inGrid(find.text('Client Test')), findsOneWidget);
    expect(inGrid(find.text('LUI MEME')), findsOneWidget);
    expect(inGrid(find.text('Non facturé')), findsOneWidget);
    expect(find.text('1 dossier(s) • 1 conteneur(s)'), findsOneWidget);

    // Facturation du dossier : un montant par conteneur, total calculé.
    await tester.tap(inGrid(find.text('Client Test')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dossier-invoice')));
    await tester.pumpAndSettle();
    expect(find.text('Facturation d’un dossier client'), findsOneWidget);
    final reference = tester
        .widget<TextFormField>(find.byKey(const ValueKey('invoice-number')))
        .controller!
        .text;
    expect(reference, startsWith('FAC-STT-'));
    final amount = find.byKey(const ValueKey('invoice-amount-0'));
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '100000');
    await tester.pumpAndSettle();
    final total = tester.widget<Text>(
      find.byKey(const ValueKey('invoice-total')),
    );
    expect(total.data!.replaceAll(RegExp(r'\D'), ''), '100000');
    await tester.tap(find.byKey(const ValueKey('invoice-validate')));
    await tester.pumpAndSettle();
    expect(inGrid(find.text('Facturé')), findsOneWidget);
    expect(inGrid(find.text(reference)), findsOneWidget);

    // Le filtre « Non facturés » masque le dossier facturé.
    await tester.tap(find.text('Non facturés'));
    await tester.pumpAndSettle();
    expect(inGrid(find.text('Client Test')), findsNothing);
    await tester.tap(find.text('Tous'));
    await tester.pumpAndSettle();
    expect(inGrid(find.text('Client Test')), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Prestation'));
    await tester.tap(find.byTooltip('Prestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture Client').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factures validées'));
    await tester.pumpAndSettle();
    expect(find.textContaining(reference), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voyages').last);
    await tester.pumpAndSettle();
    expect(find.text('Nbre de voyages : 0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-voyage')));
    await tester.pumpAndSettle();
    Finder voyageField(int i) => find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        )
        .at(i);
    await tester.enterText(voyageField(0), 'AB 1234 MD');
    await tester.enterText(voyageField(1), 'Chauffeur Test');
    await tester.enterText(voyageField(2), 'Dakar');
    await tester.enterText(voyageField(3), 'Bamako');
    await tester.enterText(voyageField(4), '12/10/2026');
    await tester.enterText(voyageField(5), '15/10/2026');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('voyages-grid')),
        matching: find.text('AB 1234 MD'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nbre de voyages : 1'), findsOneWidget);
  });

  testWidgets('Mobile uses module drawer and can create a provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    (erpBackend as MemoryErpBackend).comptes.add(
      PlanAccount(
        id: 'account-401001',
        code: '401001',
        libelle: 'Transport Dakar',
        nature: 'Fournisseur',
      ),
    );
    (erpBackend as MemoryErpBackend).clients.add(
      Client(id: 'client-mobile', nom: 'Client Mobile', telephone: ''),
    );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir les modules'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('header-stt-logo')), findsOneWidget);
    final drawerPrestation = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Prestation'),
    );
    await tester.ensureVisible(drawerPrestation);
    await tester.tap(drawerPrestation);
    await tester.pumpAndSettle();
    final drawerProvider = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Espace Prestataire'),
    );
    await tester.tap(drawerProvider);
    await tester.pumpAndSettle();

    expect(find.text('Aucun prestataire enregistré'), findsOneWidget);
    await tester.tap(find.text('NOUVEAU PRESTATAIRE'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Transport Dakar');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      '+221 77 000 0000',
    );
    await tester.enterText(
      find.byType(TextFormField).at(10),
      'Transport routier',
    );
    final providerAccountField = find.descendant(
      of: find.byKey(const ValueKey('provider-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(providerAccountField);
    await tester.enterText(providerAccountField, '401001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('401001 • Transport Dakar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Transport Dakar'), findsOneWidget);
    expect(find.textContaining('Bamako, Mali'), findsOneWidget);
    expect(find.textContaining('Compte fournisseur : 401001'), findsOneWidget);
    expect(find.byTooltip('Portail à activer'), findsOneWidget);
    await tester.tap(find.byTooltip('Modifier le prestataire'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'Bamako Centre');
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bamako Centre, Mali'), findsOneWidget);

    await tester.tap(find.byTooltip('Ouvrir les modules'));
    await tester.pumpAndSettle();
    final drawerTransport = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Transport'),
    );
    await tester.ensureVisible(drawerTransport);
    await tester.tap(drawerTransport);
    await tester.pumpAndSettle();
    final drawerDossier = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Dossier'),
    );
    await tester.tap(drawerDossier);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('dossier-new')));
    await tester.tap(find.byKey(const ValueKey('dossier-new')));
    await tester.pumpAndSettle();
    final layoutError = tester.takeException();
    if (layoutError is FlutterError) {
      for (final diagnostic in layoutError.diagnostics) {
        debugPrint(diagnostic.toString());
      }
    }
    expect(layoutError, isNull);
    expect(find.text('Nouveau dossier client'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dossier-transitaire-search')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Liste des conteneurs'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Liste des conteneurs'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
  });

  testWidgets('Transitaire invoice groups several BL with the carrier truck', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = Client(id: 'client-t', nom: 'Client Transit', telephone: '');
    final transitaire = Prestataire(
      id: 'transitaire-1',
      entreprise: 'BOUARE',
      type: 'Transitaire',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
    );
    final carrier = Prestataire(
      id: 'transp-1',
      entreprise: 'SOSAF',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
      vehicules: [
        Vehicule(
          id: 'veh-1',
          plaque: 'AB 1234 MD',
          chauffeur: 'Moussa',
          telephone: '70000001',
        ),
      ],
    );
    TransitDossier dossier(String id, String bl, List<String> containers) =>
        TransitDossier(
          id: id,
          numDossier: 'STT-$id',
          numBL: bl,
          numLB: '',
          client: client,
          nbConteneurs: containers.length,
          dateDebut: '09/10/2026',
          dateCreation: '09/10/2026',
          prestataire: transitaire,
          conteneurs: [
            for (final c in containers)
              TransitContainer(
                numero: c,
                type: '40 pieds',
                marchandise: 'Motos',
              ),
          ],
        )..transitaireAffecte = transitaire;
    (erpBackend as MemoryErpBackend)
      ..clients.add(client)
      ..prestataires.addAll([
        transitaire,
        carrier,
        Prestataire(
          id: 'transp-2',
          entreprise: 'STL',
          type: 'Transporteur',
          pays: 'Mali',
          villePort: 'Bamako',
          contact: '',
          telephone: '',
          email: '',
          services: '',
          vehicules: [
            Vehicule(
              id: 'veh-2',
              plaque: 'BF 5295 MD',
              chauffeur: 'Issa',
              telephone: '+223 90 34 12',
            ),
          ],
        ),
      ])
      ..journaux.add(
        JournalCode(
          code: 'CA',
          intitule: 'Caisse principale',
          type: 'Caisse',
          compteTresorerie: '571000',
        ),
      )
      ..dossiers.addAll([
        dossier('d1', 'BL-1', ['MSKU0000001', 'MSKU0000002']),
        dossier('d2', 'BL-2', ['TCLU0000003']),
      ]);

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Prestation'));
    await tester.tap(find.byTooltip('Prestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture Transitaire').last);
    await tester.pumpAndSettle();
    expect(
      find.text('0 facture(s) • 3 conteneur(s) à facturer'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('transitaire-invoice-new')));
    await tester.pumpAndSettle();
    Future<void> pick(Key key, String query, String option) async {
      final field = find.descendant(
        of: find.byKey(key),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, query);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(of: find.byType(ListTile), matching: find.text(option))
            .last,
      );
      await tester.pumpAndSettle();
    }

    await pick(
      const ValueKey('transitaire-invoice-partner-false'),
      'bou',
      'BOUARE',
    );
    // Nouveau camion créé depuis la facture : rattaché au transporteur DIVERS.
    await tester.tap(
      find.byKey(const ValueKey('transitaire-invoice-new-truck')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-truck-plate')),
      'aa 647 bz',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-truck-driver')),
      'Mamadou',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-truck-phone')),
      '+223 74 01 96 88',
    );
    await tester.tap(find.byKey(const ValueKey('new-truck-save')));
    await tester.pumpAndSettle();
    final divers = (erpBackend as MemoryErpBackend).prestataires.singleWhere(
      (p) => p.entreprise == 'TRANSPORTEUR DIVERS',
    );
    expect(divers.type, 'Transporteur');
    expect(divers.vehicules.single.plaque, 'AA 647 BZ');
    expect(divers.vehicules.single.telephone, '+223 74 01 96 88');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('transitaire-invoice-driver-phone')),
          )
          .controller!
          .text,
      '+223 74 01 96 88',
    );
    expect(
      find.byKey(ValueKey('transitaire-invoice-carrier-${divers.id}')),
      findsOneWidget,
    );

    // La plaque saisie remplit le transporteur et le téléphone du chauffeur.
    await pick(
      ValueKey('transitaire-invoice-plate-${divers.vehicules.single.id}'),
      'ab 12',
      'AB 1234 MD • Moussa • SOSAF',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('transitaire-invoice-driver-phone')),
          )
          .controller!
          .text,
      '70000001',
    );
    expect(
      find.byKey(const ValueKey('transitaire-invoice-carrier-transp-1')),
      findsOneWidget,
    );

    // Un clic sur une ligne l'ajoute au détail ; « Tout ajouter » prend le reste.
    final available = find.byKey(const ValueKey('available-containers-grid'));
    await tester.tap(
      find.descendant(of: available, matching: find.text('MSKU0000001')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2. Détail de la facture (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('available-add-all')));
    await tester.pumpAndSettle();
    expect(find.text('2. Détail de la facture (3)'), findsOneWidget);
    expect(find.text('1. Liste des BL disponibles (0)'), findsOneWidget);

    // Changer de camion en en-tête s'applique à tous les conteneurs.
    await pick(
      const ValueKey('transitaire-invoice-plate-veh-1'),
      'bf',
      'BF 5295 MD • Issa • STL',
    );
    Future<void> type(String key, String value) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }

    // Péage, total transporteur et avance répartis sur les trois conteneurs.
    await type('transitaire-invoice-global-toll', '21000');
    await type('transitaire-invoice-truck-total', '300000');
    await type('transitaire-invoice-truck-advance', '90000');
    await tester.tap(find.byKey(const ValueKey('tab-details')));
    await tester.pumpAndSettle();
    String cellText(String key) => tester
        .widget<TextFormField>(find.byKey(ValueKey(key)))
        .controller!
        .text;
    for (var i = 0; i < 3; i++) {
      expect(cellText('line-$i-toll'), '7000');
      expect(cellText('line-$i-transport'), '100000');
      expect(cellText('line-$i-advance'), '30000');
      expect(
        tester.widget<Text>(find.byKey(ValueKey('line-$i-truck'))).data,
        'STL • BF 5295 MD',
      );
    }
    await type('line-0-transit', '45000');
    await type('line-1-transit', '50000');
    await type('line-2-transit', '30000');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('transitaire-invoice-total')))
          .data!
          .replaceAll(RegExp(r'\D'), ''),
      '236000',
    );
    expect(find.textContaining('Avance camion (BF 5295 MD)'), findsOneWidget);
    final reference = tester
        .widget<TextFormField>(
          find.byKey(const ValueKey('transitaire-invoice-number')),
        )
        .controller!
        .text;
    expect(reference, startsWith('FAC-TRS-'));
    await tester.tap(
      find.byKey(const ValueKey('transitaire-invoice-validate')),
    );
    await tester.pumpAndSettle();

    final invoices = find.byKey(const ValueKey('transitaire-invoices-grid'));
    Finder inInvoices(Finder f) => find.descendant(of: invoices, matching: f);
    expect(inInvoices(find.text(reference)), findsOneWidget);
    expect(inInvoices(find.text('Non acquittée')), findsOneWidget);
    expect(inInvoices(find.text('BL-1, BL-2')), findsOneWidget);
    expect(
      find.text('1 facture(s) • 0 conteneur(s) à facturer'),
      findsOneWidget,
    );
    final saved = (erpBackend as MemoryErpBackend).facturesTransitaire.single;
    expect(saved.lignes.map((l) => l.plaque).toSet(), {'BF 5295 MD'});
    expect(saved.lignes.map((l) => l.transporteurId).toSet(), {'transp-2'});
    expect(saved.lignes[2].telephoneChauffeur, '+223 90 34 12');
    expect(saved.lignes.map((l) => l.fraisPeage), [7000, 7000, 7000]);
    expect(saved.lignes.map((l) => l.montantTransport), [
      100000,
      100000,
      100000,
    ]);
    expect(saved.lignes.first.avanceCamion, 30000);

    await tester.tap(inInvoices(find.text(reference)));
    await tester.pumpAndSettle();
    final lines = find.byKey(const ValueKey('transitaire-lines-grid'));
    expect(
      find.descendant(of: lines, matching: find.text('TCLU0000003')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lines, matching: find.text('STL')),
      findsNWidgets(3),
    );

    // Même camion, même date : un seul voyage, les BL des deux dossiers se suivent.
    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voyages').last);
    await tester.pumpAndSettle();
    expect(find.text('Nbre de voyages : 1'), findsOneWidget);
    final voyages = find.byKey(const ValueKey('voyages-grid'));
    Finder inVoyages(Finder f) => find.descendant(of: voyages, matching: f);
    expect(inVoyages(find.text('BF 5295 MD')), findsOneWidget);
    expect(inVoyages(find.text('STT-d1, STT-d2')), findsOneWidget);
    expect(inVoyages(find.text('BL-1')), findsNWidgets(2));
    expect(inVoyages(find.text('BL-2')), findsOneWidget);
    expect(inVoyages(find.text('TCLU0000003')), findsOneWidget);
    expect(inVoyages(find.text('Issa')), findsOneWidget);
    // Filtre de colonne : tout décocher masque le voyage, tout recocher le réaffiche.
    Future<void> toggleDossierFilter() async {
      await tester.tap(find.byKey(const ValueKey('grid-filter-1')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('STT-d1, STT-d2'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('(Tout sélectionner)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-filter-apply')));
      await tester.pumpAndSettle();
    }

    await toggleDossierFilter();
    expect(inVoyages(find.text('TCLU0000003')), findsNothing);
    await toggleDossierFilter();

    // Le responsable affecte le voyage à la Frontière ; l'agent saisit ses frais.
    await tester.tap(inVoyages(find.text('BF 5295 MD')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print("STEP assign");
    await tester.tap(find.byKey(const ValueKey('voyage-assign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-assign-Frontière')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-assign-save')));
    await tester.pumpAndSettle();
    final affectation =
        (erpBackend as MemoryErpBackend).affectationsVoyage.single;
    expect(affectation.module, 'Frontière');
    expect(affectation.plaque, 'BF 5295 MD');
    expect(affectation.dossiers, 'STT-d1, STT-d2');
    expect(find.text('Frontière en cours (1)'), findsOneWidget);
    expect(inVoyages(find.text('À saisir')), findsOneWidget);

    Future<void> openMenu(String module, String item) async {
      await tester.ensureVisible(find.byTooltip(module));
      await tester.tap(find.byTooltip(module));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    // Tableau de bord de la Frontière : un voyage à saisir.
    // ignore: avoid_print
    print("STEP 1 await openMenu('Frontière', 'Tableau de bord Frontière');");
    await openMenu('Frontière', 'Tableau de bord Frontière');
    expect(find.textContaining('nouveau voyage à saisir'), findsWidgets);
    // ignore: avoid_print
    print("STEP 2 await openMenu('Frontière', 'Agent Frontière');");
    await openMenu('Frontière', 'Agent Frontière');
    final border = find.byKey(const ValueKey('voyage-module-grid-Frontière'));
    expect(
      find.descendant(of: border, matching: find.text('À saisir')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: border, matching: find.text('Issa')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-fees-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voyage-fee-Client')), findsNothing);
    expect(find.byKey(const ValueKey('voyage-t1-pick')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('voyage-fee-Frais de passage')),
      '10000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('voyage-fee-TS Frontière')),
      '25000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-fees-save')));
    await tester.pumpAndSettle();
    expect(affectation.total, 35000);
    expect(affectation.estValide, isFalse);
    // Onglet « Saisis » : on valide, la saisie passe dans « Validés ».
    await tester.tap(find.byKey(const ValueKey('voyage-tab-saisis')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: border, matching: find.text('Issa')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-validate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-validate-confirm')));
    await tester.pumpAndSettle();
    expect(affectation.estValide, isTrue);
    await tester.tap(find.byKey(const ValueKey('voyage-tab-valides')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: border, matching: find.text('Validé')),
      findsOneWidget,
    );
    // Validée, la saisie ne se modifie plus.
    await tester.tap(find.descendant(of: border, matching: find.text('Issa')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ErpActionButton>(
            find.byKey(const ValueKey('voyage-fees-edit')),
          )
          .onPressed,
      isNull,
    );
    // Cocher les saisies validées puis créer la facture de l'agent.
    await tester.tap(find.byKey(const ValueKey('voyage-check-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-create-invoice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-invoice-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    final agentInvoice = (erpBackend as MemoryErpBackend).facturesAgent.single;
    expect(agentInvoice.montant, 35000);
    expect(agentInvoice.reference, startsWith('FAC-FRT-'));
    expect(affectation.factureId, agentInvoice.id);
    expect(
      find.descendant(of: border, matching: find.text('Facturé')),
      findsOneWidget,
    );

    // La Direction règle la facture ; elle apparaît « Payée ».
    // ignore: avoid_print
    print("STEP 3 await openMenu('Frontière', 'Factures Frontière');");
    await openMenu('Frontière', 'Factures Frontière');
    final agentInvoices = find.byKey(
      const ValueKey('agent-invoices-grid-Frontière'),
    );
    await tester.tap(
      find.descendant(
        of: agentInvoices,
        matching: find.text(agentInvoice.reference),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('agent-payment-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-payment-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-save')));
    await tester.pumpAndSettle();
    expect(agentInvoice.estPayee, isTrue);
    expect(
      find.descendant(of: agentInvoices, matching: find.text('Payée')),
      findsOneWidget,
    );
    // ignore: avoid_print
    print("STEP 4 await openMenu('Frontière', 'Tableau de bord Frontière');");
    await openMenu('Frontière', 'Tableau de bord Frontière');
    expect(find.textContaining('payée le'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voyages').last);
    await tester.pumpAndSettle();
    expect(inVoyages(find.text('TCLU0000003')), findsOneWidget);
    // Frontière validée : le voyage passe à l'étape suivante, le Bureau DD s'affecte.
    await tester.tap(
      find.byKey(const ValueKey('voyage-stage-frontiereValidee')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Frontière validée (1)'), findsOneWidget);
    await tester.tap(inVoyages(find.text('BF 5295 MD')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-assign')));
    await tester.pumpAndSettle();
    // L'Enquête attend la validation du Bureau DD.
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('voyage-assign-Enquête')),
          )
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('voyage-assign-Bureau DD')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voyage-assign-save')));
    await tester.pumpAndSettle();
    expect(find.text('Bureau DD en cours (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voyage-stage-all')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Prestation'));
    await tester.tap(find.byTooltip('Prestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture Transitaire').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('payment-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-new')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('payment-amount')))
          .controller!
          .text,
      '236000',
    );
    await tester.tap(find.byKey(const ValueKey('payment-save')));
    await tester.pumpAndSettle();
    expect(inInvoices(find.text('Acquittée')), findsOneWidget);
    final payments = find.byKey(const ValueKey('transitaire-payments-grid'));
    expect(
      find.descendant(
        of: payments,
        matching: find.text('CA • Caisse principale'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transitaire-invoice-edit')),
      -300,
      scrollable: find
          .ancestor(of: payments, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('transitaire-invoice-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Facture déjà réglée'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.descendant(of: payments, matching: find.text('Espèces')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: payments, matching: find.text('Espèces')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('payment-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(inInvoices(find.text('Non acquittée')), findsOneWidget);
    expect(saved.reglements, isEmpty);
  });

  testWidgets('Accounting pages: aged balance, payment modes and journals', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String daysAgo(int days) => DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.now().subtract(Duration(days: days)));
    final client = Client(
      id: 'client-b',
      nom: 'MAH KEITA',
      telephone: '',
      compteComptable: '411MAHKEIT',
    );
    TransitDossier invoiced(String id, int age, double amount) {
      final dossier = TransitDossier(
        id: id,
        numDossier: 'STT-$id',
        numBL: '',
        numLB: '',
        client: client,
        nbConteneurs: 0,
        dateDebut: daysAgo(age),
      );
      dossier.factureClient
        ..statut = 'Clôturée'
        ..montant = amount
        ..dateEmission = daysAgo(age);
      return dossier;
    }

    final old = invoiced('old', 60, 100000)
      ..operations.add(
        DossierOperation(
          type: DossierOperationType.clientPayment,
          titre: 'Acompte',
          montant: 30000,
          date: '${daysAgo(5)} 10:00',
        ),
      );
    final recent = invoiced('recent', 10, 50000);
    (erpBackend as MemoryErpBackend)
      ..clients.add(client)
      ..dossiers.addAll([old, recent])
      ..journaux.add(
        JournalCode(
          code: 'BQ',
          intitule: 'Banque BIM',
          type: 'Banque',
          compteTresorerie: '521000',
        ),
      );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    Future<void> open(String item) async {
      await tester.ensureVisible(find.byTooltip('Comptabilité'));
      await tester.tap(find.byTooltip('Comptabilité'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    // Balance âgée : 70 000 de plus de 46 jours (après acompte) + 50 000 à 1-15 j.
    await open('Balance Agées');
    final totalText = tester
        .widget<Text>(find.byKey(const ValueKey('aged-balance-total')))
        .data!;
    expect(totalText.replaceAll(RegExp(r'\D'), ''), '1200001');
    final grid = find.byKey(const ValueKey('aged-balance-grid'));
    Finder inGrid(Finder f) => find.descendant(of: grid, matching: f);
    expect(inGrid(find.text('411MAHKEIT')), findsOneWidget);
    expect(inGrid(find.textContaining(RegExp(r'^70\D000$'))), findsOneWidget);
    expect(inGrid(find.textContaining(RegExp(r'^50\D000$'))), findsOneWidget);

    // Modes de règlement dans le module des codes journaux.
    await open('Code journaux');
    await tester.tap(find.text('Modes de règlement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mode-intitule')),
      'virement bim',
    );
    await tester.tap(find.byKey(const ValueKey('mode-save')));
    await tester.pumpAndSettle();
    expect(find.text('VIREMENT BIM'), findsOneWidget);
    expect(
      (erpBackend as MemoryErpBackend).modesReglement.single.intitule,
      'VIREMENT BIM',
    );

    // Saisie des journaux : journaux du mois et mise à jour comptable.
    await open('Saisie des Journaux');
    expect(find.text('Saisie des journaux'), findsOneWidget);
    expect(find.textContaining('Banque BIM'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('accounting-update')));
    await tester.pumpAndSettle();
    expect(find.text('Mise à jour de la comptabilité'), findsOneWidget);
    expect(find.text('Factures de Ventes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accounting-run')));
    await tester.pumpAndSettle();
    expect(find.text('0 écriture(s) comptabilisée(s)'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
  });

  testWidgets('Clients share the general account; fee types get sub-accounts', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = erpBackend as MemoryErpBackend;
    backend.comptes.addAll([
      PlanAccount(
        id: 'g-411',
        code: '41100000',
        libelle: 'Clients',
        nature: 'Client',
        tiersId: 'ancien-client',
      ),
      PlanAccount(
        id: 'c-411-1',
        code: '41100001',
        libelle: 'MAH KEITA',
        nature: 'Client',
        tiersId: 'autre-client',
      ),
      PlanAccount(
        id: 'g-6588',
        code: '65880000',
        libelle: 'Autres charges diverses',
        nature: 'Charge',
      ),
    ]);
    final client = Client(id: 'client-c', nom: 'Client Caisse', telephone: '');
    final dossier = TransitDossier(
      id: 'dossier-c',
      numDossier: 'STT-CAISSE',
      numBL: '',
      numLB: '',
      client: client,
      nbConteneurs: 0,
      dateDebut: '09/10/2026',
    );
    dossier.operations.add(
      DossierOperation(
        type: DossierOperationType.clientPayment,
        titre: 'Encaissement',
        montant: 1500000,
        date: '${DateFormat('dd/MM/yyyy').format(DateTime.now())} 10:00',
        codeJournal: 'CA',
        modePaiement: 'Espèces',
      ),
    );
    backend
      ..clients.add(client)
      ..dossiers.add(dossier)
      ..journaux.add(
        JournalCode(
          code: 'CA',
          intitule: 'Caisse principale',
          type: 'Caisse',
          compteTresorerie: '57110001',
        ),
      );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    Future<void> open(String module, String item) async {
      await tester.ensureVisible(find.byTooltip(module));
      await tester.tap(find.byTooltip(module));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    // Fiche client : tous les clients partagent le compte général 41100000.
    await open('Transitaire', 'Clients');
    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pumpAndSettle();
    final picker = find.descendant(
      of: find.byKey(const ValueKey('client-account-picker')),
      matching: find.byType(TextFormField),
    );
    expect(
      tester.widget<TextFormField>(picker).controller!.text,
      '41100000 • Clients',
    );
    expect(find.byKey(const ValueKey('client-account-create')), findsNothing);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();

    // Type de frais : AMENDE devient le sous-compte 65880001.
    await open('Dépenses & Frais', 'Types de frais');
    await tester.enterText(
      find.byKey(const ValueKey('fee-type-label')),
      'amende',
    );
    // Compte facultatif : recherche dans le plan comptable.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('fee-type-account-0')),
        matching: find.byType(TextFormField),
      ),
      '6588',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text('65880000 — Autres charges diverses'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fee-type-subaccount')))
          .data,
      'Sous-compte : 65880001 (créé automatiquement)',
    );
    await tester.tap(find.byKey(const ValueKey('fee-type-save')));
    await tester.pumpAndSettle();
    final feeGrid = find.byKey(const ValueKey('fee-types-grid'));
    expect(
      find.descendant(of: feeGrid, matching: find.text('AMENDE')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: feeGrid, matching: find.text('65880001')),
      findsOneWidget,
    );
    expect(backend.typesFrais.single.compte, '65880001');

    // Paiement Frais : bon de caisse numéroté pour le camion d'un dossier.
    await open('Dépenses & Frais', 'Paiement Frais');
    final trucks = find.byKey(const ValueKey('fee-trucks-grid'));
    await tester.tap(
      find.descendant(of: trucks, matching: find.text('STT-CAISSE')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fee-voucher-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('voucher-line-0-amount')),
      '15000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voucher-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fermer').last);
    await tester.pumpAndSettle();
    final voucher = backend.bonsCaisse.single;
    expect(voucher.reference, 'BC-00001');
    expect(voucher.montant, 15000);
    expect(voucher.codeJournal, 'CA');
    expect(voucher.lignes.single.compte, '65880001');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fee-vouchers-grid')),
        matching: find.text('BC-00001'),
      ),
      findsOneWidget,
    );

    // Dépense administrative : motif et compte comptable obligatoires.
    await open('Dépenses & Frais', 'Dépenses administratives');
    await tester.tap(find.byKey(const ValueKey('admin-voucher-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-beneficiary-DG')));
    await tester.enterText(
      find.byKey(const ValueKey('admin-motif')),
      'Mission à Bamako',
    );
    await tester.enterText(find.byKey(const ValueKey('admin-amount')), '50000');
    await tester.tap(find.byKey(const ValueKey('admin-voucher-save')));
    await tester.pumpAndSettle();
    expect(backend.bonsCaisse, hasLength(1));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('admin-account-0')),
        matching: find.byType(TextFormField),
      ),
      '65880001',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('65880001 —'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-voucher-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fermer').last);
    await tester.pumpAndSettle();
    final admin = backend.bonsCaisse.last;
    expect(admin.reference, 'BC-00002');
    expect(admin.beneficiaire, 'DG');
    expect(admin.lignes.single.compte, '65880001');

    // Contrôle de caisse : compte général du journal et compte tiers.
    await open('Comptabilité', 'Control des Caisses');
    final cash = find.byKey(const ValueKey('cash-control-grid'));
    expect(
      find.descendant(of: cash, matching: find.text('57110001')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cash,
        matching: find.text('Règlement Client Caisse (Espèces)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Carriers keep their trucks and the trial balance opens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = erpBackend as MemoryErpBackend;
    backend.comptes.add(
      PlanAccount(
        id: 'g-401',
        code: '40100000',
        libelle: 'Fournisseurs',
        nature: 'Fournisseur',
      ),
    );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transporteurs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('carrier-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'SOSAF');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Téléphone'),
      '20 21 00 00',
    );
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const ValueKey('truck-add')));
      await tester.tap(find.byKey(const ValueKey('truck-add')));
      await tester.pumpAndSettle();
    }
    Future<void> type(String key, String value) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.enterText(find.byKey(ValueKey(key)), value);
    }

    await type('truck-plate-0', 'ab 1234 md');
    await type('truck-driver-0', 'Moussa');
    await type('truck-phone-0', '70000001');
    await type('truck-plate-1', 'AC 5678 MD');
    await type('truck-driver-1', 'Issa');
    // Le compte général fournisseur est proposé d'office.
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const ValueKey('provider-account-picker')),
              matching: find.byType(TextFormField),
            ),
          )
          .controller!
          .text,
      '40100000 • Fournisseurs',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final carrier = backend.prestataires.single;
    expect(carrier.type, 'Transporteur');
    expect(carrier.vehicules.map((v) => v.plaque), [
      'AB 1234 MD',
      'AC 5678 MD',
    ]);
    expect(carrier.vehicules.first.telephone, '70000001');
    final grid = find.byKey(const ValueKey('carriers-grid'));
    expect(
      find.descendant(of: grid, matching: find.text('AB 1234 MD, AC 5678 MD')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: grid, matching: find.text('SOSAF')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final trucks = find.byKey(const ValueKey('carrier-trucks-grid'));
    expect(
      find.descendant(of: trucks, matching: find.text('Moussa')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byTooltip('Comptabilité'));
    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balance des Comptes').last);
    await tester.pumpAndSettle();
    expect(find.text('Génération de la Balance Générale'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trial-balance-show')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trial-balance-grid')), findsOneWidget);
  });

  testWidgets('Carrier invoice collects the containers of a truck', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = Client(id: 'client-c', nom: 'Client Camion', telephone: '');
    final carrier = Prestataire(
      id: 'transp-1',
      entreprise: 'SOSAF',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
      vehicules: [
        Vehicule(
          id: 'veh-1',
          plaque: 'AB 1234 MD',
          chauffeur: 'Moussa',
          telephone: '70000001',
        ),
      ],
    );
    final dossier = TransitDossier(
      id: 'd1',
      numDossier: 'STT-CAMION',
      numBL: 'BL-9',
      numLB: '',
      client: client,
      nbConteneurs: 2,
      dateDebut: '09/10/2026',
    );
    FactureTransitaireLigne line(
      String container,
      double transport,
      double advance,
    ) => FactureTransitaireLigne(
      dossierId: 'd1',
      bl: 'BL-9',
      numeroConteneur: container,
      transporteurId: 'transp-1',
      plaque: 'AB 1234 MD',
      telephoneChauffeur: '70000001',
      fraisTransit: 10000,
      montantTransport: transport,
      avanceCamion: advance,
    );
    final backend = erpBackend as MemoryErpBackend;
    backend
      ..clients.add(client)
      ..prestataires.add(carrier)
      ..dossiers.add(dossier)
      ..journaux.add(
        JournalCode(
          code: 'CA',
          intitule: 'Caisse principale',
          type: 'Caisse',
          compteTresorerie: '571000',
        ),
      )
      ..facturesTransitaire.add(
        FactureTransitaire(
          id: 'ftr-1',
          numero: 1,
          reference: 'FAC-TRS-1026-0009',
          transitaireId: 'transit-x',
          dateEmission: '15/10/2026',
          lignes: [
            line('MSKU0000001', 300000, 100000),
            line('MSKU0000002', 200000, 0),
          ],
        ),
      );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Prestation'));
    await tester.tap(find.byTooltip('Prestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture Transporteur').last);
    await tester.pumpAndSettle();
    expect(
      find.text('0 facture(s) • 2 conteneur(s) transporté(s) à facturer'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('carrier-invoice-new')));
    await tester.pumpAndSettle();
    final partner = find.descendant(
      of: find.byKey(const ValueKey('carrier-invoice-partner-false')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(partner, 'sos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOSAF').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('carrier-invoice-plate-transp-1-null')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('AB 1234 MD • Moussa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('carrier-available-add-all')));
    await tester.pumpAndSettle();
    expect(find.text('2. Détail de la facture (2)'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('carrier-invoice-advance')),
          )
          .controller!
          .text,
      '100000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('carrier-invoice-net')))
          .data!
          .replaceAll(RegExp(r'\D'), ''),
      '400000',
    );
    await tester.tap(find.byKey(const ValueKey('carrier-invoice-validate')));
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey('carrier-invoices-grid'));
    Finder inGrid(Finder f) => find.descendant(of: grid, matching: f);
    expect(inGrid(find.text('AB 1234 MD')), findsOneWidget);
    expect(inGrid(find.text('MSKU0000002')), findsOneWidget);
    expect(inGrid(find.text('Non payée')), findsOneWidget);
    final saved = backend.facturesTransporteur.single;
    expect(saved.montant, 500000);
    expect(saved.avance, 100000);
    expect(saved.plaque, 'AB 1234 MD');

    await tester.tap(inGrid(find.text('AB 1234 MD')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // « Modifier » : fenêtre compacte, Total TTC saisi (prix convenu).
    await tester.tap(find.byKey(const ValueKey('carrier-invoice-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier la facture transporteur'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('quick-total')), '550000');
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    final edited = backend.facturesTransporteur.single;
    expect(edited.montant, 550000);
    expect(edited.lignes.length, 2);
    await tester.ensureVisible(
      find.byKey(const ValueKey('carrier-payment-new')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('carrier-payment-new')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('payment-amount')))
          .controller!
          .text,
      '450000',
    );
    await tester.tap(find.byKey(const ValueKey('payment-save')));
    await tester.pumpAndSettle();
    expect(inGrid(find.text('Payée')), findsOneWidget);
    expect(edited.reliquat, 0);
  });

  test('Dossier balances keep the client and provider accounts separate', () {
    final client = Client(id: 'client-1', nom: 'Client test', telephone: '');
    final provider = Prestataire(
      id: 'provider-1',
      entreprise: 'Transport test',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
    );
    final dossier = TransitDossier(
      id: 'dossier-1',
      numDossier: 'STT-TEST',
      numBL: 'BL-1',
      numLB: '',
      client: client,
      prestataire: provider,
      nbConteneurs: 1,
      dateDebut: '09/10/2026',
    );
    expect(dossier.factureClient.statut, 'Brouillon');
    expect(dossier.facturePrestataire.statut, 'Brouillon');
    dossier.factureClient
      ..montant = 100000
      ..statut = 'Clôturée';
    dossier.factureTransporteur
      ..montant = 60000
      ..statut = 'Clôturée';
    dossier.operations.addAll([
      DossierOperation(
        type: DossierOperationType.clientPayment,
        titre: 'Règlement client',
        montant: 100000,
        date: '09/10/2026',
      ),
      DossierOperation(
        type: DossierOperationType.providerAdvance,
        titre: 'Avance',
        montant: 20000,
        date: '09/10/2026',
      ),
      DossierOperation(
        type: DossierOperationType.providerPayment,
        titre: 'Paiement complémentaire',
        montant: 30000,
        date: '09/10/2026',
      ),
    ]);

    expect(dossier.soldeClient, 0);
    expect(dossier.soldePrestataire, 10000);
    expect(dossier.peutCloturer, isFalse);

    dossier.operations.add(
      DossierOperation(
        type: DossierOperationType.providerPayment,
        titre: 'Solde final',
        montant: 10000,
        date: '09/10/2026',
      ),
    );
    expect(dossier.soldePrestataire, 0);
    expect(dossier.peutCloturer, isTrue);
  });

  testWidgets('Searchable provider selector filters the saved providers', (
    WidgetTester tester,
  ) async {
    final providers = [
      Prestataire(
        id: 'provider-dakar',
        entreprise: 'Transport Dakar',
        type: 'Transporteur',
        pays: 'Sénégal',
        villePort: 'Dakar',
        contact: '',
        telephone: '',
        email: '',
        services: '',
      ),
      Prestataire(
        id: 'provider-bamako',
        entreprise: 'Camions Bamako',
        type: 'Transporteur',
        pays: 'Mali',
        villePort: 'Bamako',
        contact: '',
        telephone: '',
        email: '',
        services: '',
      ),
    ];
    Prestataire? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: SearchableDropdownFormField<Prestataire>(
              key: const ValueKey('test-provider-search'),
              options: providers,
              value: null,
              label: 'Prestataire affecté',
              emptyText: 'Aucun prestataire',
              displayString: (provider) => provider.entreprise,
              onChanged: (provider) => selected = provider,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('test-provider-search')),
        matching: find.byType(TextFormField),
      ),
      'dakar',
    );
    await tester.pumpAndSettle();

    expect(find.text('Transport Dakar'), findsOneWidget);
    expect(find.text('Camions Bamako'), findsNothing);
    await tester.tap(find.text('Transport Dakar').last);
    await tester.pumpAndSettle();
    expect(selected?.id, 'provider-dakar');
  });

  testWidgets(
    'Cash desks: collect an invoice, pay a voucher and close the day',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = erpBackend as MemoryErpBackend;
      final client = Client(
        id: 'client-k',
        nom: 'Client Comptoir',
        telephone: '',
        compteComptable: '41100009',
      );
      final dossier = TransitDossier(
        id: 'dossier-k',
        numDossier: 'STT-K1',
        numBL: 'BL-K1',
        numLB: '',
        client: client,
        nbConteneurs: 0,
        dateDebut: '09/10/2026',
        typeMarchandise: 'Riz',
      );
      dossier.factureClient
        ..reference = 'FAC-K1'
        ..statut = 'Clôturée'
        ..montant = 500000
        ..dateEmission = '20/10/2026';
      backend
        ..clients.add(client)
        ..dossiers.add(dossier)
        ..journaux.addAll([
          JournalCode(
            code: 'CA',
            intitule: 'Caisse principale',
            type: 'Caisse',
            compteTresorerie: '57110001',
          ),
          JournalCode(
            code: 'CD',
            intitule: 'Caisse dépenses',
            type: 'Caisse',
            compteTresorerie: '57110002',
          ),
        ])
        ..caisseParametres.principale = 'CA'
        ..caisseParametres.depenses = 'CD'
        ..bonsCaisse.add(
          BonCaisse(
            id: 'bon-k',
            numero: 1,
            categorie: BonCaisse.depenseAdministrative,
            date: '20/10/2026',
            beneficiaire: 'DG',
            motif: 'Mission Kayes',
            lignes: [
              BonCaisseLigne(
                libelle: 'Mission',
                compte: '63800000',
                montant: 10000,
              ),
            ],
          ),
        );

      await tester.pumpWidget(const TransitTrackerApp());
      await tester.enterText(find.byType(TextField).at(0), 'admin');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.text('SE CONNECTER'));
      await tester.pumpAndSettle();

      Future<void> open(String item) async {
        await tester.ensureVisible(find.byTooltip('Caisse'));
        await tester.tap(find.byTooltip('Caisse'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
      }

      // Caisse principale : la facture non soldée, pointée en « Commencement ».
      await open('Caisse Encaissement');
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('impayes-grid')),
          matching: find.text('FAC-K1'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('encaisser')));
      await tester.pumpAndSettle();
      // « Non payé » par défaut : rien ne peut être validé.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('encaissement-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('encaissement-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencement (paiement partiel)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('encaissement-amount')),
        '200000',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('encaissement-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer').last);
      await tester.pumpAndSettle();
      final recu = backend.caisseMouvements.single;
      expect(recu.recu, 'RC-00001');
      expect(recu.statutReglement, statutCommencement);
      expect(dossier.soldeClient, 300000);

      // Recherche du client : ses totaux apparaissent, et reviennent à zéro.
      final totaux = find.byKey(const ValueKey('impayes-totaux'));
      await tester.enterText(
        find.byKey(const ValueKey('impayes-search')),
        'Comptoir',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: totaux,
          matching: find.text('${formatCurrency(300000)} F'),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('impayes-search')), '');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: totaux, matching: find.text('0 F')),
        findsNWidgets(3),
      );

      // Approvisionnement de la caisse des dépenses.
      await tester.tap(find.byKey(const ValueKey('caisse-appro')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('virement-amount')),
        '50000',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('virement-save')));
      await tester.pumpAndSettle();

      // Caisse des dépenses : réception, puis paiement du bon par son numéro.
      await open('Caisse Dépenses');
      await tester.tap(find.byKey(const ValueKey('caisse-reception-depenses')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réceptionner').last);
      await tester.pumpAndSettle();
      expect(soldeCaisse(caisseDepenses, backend.caisseMouvements), 50000);
      await tester.enterText(
        find.byKey(const ValueKey('bon-search')),
        'BC-00001',
      );
      await tester.tap(find.byKey(const ValueKey('bon-search-go')));
      await tester.pumpAndSettle();
      expect(find.text('Mission Kayes', findRichText: true), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('bon-pay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bon-pay-confirm')));
      await tester.pumpAndSettle();
      expect(
        backend.caisseMouvements.where((m) => m.bonId == 'bon-k'),
        hasLength(1),
      );
      expect(soldeCaisse(caisseDepenses, backend.caisseMouvements), 40000);

      // Relevé de caisse principale du jour, puis clôture.
      await open('Relevé de Caisse');
      final releve = find.byKey(const ValueKey('releve-grid'));
      expect(
        find.descendant(of: releve, matching: find.text('RC-00001')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: releve, matching: find.text('TOTAUX DE CAISSE')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('caisse-cloture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('caisse-cloture-confirm')));
      await tester.pumpAndSettle();
      final cloture = backend.caisseClotures.single;
      expect(cloture.caisse, caissePrincipale);
      expect(cloture.solde, 150000);
      expect(find.byKey(const ValueKey('caisse-cloture')), findsNothing);

      // L'administrateur déclôture une caisse clôturée par erreur.
      await tester.tap(find.byKey(const ValueKey('caisse-decloture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('caisse-decloture-confirm')));
      await tester.pumpAndSettle();
      expect(backend.caisseClotures, isEmpty);
      expect(find.byKey(const ValueKey('caisse-cloture')), findsOneWidget);

      // Le comptable impute l'encaissement pointé par la caissière.
      await tester.ensureVisible(find.byTooltip('Recouvrement'));
      await tester.tap(find.byTooltip('Recouvrement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Règlement').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saisie des Règlements Clients'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reglement-soldes-grid')),
          matching: find.text('Client Comptoir'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reglement-a-imputer')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('imputer-${recu.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('echeances-valider')));
      await tester.pumpAndSettle();
      expect(recu.estImpute, isTrue);
      expect(dossier.operations.single.id, '${recu.id}-i1');
      expect(find.byKey(const ValueKey('reglement-a-imputer')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('total-solde'))).data,
        formatCurrency(300000),
      );
    },
  );
}
