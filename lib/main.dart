import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'erp_backend.dart';
import 'file_saver.dart';
import 'models.dart';

export 'erp_backend.dart' show ErpBackend, MemoryErpBackend, erpBackend;
export 'models.dart';

part 'pages/balance_comptes_page.dart';
part 'pages/caisse_page.dart';
part 'pages/comptabilite_pages.dart';
part 'pages/dossier_dialogs.dart';
part 'pages/depenses_frais_page.dart';
part 'pages/dossiers_page.dart';
part 'pages/facture_transitaire_page.dart';
part 'pages/facture_transporteur_page.dart';
part 'pages/frais_caisse_pages.dart';
part 'pages/reglements_page.dart';
part 'pages/transporteurs_page.dart';
part 'pages/voyage_modules_page.dart';
part 'pages/voyages_page.dart';
part 'widgets/erp_documents.dart';
part 'widgets/dossier_report.dart';
part 'widgets/erp_grid.dart';
part 'widgets/tiers_accounts.dart';
part 'widgets/user_photo.dart';

// Fonction globale pour formater les montants
String formatCurrency(double amount) {
  return NumberFormat('#,###', 'fr_FR').format(amount).replaceAll(',', ' ');
}

String? _amountValidator(String? value) {
  final amount = double.tryParse(
    (value ?? '').trim().replaceAll(' ', '').replaceAll(',', '.'),
  );
  if (amount == null || amount < 0) {
    return 'Saisissez un solde égal ou supérieur à zéro';
  }
  return null;
}

String _normalizeUniqueValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

Future<void> _showDuplicateAlert(BuildContext context, String subject) async {
  await _showInfoAlert(
    context,
    title: 'Doublon détecté',
    message: '$subject existe déjà. Vérifiez les informations saisies.',
  );
}

// Enregistre via l'API ; en cas d'échec, affiche la raison et renvoie false.
Future<bool> _persist(
  BuildContext context,
  Future<void> Function() save,
) async {
  try {
    await save();
    return true;
  } on ErpBackendException catch (error) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Enregistrement impossible',
        message: error.message,
      );
    }
    return false;
  }
}

void _logout(BuildContext context) {
  erpBackend.logout();
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const LoginPage()),
  );
}

Future<void> _showInfoAlert(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Compris'),
        ),
      ],
    ),
  );
}

void main() {
  runApp(const TransitTrackerApp());
}

// Données de l'ERP, chargées depuis l'API à la connexion.
ErpUser? _currentUser;
final List<ErpUser> _erpUsers = [];
final List<Client> _clients = [];
final List<TransitDossier> _dossiers = [];
final List<Prestataire> _prestataires = [];
final List<PlanAccount> _planAccounts = [];
final List<JournalCode> _journalCodes = [];
final List<Voyage> _voyages = [];
final List<ModeReglement> _modesReglement = [];
final List<TypeFrais> _typesFrais = [];
final List<FactureTransitaire> _facturesTransitaire = [];
final List<FactureTransporteur> _facturesTransporteur = [];
final List<AffectationVoyage> _affectationsVoyage = [];
final List<AgentVoyage> _agentsVoyage = [];
final List<FactureAgent> _facturesAgent = [];
final List<BonCaisse> _bonsCaisse = [];
final List<CaisseMouvement> _caisseMouvements = [];
final List<CaisseCloture> _caisseClotures = [];
CaisseParametres _caisseParametres = CaisseParametres();

void _loadErpData(ErpData data) {
  _currentUser = data.user;
  _erpUsers
    ..clear()
    ..addAll(data.users);
  _clients
    ..clear()
    ..addAll(data.clients);
  _dossiers
    ..clear()
    ..addAll(data.dossiers);
  _prestataires
    ..clear()
    ..addAll(data.prestataires);
  _planAccounts
    ..clear()
    ..addAll(data.comptes);
  _journalCodes
    ..clear()
    ..addAll(data.journaux);
  _voyages
    ..clear()
    ..addAll(data.voyages);
  _modesReglement
    ..clear()
    ..addAll(data.modesReglement);
  _typesFrais
    ..clear()
    ..addAll(data.typesFrais);
  _facturesTransitaire
    ..clear()
    ..addAll(data.facturesTransitaire);
  _facturesTransporteur
    ..clear()
    ..addAll(data.facturesTransporteur);
  _affectationsVoyage
    ..clear()
    ..addAll(data.affectationsVoyage);
  _agentsVoyage
    ..clear()
    ..addAll(data.agentsVoyage);
  _facturesAgent
    ..clear()
    ..addAll(data.facturesAgent);
  _bonsCaisse
    ..clear()
    ..addAll(data.bonsCaisse);
  _caisseMouvements
    ..clear()
    ..addAll(data.caisseMouvements);
  _caisseClotures
    ..clear()
    ..addAll(data.caisseClotures);
  _caisseParametres = data.caisseParametres ?? CaisseParametres();
}

// Recharge toutes les données depuis le serveur (saisies des autres utilisateurs).
Future<bool> _actualiserDonnees(BuildContext context) async {
  try {
    _loadErpData(await erpBackend.reload());
  } on ErpBackendException catch (error) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Actualisation impossible',
        message: error.message,
      );
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          'Données actualisées à ${DateFormat('HH:mm').format(DateTime.now())}',
        ),
      ),
    );
  }
  return true;
}

// Bouton « Actualiser » : icône qui tourne pendant le rechargement.
class ErpRefreshButton extends StatefulWidget {
  final Color color;
  final VoidCallback? onRefreshed;

  const ErpRefreshButton({
    super.key,
    this.color = Colors.white,
    this.onRefreshed,
  });

  @override
  State<ErpRefreshButton> createState() => _ErpRefreshButtonState();
}

class _ErpRefreshButtonState extends State<ErpRefreshButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('erp-refresh'),
    tooltip: 'Actualiser',
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            final ok = await _actualiserDonnees(context);
            if (!mounted) return;
            setState(() => _busy = false);
            if (ok) widget.onRefreshed?.call();
          },
    icon: _busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: widget.color,
            ),
          )
        : Icon(Icons.sync_rounded, color: widget.color),
  );
}

// Rubriques masquées selon le rôle : chaque caissière ne voit que sa caisse.
bool _menuVisible(ErpMenuItem item) => switch (_currentUser?.role) {
  roleCaissierPrincipal => item.title != 'Caisse Dépenses',
  roleCaissierDepenses => item.title != 'Caisse Encaissement',
  _ => true,
};

class TransitTrackerApp extends StatelessWidget {
  const TransitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SYLLA TRANSIT & TRANSPORT',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LoginPage(),
    );
  }
}

// --- PAGE DE CONNEXION OPTIMISÉE WEB ---

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data = await erpBackend.login(_userCtrl.text, _passCtrl.text);
      if (!mounted) return;
      // Connexion réussie : le navigateur peut proposer d'enregistrer les identifiants.
      TextInput.finishAutofillContext();
      _loadErpData(data);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainNavigationPage(
            userDisplayName: data.user.name,
            userRole: data.user.role,
            authorizedModules: data.user.accessModules,
          ),
        ),
      );
    } on ErpBackendException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 15,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 50,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/logo.png',
                          height: 100,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.local_shipping_rounded,
                                size: 80,
                                color: Color(0xFF1A237E),
                              ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          "ESPACE GESTION",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Text(
                          "SYLLA TRANSIT & TRANSPORT",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 40),
                        // Le navigateur propose d'enregistrer puis remplit
                        // automatiquement l'identifiant et le mot de passe.
                        AutofillGroup(
                          child: Column(
                            children: [
                              TextField(
                                controller: _userCtrl,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: "Utilisateur",
                                  prefixIcon: const Icon(Icons.person_outline),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1A237E),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _login(),
                                decoration: InputDecoration(
                                  labelText: "Mot de passe",
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1A237E),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 35),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 5,
                            ),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Text(
                                    "SE CONNECTER",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _accountNatures = [
  'Aucun',
  'Salarié',
  'Résultat-Gestion',
  'Capitaux',
  'Stock',
  'Titre',
  'Résultat-Bilan',
  'Immobilisation',
  'Client',
  'Fournisseur',
  'Banque',
  'Caisse',
  'Charge',
  'Produit',
];

class SearchableDropdownFormField<T extends Object> extends StatefulWidget {
  final List<T> options;
  final T? value;
  final String label;
  final String emptyText;
  final bool required;
  final String Function(T) displayString;
  final ValueChanged<T?> onChanged;

  const SearchableDropdownFormField({
    super.key,
    required this.options,
    required this.value,
    required this.label,
    required this.emptyText,
    this.required = true,
    required this.displayString,
    required this.onChanged,
  });

  @override
  State<SearchableDropdownFormField<T>> createState() =>
      _SearchableDropdownFormFieldState<T>();
}

class _SearchableOption<T extends Object> {
  final T value;
  final String label;

  const _SearchableOption(this.value, this.label);
}

class _SearchableDropdownFormFieldState<T extends Object>
    extends State<SearchableDropdownFormField<T>> {
  T? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant SearchableDropdownFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _selectedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_SearchableOption<T>>(
      initialValue: TextEditingValue(
        text: widget.value == null ? '' : widget.displayString(widget.value!),
      ),
      displayStringForOption: (option) => option.label,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        final options = widget.options
            .map(
              (option) =>
                  _SearchableOption(option, widget.displayString(option)),
            )
            .toList();
        if (query.isEmpty) return options;
        return options.where(
          (option) => option.label.toLowerCase().contains(query),
        );
      },
      onSelected: (option) {
        setState(() => _selectedValue = option.value);
        widget.onChanged(option.value);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: (_) {
            return widget.required && _selectedValue == null
                ? 'Sélectionnez une valeur dans la liste'
                : null;
          },
          onChanged: (text) {
            if (_selectedValue != null &&
                text != widget.displayString(_selectedValue as T)) {
              setState(() => _selectedValue = null);
              widget.onChanged(null);
            }
          },
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.options.isEmpty ? widget.emptyText : 'Rechercher…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Afficher la liste',
              onPressed: () {
                focusNode.requestFocus();
                controller.clear();
              },
              icon: const Icon(Icons.arrow_drop_down),
            ),
            border: const OutlineInputBorder(),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: options
                  .map(
                    (option) => ListTile(
                      title: Text(option.label),
                      onTap: () => onSelected(option),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class ErpMenuItem {
  final String title;
  final IconData icon;

  const ErpMenuItem(this.title, this.icon);
}

class ErpModule {
  final String title;
  final IconData icon;
  final List<ErpMenuItem> items;

  const ErpModule(this.title, this.icon, this.items);
}

// --- NAVIGATION PRINCIPALE ---

class MainNavigationPage extends StatefulWidget {
  final String userDisplayName;
  final String userRole;
  final Set<String> authorizedModules;

  const MainNavigationPage({
    super.key,
    this.userDisplayName = 'Administrateur',
    this.userRole = 'Administrateur',
    this.authorizedModules = const {
      'Gestion',
      'Prestation',
      'Recouvrement',
      'Transport',
      'Transitaire',
      'Comptabilité',
      'RH & Paie',
      'Frontière',
      'Bureau DD',
      'Enquête',
      'Dépenses & Frais',
      'Caisse',
    },
  });
  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Incrémenté à chaque actualisation : les onglets ouverts sont reconstruits.
  int _dataVersion = 0;

  static const List<ErpModule> _modules = [
    ErpModule('Gestion', Icons.space_dashboard_rounded, [
      ErpMenuItem('Accueil', Icons.home_rounded),
      ErpMenuItem('Gestion utilisateur', Icons.manage_accounts_rounded),
      ErpMenuItem('Indicateur Performance (KPI)', Icons.insights_rounded),
    ]),
    ErpModule('Prestation', Icons.room_service_rounded, [
      ErpMenuItem('Facture Client', Icons.request_quote_rounded),
      ErpMenuItem('Facture Prestataire', Icons.receipt_long_rounded),
      ErpMenuItem('Facture Transitaire', Icons.directions_boat_rounded),
      ErpMenuItem('Facture Transporteur', Icons.local_shipping_rounded),
      ErpMenuItem('Espace Prestataire', Icons.business_center_rounded),
    ]),
    ErpModule('Recouvrement', Icons.price_check_rounded, [
      ErpMenuItem('Etat des Impayés', Icons.receipt_long_rounded),
      ErpMenuItem('Relance des Impayés', Icons.notifications_active_rounded),
      ErpMenuItem('Règlement', Icons.payments_rounded),
      ErpMenuItem(
        'Saisie des Règlements Transporteurs',
        Icons.local_shipping_rounded,
      ),
    ]),
    ErpModule('Transport', Icons.local_shipping_rounded, [
      ErpMenuItem('Dossier', Icons.folder_copy_rounded),
      ErpMenuItem('Gestion des dépenses', Icons.money_off_csred_rounded),
      ErpMenuItem('Gestion des Avances', Icons.account_balance_wallet_rounded),
      ErpMenuItem('Voyages', Icons.route_rounded),
      ErpMenuItem('Transporteurs', Icons.local_shipping_outlined),
      ErpMenuItem('Historique', Icons.history_rounded),
    ]),
    ErpModule('Frontière', Icons.signpost_rounded, [
      ErpMenuItem('Tableau de bord Frontière', Icons.space_dashboard_rounded),
      ErpMenuItem('Agent Frontière', Icons.signpost_rounded),
      ErpMenuItem('Factures Frontière', Icons.receipt_long_rounded),
    ]),
    ErpModule('Bureau DD', Icons.local_police_rounded, [
      ErpMenuItem('Tableau de bord DD', Icons.space_dashboard_rounded),
      ErpMenuItem('Bureau des Douanes (DD)', Icons.local_police_rounded),
      ErpMenuItem('Factures DD', Icons.receipt_long_rounded),
    ]),
    ErpModule('Enquête', Icons.manage_search_rounded, [
      ErpMenuItem('Tableau de bord Enquête', Icons.space_dashboard_rounded),
      ErpMenuItem('Enquêtes', Icons.manage_search_rounded),
      ErpMenuItem('Factures Enquête', Icons.receipt_long_rounded),
    ]),
    ErpModule('Transitaire', Icons.directions_boat_rounded, [
      ErpMenuItem('Gestion des Transitaires & Chargeurs', Icons.groups_rounded),
      ErpMenuItem('Clients', Icons.people_rounded),
    ]),
    ErpModule('Dépenses & Frais', Icons.local_gas_station_rounded, [
      ErpMenuItem('Paiement Frais', Icons.local_gas_station_rounded),
      ErpMenuItem(
        'Dépenses administratives',
        Icons.account_balance_wallet_rounded,
      ),
      ErpMenuItem('Types de frais', Icons.category_rounded),
    ]),
    ErpModule('Caisse', Icons.point_of_sale_rounded, [
      ErpMenuItem('Caisse Encaissement', Icons.savings_rounded),
      ErpMenuItem('Caisse Dépenses', Icons.payments_rounded),
      ErpMenuItem('Relevé de Caisse', Icons.receipt_long_rounded),
    ]),
    ErpModule('Comptabilité', Icons.account_balance_rounded, [
      ErpMenuItem('Balance des Comptes', Icons.balance_rounded),
      ErpMenuItem('Balance Agées', Icons.pending_actions_rounded),
      ErpMenuItem('Control des Caisses', Icons.point_of_sale_rounded),
      ErpMenuItem('Règlements', Icons.payments_rounded),
      ErpMenuItem('Interrogation et Lettrage', Icons.search_rounded),
      ErpMenuItem('Grand-Livre des Tiers', Icons.menu_book_rounded),
      ErpMenuItem('Saisie des Journaux', Icons.edit_note_rounded),
      ErpMenuItem('Code journaux', Icons.menu_book_rounded),
      ErpMenuItem('Plan Comptable', Icons.account_tree_rounded),
      ErpMenuItem('Rapprochement Bancaire', Icons.compare_arrows_rounded),
    ]),
    ErpModule('RH & Paie', Icons.badge_rounded, [
      ErpMenuItem('Espace RH & Paie', Icons.badge_rounded),
    ]),
  ];

  int _selectedModuleIndex = 0;
  String _selectedMenuTitle = 'Accueil';
  final List<({int moduleIndex, String title})> _openPages = [
    (moduleIndex: 0, title: 'Accueil'),
  ];

  List<int> get _visibleModuleIndexes => [
    for (var index = 0; index < _modules.length; index++)
      if (widget.authorizedModules.contains(_modules[index].title)) index,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.authorizedModules.contains('Gestion')) return;
    final visibleIndexes = _visibleModuleIndexes;
    if (visibleIndexes.isEmpty) return;
    _selectedModuleIndex = visibleIndexes.first;
    _selectedMenuTitle = _modules[_selectedModuleIndex].items
        .where(_menuVisible)
        .first
        .title;
    _openPages
      ..clear()
      ..add((moduleIndex: _selectedModuleIndex, title: _selectedMenuTitle));
  }

  Future<void> _changeMyPhoto() async {
    final user = _currentUser;
    if (user == null) return;
    final photo = await _pickProfilePhoto(context);
    if (photo == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveMyPhoto(photo))) return;
    setState(() {
      user.photo = photo;
      // La liste des utilisateurs (administrateur) affiche aussi la nouvelle photo.
      for (final entry in _erpUsers.where((u) => u.id == user.id)) {
        entry.photo = photo;
      }
    });
  }

  void _selectMenu(int moduleIndex, ErpMenuItem item) {
    if (!widget.authorizedModules.contains(_modules[moduleIndex].title)) return;
    setState(() {
      _selectedModuleIndex = moduleIndex;
      _selectedMenuTitle = item.title;
      if (!_openPages.any(
        (page) => page.moduleIndex == moduleIndex && page.title == item.title,
      )) {
        _openPages.add((moduleIndex: moduleIndex, title: item.title));
      }
    });
  }

  void _openDashboard() {
    if (!widget.authorizedModules.contains('Gestion')) return;
    setState(() {
      _selectedModuleIndex = 0;
      _selectedMenuTitle = 'Accueil';
      if (!_openPages.any((page) => page.title == 'Accueil')) {
        _openPages.insert(0, (moduleIndex: 0, title: 'Accueil'));
      }
    });
  }

  void _selectOpenPage(({int moduleIndex, String title}) page) {
    setState(() {
      _selectedModuleIndex = page.moduleIndex;
      _selectedMenuTitle = page.title;
    });
  }

  void _closeOpenPage(({int moduleIndex, String title}) page) {
    if (page.title == 'Accueil') return;
    setState(() {
      final index = _openPages.indexOf(page);
      _openPages.remove(page);
      if (_selectedModuleIndex == page.moduleIndex &&
          _selectedMenuTitle == page.title) {
        final next = _openPages[(index - 1).clamp(0, _openPages.length - 1)];
        _selectedModuleIndex = next.moduleIndex;
        _selectedMenuTitle = next.title;
      }
    });
  }

  Widget _buildPageTabs() => Container(
    height: 44,
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _openPages.map((page) {
          final selected =
              page.moduleIndex == _selectedModuleIndex &&
              page.title == _selectedMenuTitle;
          return InkWell(
            onTap: () => _selectOpenPage(page),
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14, right: 4),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE8EAF6) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: selected
                        ? const Color(0xFF1A237E)
                        : Colors.transparent,
                    width: 2,
                  ),
                  right: const BorderSide(color: Color(0xFFE7EAF0)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    page.title,
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: const Color(0xFF344054),
                    ),
                  ),
                  if (page.title != 'Accueil')
                    IconButton(
                      key: ValueKey(
                        'close-page-${page.moduleIndex}-${page.title}',
                      ),
                      tooltip: 'Fermer ${page.title}',
                      visualDensity: VisualDensity.compact,
                      iconSize: 17,
                      onPressed: () => _closeOpenPage(page),
                      icon: const Icon(Icons.close_rounded),
                    )
                  else
                    const SizedBox(width: 10),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );

  Widget _buildPageFor(({int moduleIndex, String title}) page) {
    final module = _modules[page.moduleIndex];
    switch (page.title) {
      case 'Accueil':
        if (!widget.authorizedModules.contains('Gestion')) {
          return const ModulePlaceholderPage(
            title: 'Accès non autorisé',
            icon: Icons.lock_outline_rounded,
            moduleTitle: 'Gestion',
          );
        }
        return HomePage(
          dossiers: _dossiers,
          clients: _clients,
          onSelectMenu: _selectMenu,
          availableModuleIndexes: _visibleModuleIndexes,
        );
      case 'Dossier':
        return DossiersPage(
          dossiers: _dossiers,
          clients: _clients,
          prestataires: _prestataires,
          journals: _journalCodes,
        );
      case 'Clients':
        return ClientsPage(clients: _clients, comptes: _planAccounts);
      case 'Espace Prestataire':
        return PrestatairesPage(
          prestataires: _prestataires,
          comptes: _planAccounts,
        );
      case 'Plan Comptable':
        return PlanComptablePage(
          comptes: _planAccounts,
          clients: _clients,
          prestataires: _prestataires,
          journals: _journalCodes,
        );
      case 'Code journaux':
        return JournauxEtModesPage(
          journals: _journalCodes,
          comptes: _planAccounts,
          modes: _modesReglement,
        );
      case 'Paiement Frais':
        return PaiementFraisPage();
      case 'Dépenses administratives':
        return DepensesAdministrativesPage();
      case 'Types de frais':
        return TypesFraisPage(types: _typesFrais, comptes: _planAccounts);
      case 'Balance des Comptes':
        return BalanceComptesPage(
          comptes: _planAccounts,
          journals: _journalCodes,
        );
      case 'Balance Agées':
        return BalanceAgeePage(clients: _clients, dossiers: _dossiers);
      case 'Saisie des Journaux':
        return SaisieJournauxPage(journals: _journalCodes);
      case 'Facture Client':
        return DossierInvoicesPage(
          dossiers: _dossiers,
          kind: DossierInvoiceKind.client,
          userDisplayName: widget.userDisplayName,
        );
      case 'Facture Prestataire':
        return DossierInvoicesPage(
          dossiers: _dossiers,
          kind: DossierInvoiceKind.provider,
          prestataires: _prestataires,
          userDisplayName: widget.userDisplayName,
        );
      case 'Facture Transitaire':
        return FactureTransitairePage(
          dossiers: _dossiers,
          prestataires: _prestataires,
          journals: _journalCodes,
          modes: _modesReglement,
          factures: _facturesTransitaire,
        );
      case 'Facture Transporteur':
        return FactureTransporteurPage(
          dossiers: _dossiers,
          prestataires: _prestataires,
          journals: _journalCodes,
          modes: _modesReglement,
          facturesTransitaire: _facturesTransitaire,
          factures: _facturesTransporteur,
        );
      case 'Transporteurs':
        return TransporteursPage(
          prestataires: _prestataires,
          comptes: _planAccounts,
        );
      case 'Tableau de bord Frontière':
        return VoyageModuleDashboard(module: 'Frontière');
      case 'Tableau de bord DD':
        return VoyageModuleDashboard(module: 'Bureau DD');
      case 'Tableau de bord Enquête':
        return VoyageModuleDashboard(module: 'Enquête');
      case 'Factures Frontière':
      case 'Factures DD':
      case 'Factures Enquête':
        return FacturesAgentPage(
          module: switch (page.title) {
            'Factures Frontière' => 'Frontière',
            'Factures DD' => 'Bureau DD',
            _ => 'Enquête',
          },
          journals: _journalCodes,
          modes: _modesReglement,
        );
      case 'Agent Frontière':
        return VoyageModulePage(module: 'Frontière', title: 'Agent Frontière');
      case 'Bureau des Douanes (DD)':
        return VoyageModulePage(
          module: 'Bureau DD',
          title: 'Bureau des Douanes (DD)',
        );
      case 'Enquêtes':
        return VoyageModulePage(module: 'Enquête', title: 'Enquêtes');
      case 'Voyages':
        return VoyagesPage(
          dossiers: _dossiers,
          voyages: _voyages,
          clients: _clients,
          prestataires: _prestataires,
          factures: _facturesTransitaire,
        );
      case 'Gestion utilisateur':
        return UserManagementPage(
          users: _erpUsers,
          moduleNames: _modules.map((module) => module.title).toList(),
          currentUserRole: widget.userRole,
        );
      case 'Etat des Impayés':
        return EtatImpayesPage();
      case 'Caisse Encaissement':
        return CaisseEncaissementPage();
      case 'Caisse Dépenses':
        return CaisseDepensesPage();
      case 'Relevé de Caisse':
        return ReleveCaissePage();
      case 'Control des Caisses':
        return CashControlPage(dossiers: _dossiers, journals: _journalCodes);
      case 'Règlement':
        return SettlementHubPage(dossiers: _dossiers, journals: _journalCodes);
      case 'Saisie des Règlements Transporteurs':
        return ReglementsTiersPage(
          kind: SettlementKind.carrier,
          embedded: true,
        );
      case 'Historique':
        return HistoryPage(dossiers: _dossiers);
      default:
        final item = module.items.firstWhere(
          (entry) => entry.title == page.title,
        );
        return ModulePlaceholderPage(
          title: item.title,
          icon: item.icon,
          moduleTitle: module.title,
        );
    }
  }

  Widget _buildTopBar(bool isCompact) {
    final openDossiers = _dossiers
        .where((dossier) => dossier.statut == 'Ouvert')
        .toList();
    // Un agent Frontière / Bureau DD / Enquête ne voit que ce qui le concerne.
    final agentOnly = _isVoyageAgentOnly;
    final agentVoyages = agentOnly
        ? _agentOpenVoyages()
        : const <AffectationVoyage>[];
    final dossierAlerts = agentOnly ? const <TransitDossier>[] : openDossiers;
    final voyageAlerts = [
      for (final module in fraisParModuleVoyage.keys)
        if (widget.authorizedModules.contains(module))
          ..._voyageNotifications(module),
    ];
    return Container(
      height: 64,
      color: const Color(0xFF18334F),
      child: Row(
        children: [
          InkWell(
            key: const ValueKey('dashboard-logo-button'),
            onTap: _openDashboard,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 54,
              height: 48,
              margin: const EdgeInsets.only(left: 10, right: 8),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                key: const ValueKey('header-stt-logo'),
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_shipping_rounded,
                  color: Color(0xFF18334F),
                ),
              ),
            ),
          ),
          if (isCompact)
            IconButton(
              tooltip: 'Ouvrir les modules',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
            ),
          if (!isCompact)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _visibleModuleIndexes.map((index) {
                    final module = _modules[index];
                    final selected = index == _selectedModuleIndex;
                    return PopupMenuButton<ErpMenuItem>(
                      tooltip: module.title,
                      onSelected: (item) => _selectMenu(index, item),
                      itemBuilder: (context) => module.items
                          .where(_menuVisible)
                          .map(
                            (item) => PopupMenuItem<ErpMenuItem>(
                              value: item,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 270,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 20,
                                      color: const Color(0xFF1A237E),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              module.title,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.88),
                                fontSize: 16,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white,
                              size: 21,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          if (isCompact) const Spacer(),
          ErpRefreshButton(onRefreshed: () => setState(() => _dataVersion++)),
          IconButton(
            tooltip: 'Alertes conteneurs',
            onPressed: () => agentOnly
                ? _showAgentVoyages(context)
                : _showContainerAlerts(openDossiers),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.public_rounded, color: Colors.white),
                if ((agentOnly ? agentVoyages.length : openDossiers.length) > 0)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: _HeaderBadge(
                      count: agentOnly
                          ? agentVoyages.length
                          : openDossiers.length,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Notifications',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
                if (dossierAlerts.length + voyageAlerts.length > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: _HeaderBadge(
                      count: dossierAlerts.length + voyageAlerts.length,
                    ),
                  ),
              ],
            ),
            itemBuilder: (context) =>
                dossierAlerts.isEmpty && voyageAlerts.isEmpty
                ? const [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text('Aucune notification pour le moment'),
                    ),
                  ]
                : [
                    // Voyages Frontière / Bureau DD / Enquête : saisies et factures.
                    for (final (text, icon, color) in voyageAlerts.take(8))
                      PopupMenuItem<String>(
                        enabled: false,
                        child: SizedBox(
                          width: 300,
                          child: Row(
                            children: [
                              Icon(icon, size: 18, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final dossier in dossierAlerts.take(5))
                      PopupMenuItem<String>(
                        enabled: false,
                        child: SizedBox(
                          width: 300,
                          child: Text(
                            'Dossier ${dossier.numDossier} à suivre • ${dossier.client.nom}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Profil utilisateur',
            onSelected: (value) {
              if (value == 'logout') _logout(context);
              if (value == 'photo') _changeMyPhoto();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ErpUserAvatar(
                    name: widget.userDisplayName,
                    photo: _currentUser?.photo,
                  ),
                  title: Text(widget.userDisplayName),
                  subtitle: Text(widget.userRole),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'photo',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(
                    _currentUser?.photo == null
                        ? 'Ajouter ma photo'
                        : 'Changer ma photo',
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Se déconnecter'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ErpUserAvatar(
                key: const ValueKey('header-user-avatar'),
                name: widget.userDisplayName,
                photo: _currentUser?.photo,
                radius: 17,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              color: const Color(0xFF18334F),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 54,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Modules ERP',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _visibleModuleIndexes.length,
                itemBuilder: (context, visibleIndex) {
                  final moduleIndex = _visibleModuleIndexes[visibleIndex];
                  final module = _modules[moduleIndex];
                  final isSelectedModule = moduleIndex == _selectedModuleIndex;
                  return ExpansionTile(
                    key: PageStorageKey<String>('module-${module.title}'),
                    initiallyExpanded: isSelectedModule,
                    leading: Icon(
                      module.icon,
                      color: isSelectedModule
                          ? const Color(0xFF1A237E)
                          : const Color(0xFF64748B),
                    ),
                    title: Text(
                      module.title,
                      style: TextStyle(
                        fontWeight: isSelectedModule
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    children: module.items
                        .where(_menuVisible)
                        .map(
                          (item) => ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 58,
                              right: 16,
                            ),
                            leading: Icon(item.icon, size: 19),
                            title: Text(item.title),
                            selected: _selectedMenuTitle == item.title,
                            onTap: () {
                              _selectMenu(moduleIndex, item);
                              Navigator.pop(context);
                            },
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContainerAlerts(List<TransitDossier> openDossiers) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.public_rounded, color: Color(0xFF1A237E)),
            SizedBox(width: 10),
            Expanded(child: Text('Suivi des conteneurs')),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: openDossiers.isEmpty
              ? const Text('Aucun dossier ouvert à surveiller.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${openDossiers.fold<int>(0, (sum, dossier) => sum + dossier.nbConteneurs)} conteneur(s) dans ${openDossiers.length} dossier(s) ouvert(s).',
                    ),
                    const SizedBox(height: 12),
                    ...openDossiers
                        .take(6)
                        .map(
                          (dossier) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.local_shipping_outlined,
                              color: Color(0xFF1A237E),
                            ),
                            title: Text('Dossier ${dossier.numDossier}'),
                            subtitle: Text(
                              '${dossier.client.nom} • ${dossier.nbConteneurs} conteneur(s)',
                            ),
                            trailing: const Chip(label: Text('Ouvert')),
                          ),
                        ),
                    const SizedBox(height: 8),
                    const Text(
                      'Les alertes d’arrivée nécessiteront une date d’arrivée prévue et une source de suivi.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1000;
        return Scaffold(
          key: _scaffoldKey,
          drawer: isCompact ? _buildModuleDrawer() : null,
          body: Column(
            children: [
              _buildTopBar(isCompact),
              if (_openPages.length > 1) _buildPageTabs(),
              Expanded(
                child: Container(
                  color: const Color(0xFFF8F9FD),
                  child: IndexedStack(
                    index: _openPages.indexWhere(
                      (page) =>
                          page.moduleIndex == _selectedModuleIndex &&
                          page.title == _selectedMenuTitle,
                    ),
                    children: _openPages
                        .map(
                          (page) => HeroMode(
                            enabled:
                                page.moduleIndex == _selectedModuleIndex &&
                                page.title == _selectedMenuTitle,
                            child: KeyedSubtree(
                              key: ValueKey(
                                'workspace-${page.moduleIndex}-${page.title}-$_dataVersion',
                              ),
                              child: _buildPageFor(page),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final int count;

  const _HeaderBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFE53935),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class UserManagementPage extends StatefulWidget {
  final List<ErpUser> users;
  final List<String> moduleNames;
  final String currentUserRole;

  const UserManagementPage({
    super.key,
    required this.users,
    required this.moduleNames,
    required this.currentUserRole,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (widget.currentUserRole != 'Administrateur') {
      return const ModulePlaceholderPage(
        title: 'Gestion utilisateur',
        icon: Icons.lock_outline,
        moduleTitle: 'Gestion',
      );
    }
    final users = widget.users
        .where(
          (user) => '${user.name} ${user.login} ${user.role}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Gestion du Personnel'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('user-search'),
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          hintText: 'Rechercher un membre…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      key: const ValueKey('add-user'),
                      onPressed: () => _editUser(),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Nouveau membre'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: users.isEmpty
                    ? const Center(child: Text('Aucun utilisateur enregistré.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return Card(
                            child: ListTile(
                              leading: ErpUserAvatar(
                                name: user.name,
                                photo: user.photo,
                              ),
                              title: Text(
                                user.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${user.login} • ${user.role} • ${user.accessModules.length} module(s) autorisé(s)',
                              ),
                              trailing: IconButton(
                                key: ValueKey('edit-user-${user.id}'),
                                tooltip: 'Modifier les accès',
                                onPressed: () => _editUser(user),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editUser([ErpUser? initial]) async {
    final result = await showDialog<ErpUser>(
      context: context,
      builder: (context) => _ErpUserFormDialog(
        users: widget.users,
        moduleNames: widget.moduleNames,
        initial: initial,
      ),
    );
    if (result == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveUser(result))) return;
    // Le mot de passe saisi est chiffré par le serveur : on ne le garde pas en mémoire.
    result
      ..password = ''
      ..photoModifiee = false;
    if (_currentUser?.id == result.id) _currentUser!.photo = result.photo;
    if (!mounted) return;
    setState(() {
      final index = widget.users.indexWhere((user) => user.id == result.id);
      if (index < 0) {
        widget.users.add(result);
      } else {
        widget.users[index] = result;
      }
    });
  }
}

class _ErpUserFormDialog extends StatefulWidget {
  final List<ErpUser> users;
  final List<String> moduleNames;
  final ErpUser? initial;

  const _ErpUserFormDialog({
    required this.users,
    required this.moduleNames,
    this.initial,
  });

  @override
  State<_ErpUserFormDialog> createState() => _ErpUserFormDialogState();
}

class _ErpUserFormDialogState extends State<_ErpUserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  late String _role;
  late Set<String> _access;
  String? _photo;
  bool _photoChanged = false;

  static const _minPasswordLength = 8;

  static const _roles = [
    'Administrateur',
    'Direction',
    'Gérant',
    'Comptable',
    'Gestionnaire',
    'Recouvreur',
    'Prestataire',
    'Transporteur',
    'Agent Frontière',
    'Agent Bureau DD',
    'Agent Enquête',
    roleCaissierPrincipal,
    roleCaissierDepenses,
  ];

  // Inclut un rôle enregistré qui ne serait plus dans la liste.
  List<String> get _roleOptions => [
    ..._roles,
    if (!_roles.contains(_role)) _role,
  ];

  @override
  void initState() {
    super.initState();
    final user = widget.initial;
    _role = user?.role ?? 'Gestionnaire';
    _access = user == null
        ? _defaultAccess(_role, widget.moduleNames)
        : user.accessModules.toSet();
    if (user != null) {
      _name.text = user.name;
      _login.text = user.login;
      _photo = user.photo;
    }
  }

  static Set<String> _defaultAccess(String role, List<String> modules) {
    switch (role) {
      case 'Administrateur':
      case 'Direction':
      case 'Gérant':
        return modules.toSet();
      case 'Recouvreur':
        return {'Recouvrement'};
      case 'Comptable':
        return {'Comptabilité', 'Recouvrement', 'Dépenses & Frais', 'Caisse'};
      case roleCaissierPrincipal:
      case roleCaissierDepenses:
        return {'Caisse'};
      case 'Prestataire':
        return {'Prestation'};
      case 'Transporteur':
        return {'Transport'};
      case 'Agent Frontière':
        return {'Frontière'};
      case 'Agent Bureau DD':
        return {'Bureau DD'};
      case 'Agent Enquête':
        return {'Enquête'};
      default:
        return {'Gestion', 'Transport'};
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Nouveau membre' : 'Modifier le membre',
    ),
    content: SizedBox(
      width: 540,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPhotoPicker(),
              const SizedBox(height: 16),
              _requiredField(_name, 'Nom complet'),
              _requiredField(_login, 'Identifiant'),
              TextFormField(
                key: const ValueKey('user-password'),
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.initial == null
                      ? 'Mot de passe'
                      : 'Nouveau mot de passe',
                  helperText: widget.initial == null
                      ? 'Au moins $_minPasswordLength caractères'
                      : 'Laissez vide pour conserver le mot de passe actuel',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (password.isEmpty) {
                    return widget.initial == null
                        ? 'Saisissez un mot de passe'
                        : null;
                  }
                  return password.length < _minPasswordLength
                      ? 'Au moins $_minPasswordLength caractères'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const ValueKey('user-role'),
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Rôle',
                  border: OutlineInputBorder(),
                ),
                items: _roleOptions
                    .map(
                      (role) =>
                          DropdownMenuItem(value: role, child: Text(role)),
                    )
                    .toList(),
                onChanged: (role) {
                  if (role == null) return;
                  setState(() {
                    _role = role;
                    _access = _defaultAccess(role, widget.moduleNames);
                  });
                },
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DROITS D’ACCÈS AUX MODULES',
                  style: TextStyle(
                    color: Color(0xFF607D8B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(),
              ...widget.moduleNames.map(
                (module) => CheckboxListTile(
                  key: ValueKey('access-$module'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(module),
                  value: _access.contains(module),
                  onChanged: (allowed) => setState(() {
                    if (allowed == true) {
                      _access.add(module);
                    } else {
                      _access.remove(module);
                    }
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );

  Widget _requiredField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ce champ est obligatoire'
              : null,
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final login = _login.text.trim();
    final duplicate = widget.users.any(
      (user) =>
          user.id != widget.initial?.id &&
          _normalizeUniqueValue(user.login) == _normalizeUniqueValue(login),
    );
    if (duplicate) {
      await _showDuplicateAlert(context, 'Cet identifiant utilisateur');
      return;
    }
    Navigator.pop(
      context,
      ErpUser(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        login: login,
        password: _password.text,
        role: _role,
        accessModules: _access,
        photo: _photo,
        photoModifiee: _photoChanged,
      ),
    );
  }

  Widget _buildPhotoPicker() => Row(
    children: [
      ErpUserAvatar(
        name: _name.text.isEmpty ? '?' : _name.text,
        photo: _photo,
        radius: 34,
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('user-photo-pick'),
              onPressed: () async {
                final photo = await _pickProfilePhoto(context);
                if (photo == null || !mounted) return;
                setState(() {
                  _photo = photo;
                  _photoChanged = true;
                });
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_photo == null ? 'Ajouter une photo' : 'Changer'),
            ),
            if (_photo != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _photo = null;
                  _photoChanged = true;
                }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Retirer'),
              ),
          ],
        ),
      ),
    ],
  );
}

class SettlementHubPage extends StatelessWidget {
  final List<TransitDossier> dossiers;
  final List<JournalCode> journals;

  const SettlementHubPage({
    super.key,
    required this.dossiers,
    required this.journals,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FD),
    appBar: AppBar(
      title: const Text('Gestion des règlements'),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1A237E),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            _settlementOption(
              context,
              title: 'Saisie des Règlements Clients',
              icon: Icons.person_add_alt_1_rounded,
              kind: SettlementKind.client,
            ),
            _settlementOption(
              context,
              title: 'Saisie des Règlements Fournisseurs',
              icon: Icons.business_center_rounded,
              kind: SettlementKind.supplier,
            ),
            _settlementOption(
              context,
              title: 'Saisie des Règlements Transitaires',
              icon: Icons.directions_boat_rounded,
              kind: SettlementKind.forwarder,
            ),
            _settlementOption(
              context,
              title: 'Saisie des Règlements Transporteurs',
              icon: Icons.local_shipping_rounded,
              kind: SettlementKind.carrier,
              key: const ValueKey('settlement-carriers'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _settlementOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required SettlementKind kind,
    Key? key,
  }) => Card(
    key: key,
    margin: const EdgeInsets.only(bottom: 14),
    elevation: 2,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: const Color(0xFFE9EEF5),
        child: Icon(icon, color: const Color(0xFF455A64)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReglementsTiersPage(kind: kind)),
      ),
    ),
  );
}

class _VoyageFormDialog extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final Voyage? initial;

  const _VoyageFormDialog({required this.dossiers, this.initial});

  @override
  State<_VoyageFormDialog> createState() => _VoyageFormDialogState();
}

class _VoyageFormDialogState extends State<_VoyageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _driver = TextEditingController();
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _depart = TextEditingController();
  final _arrival = TextEditingController();
  late TransitDossier _dossier;
  String _status = 'Planifié';

  @override
  void initState() {
    super.initState();
    _dossier = widget.dossiers.firstWhere(
      (item) => item.id == widget.initial?.dossierId,
      orElse: () => widget.dossiers.first,
    );
    final voyage = widget.initial;
    if (voyage == null) {
      _origin.text = _dossier.lieuMarchandise;
      _destination.text = _dossier.lieuLivraison;
      _depart.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
      _arrival.text = _dossier.dateArriveeBateau;
      return;
    }
    _plate.text = voyage.plaque;
    _driver.text = voyage.chauffeur;
    _origin.text = voyage.origine;
    _destination.text = voyage.destination;
    _depart.text = voyage.depart;
    _arrival.text = voyage.arriveePrevue;
    _status = voyage.statut;
  }

  @override
  void dispose() {
    _plate.dispose();
    _driver.dispose();
    _origin.dispose();
    _destination.dispose();
    _depart.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Nouveau voyage' : 'Modifier le voyage',
    ),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TransitDossier>(
                isExpanded: true,
                initialValue: _dossier,
                decoration: const InputDecoration(
                  labelText: 'Dossier',
                  border: OutlineInputBorder(),
                ),
                items: widget.dossiers
                    .map(
                      (dossier) => DropdownMenuItem(
                        value: dossier,
                        child: Text(
                          '${dossier.numDossier} • ${dossier.client.nom}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _dossier = value);
                },
              ),
              const SizedBox(height: 10),
              _field(_plate, 'Plaque du véhicule'),
              _field(_driver, 'Nom du chauffeur'),
              _field(_origin, 'Lieu de départ'),
              _field(_destination, 'Destination'),
              _field(_depart, 'Date de départ', isDate: true),
              _field(_arrival, 'Date d’arrivée prévue', isDate: true),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Statut du voyage',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Planifié', child: Text('Planifié')),
                  DropdownMenuItem(value: 'En cours', child: Text('En cours')),
                  DropdownMenuItem(value: 'Arrivé', child: Text('Arrivé')),
                  DropdownMenuItem(value: 'Annulé', child: Text('Annulé')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool isDate = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: isDate ? 'jj/mm/aaaa' : null,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'Ce champ est obligatoire';
        if (isDate && !_isValidFrenchDate(text)) {
          return 'Date invalide (format jj/mm/aaaa)';
        }
        return null;
      },
    ),
  );

  static bool _isValidFrenchDate(String value) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value);
    if (match == null) return false;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Voyage(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        dossierId: _dossier.id,
        plaque: _plate.text.trim(),
        chauffeur: _driver.text.trim(),
        origine: _origin.text.trim(),
        destination: _destination.text.trim(),
        depart: _depart.text.trim(),
        arriveePrevue: _arrival.text.trim(),
        statut: _status,
      ),
    );
  }
}

class ModulePlaceholderPage extends StatelessWidget {
  final String title;
  final String moduleTitle;
  final IconData icon;

  const ModulePlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.moduleTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFFE8EAF6),
                      child: Icon(
                        icon,
                        size: 36,
                        color: const Color(0xFF1A237E),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Module $moduleTitle',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Cet espace est prêt à recevoir ses fonctionnalités métier.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- TABLEAU DE BORD ---

class HomePage extends StatelessWidget {
  final List<TransitDossier> dossiers;
  final List<Client> clients;
  final void Function(int moduleIndex, ErpMenuItem item) onSelectMenu;
  final List<int> availableModuleIndexes;

  const HomePage({
    super.key,
    required this.dossiers,
    required this.clients,
    required this.onSelectMenu,
    required this.availableModuleIndexes,
  });

  @override
  Widget build(BuildContext context) {
    final totalExpenses = dossiers.fold<double>(
      0,
      (sum, dossier) => sum + dossier.totalDepenses,
    );
    final openDossiers = dossiers
        .where((dossier) => dossier.statut == 'Ouvert')
        .length;
    final totalContainers = dossiers.fold<int>(
      0,
      (sum, dossier) => sum + dossier.nbConteneurs,
    );
    final expensesByCategory = <String, double>{};
    for (final dossier in dossiers) {
      for (final expense in dossier.depenses) {
        expensesByCategory.update(
          expense.categorie,
          (amount) => amount + expense.montant,
          ifAbsent: () => expense.montant,
        );
      }
    }
    final expenseCategories = expensesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final horizontalPadding = compact ? 16.0 : 28.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final metricWidth = compact ? contentWidth : (contentWidth - 36) / 4;
        final panelWidth = compact ? contentWidth : (contentWidth - 16) / 2;
        return SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1384),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tableau de bord',
                              style: TextStyle(
                                color: const Color(0xFF172B4D),
                                fontSize: compact ? 24 : 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Vue d’ensemble de votre activité SYLLA TRANSIT',
                              style: TextStyle(
                                color: Colors.blueGrey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 17,
                                color: Color(0xFF1A237E),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                DateFormat('dd/MM/yyyy').format(DateTime.now()),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(compact ? 22 : 30),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF172B4D), Color(0xFF315D91)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF172B4D,
                          ).withValues(alpha: 0.16),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DÉPENSES ENREGISTRÉES',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${formatCurrency(totalExpenses)} FCFA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 27 : 38,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Cumul des frais saisis sur les dossiers de transit',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.trending_up_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _DashboardMetricCard(
                        width: metricWidth,
                        label: 'Dossiers ouverts',
                        value: '$openDossiers',
                        note: 'À suivre',
                        icon: Icons.folder_open_rounded,
                        color: const Color(0xFF3976C5),
                      ),
                      _DashboardMetricCard(
                        width: metricWidth,
                        label: 'Conteneurs',
                        value: '$totalContainers',
                        note: 'Tous les dossiers',
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFF8A5BC2),
                      ),
                      _DashboardMetricCard(
                        width: metricWidth,
                        label: 'Clients',
                        value: '${clients.length}',
                        note: 'Portefeuille',
                        icon: Icons.groups_rounded,
                        color: const Color(0xFF24A47A),
                      ),
                      _DashboardMetricCard(
                        width: metricWidth,
                        label: 'Dossiers gérés',
                        value: '${dossiers.length}',
                        note: 'Total enregistré',
                        icon: Icons.assignment_rounded,
                        color: const Color(0xFFE59A32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Activité opérationnelle',
                    style: TextStyle(
                      color: Color(0xFF172B4D),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: panelWidth,
                        child: _DashboardPanel(
                          title: 'Dépenses par catégorie',
                          subtitle: 'Répartition des frais saisis',
                          child: expenseCategories.isEmpty
                              ? const _DashboardEmpty(
                                  message:
                                      'Les catégories apparaîtront après la saisie des premiers frais.',
                                )
                              : Column(
                                  children: expenseCategories.take(5).map((
                                    entry,
                                  ) {
                                    final fraction = totalExpenses == 0
                                        ? 0.0
                                        : entry.value / totalExpenses;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  entry.key,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${formatCurrency(entry.value)} F',
                                                style: const TextStyle(
                                                  color: Color(0xFF526174),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 7),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: fraction.clamp(0.0, 1.0),
                                              minHeight: 8,
                                              backgroundColor: const Color(
                                                0xFFE9EEF5,
                                              ),
                                              color: const Color(0xFF3976C5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ),
                      SizedBox(
                        width: panelWidth,
                        child: _DashboardPanel(
                          title: 'Dossiers récents',
                          subtitle: 'Derniers dossiers enregistrés',
                          child: dossiers.isEmpty
                              ? const _DashboardEmpty(
                                  message:
                                      'Aucun dossier pour le moment. Les nouveaux dossiers apparaîtront ici.',
                                )
                              : Column(
                                  children: dossiers.reversed
                                      .take(4)
                                      .map(
                                        (dossier) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const CircleAvatar(
                                            backgroundColor: Color(0xFFEAF1FA),
                                            child: Icon(
                                              Icons.local_shipping_rounded,
                                              color: Color(0xFF1A237E),
                                              size: 20,
                                            ),
                                          ),
                                          title: Text(
                                            'Dossier ${dossier.numDossier}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${dossier.client.nom} • ${dossier.nbConteneurs} conteneur(s)',
                                          ),
                                          trailing: Text(
                                            '${formatCurrency(dossier.totalDepenses)} F',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Modules de gestion',
                    style: TextStyle(
                      color: Color(0xFF172B4D),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: availableModuleIndexes.map((moduleIndex) {
                      final module =
                          _MainNavigationPageState._modules[moduleIndex];
                      return SizedBox(
                        width: panelWidth,
                        child: _DashboardPanel(
                          title: module.title,
                          subtitle:
                              '${module.items.length} rubrique(s) disponible(s)',
                          leading: Icon(
                            module.icon,
                            color: const Color(0xFF1A237E),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: module.items
                                .map(
                                  (item) => ActionChip(
                                    avatar: Icon(item.icon, size: 16),
                                    label: Text(item.title),
                                    onPressed: () =>
                                        onSelectMenu(moduleIndex, item),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;

  const _DashboardMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF69788C),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF172B4D),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(
                    color: Color(0xFF8290A2),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;

  const _DashboardPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF172B4D),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8290A2),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          child,
        ],
      ),
    );
  }
}

class _DashboardEmpty extends StatelessWidget {
  final String message;

  const _DashboardEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF8290A2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF69788C),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlanComptablePage extends StatefulWidget {
  final List<PlanAccount> comptes;
  final List<Client> clients;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;

  const PlanComptablePage({
    super.key,
    required this.comptes,
    required this.clients,
    required this.prestataires,
    required this.journals,
  });

  @override
  State<PlanComptablePage> createState() => _PlanComptablePageState();
}

class _PlanComptablePageState extends State<PlanComptablePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.comptes.where((account) {
      final query = _query.trim().toLowerCase();
      return account.code.toLowerCase().contains(query) ||
          account.libelle.toLowerCase().contains(query) ||
          account.nature.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          'Plan Comptable',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Rechercher par code, libellé ou nature',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('Aucun compte comptable enregistré.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 90),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final account = filtered[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  account.code.length > 3
                                      ? account.code.substring(0, 3)
                                      : account.code,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              title: Text(
                                '${account.code} — ${account.libelle}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  'Nature : ${account.nature}',
                                  if (account.tiersId != null)
                                    'Compte tiers associé',
                                  if (account.assujettiTva)
                                    'Assujetti à la TVA',
                                  if (account.soldeInitial != 0)
                                    'Solde initial : ${formatCurrency(account.soldeInitial)} FCFA',
                                ].join(' • '),
                              ),
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                      'edit-account-${account.code}',
                                    ),
                                    tooltip: 'Modifier le compte',
                                    onPressed: () => _editAccount(account),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    key: ValueKey(
                                      'delete-account-${account.code}',
                                    ),
                                    tooltip: 'Supprimer le compte',
                                    onPressed: () => _deleteAccount(account),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan-account-add',
        onPressed: () => _openAccountForm(),
        icon: const Icon(Icons.add),
        label: const Text('NOUVEAU COMPTE'),
      ),
    );
  }

  Future<void> _openAccountForm([PlanAccount? initial]) async {
    final account = await showDialog<PlanAccount>(
      context: context,
      builder: (context) =>
          _PlanAccountFormDialog(accounts: widget.comptes, initial: initial),
    );
    if (account == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveAccount(account))) return;
    if (!mounted) return;
    setState(() {
      if (initial == null) {
        widget.comptes.add(account);
        return;
      }
      final index = widget.comptes.indexWhere((item) => item.id == initial.id);
      if (index < 0) return;
      final oldCode = widget.comptes[index].code;
      widget.comptes[index] = account;
      for (final client in widget.clients) {
        if (client.compteComptable == oldCode) {
          client.compteComptable = account.code;
        }
      }
      for (final provider in widget.prestataires) {
        if (provider.compteComptable == oldCode) {
          provider.compteComptable = account.code;
        }
      }
      for (final journal in widget.journals) {
        if (journal.compteTresorerie == oldCode) {
          journal.compteTresorerie = account.code;
        }
      }
    });
  }

  Future<void> _editAccount(PlanAccount account) => _openAccountForm(account);

  Future<void> _deleteAccount(PlanAccount account) async {
    final journalUsesAccount = widget.journals.any(
      (journal) => journal.compteTresorerie == account.code,
    );
    if (account.tiersId != null || journalUsesAccount) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Compte encore utilisé'),
          content: const Text(
            'Réaffectez d’abord ce compte au tiers ou au journal concerné avant de le supprimer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce compte ?'),
        content: Text('${account.code} — ${account.libelle} sera supprimé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _persist(context, () => erpBackend.deleteAccount(account))) {
      return;
    }
    if (!mounted) return;
    setState(() => widget.comptes.removeWhere((item) => item.id == account.id));
  }
}

class _PlanAccountFormDialog extends StatefulWidget {
  final List<PlanAccount> accounts;
  final PlanAccount? initial;

  const _PlanAccountFormDialog({required this.accounts, this.initial});

  @override
  State<_PlanAccountFormDialog> createState() => _PlanAccountFormDialogState();
}

class _PlanAccountFormDialogState extends State<_PlanAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _label = TextEditingController();
  late String _nature;
  PlanAccount? _general;

  // Comptes généraux auxquels rattacher un nouveau sous-compte.
  List<PlanAccount> get _generals =>
      widget.accounts.where((a) => isGeneralAccountCode(a.code)).toList()
        ..sort((a, b) => a.code.compareTo(b.code));

  void _attachTo(PlanAccount? general) => setState(() {
    _general = general;
    if (general == null) return;
    _code.text = nextSubAccountCode(
      general.code,
      widget.accounts.map((a) => a.code),
    );
    if (_accountNatures.contains(general.nature)) _nature = general.nature;
  });

  @override
  void initState() {
    super.initState();
    final account = widget.initial;
    if (account == null) {
      _nature = 'Charge';
    } else {
      _code.text = account.code;
      _label.text = account.libelle;
      _nature = account.nature;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nouveau compte' : 'Modifier le compte',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.initial == null && _generals.isNotEmpty) ...[
                DropdownButtonFormField<PlanAccount?>(
                  key: const ValueKey('plan-account-general'),
                  isExpanded: true,
                  initialValue: _general,
                  decoration: const InputDecoration(
                    labelText: 'Rattacher au compte général (facultatif)',
                    helperText:
                        'Le numéro du sous-compte suivant est proposé automatiquement',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<PlanAccount?>(
                      value: null,
                      child: Text('Aucun (saisie libre)'),
                    ),
                    for (final general in _generals)
                      DropdownMenuItem<PlanAccount?>(
                        value: general,
                        child: Text(
                          '${general.code} — ${general.libelle}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _attachTo,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const ValueKey('plan-account-code'),
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Le code est obligatoire';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('plan-account-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Libellé',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le libellé est obligatoire'
                    : null,
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: const ValueKey('plan-account-nature'),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('plan-account-nature-$_nature'),
                  initialValue: _nature,
                  onChanged: widget.initial?.tiersId != null
                      ? null
                      : (value) {
                          if (value != null) setState(() => _nature = value);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Nature',
                    border: OutlineInputBorder(),
                  ),
                  items: _accountNatures
                      .map(
                        (nature) => DropdownMenuItem(
                          value: nature,
                          child: Text(nature),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            widget.initial == null
                ? 'Enregistrer'
                : 'Enregistrer les modifications',
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _code.text.trim();
    final duplicate = widget.accounts.any(
      (account) =>
          account.id != widget.initial?.id &&
          _normalizeUniqueValue(account.code) == _normalizeUniqueValue(code),
    );
    if (duplicate) {
      await _showDuplicateAlert(context, 'Ce code de compte comptable');
      return;
    }
    Navigator.pop(
      context,
      PlanAccount(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        code: code,
        libelle: _label.text.trim(),
        nature: _nature,
        tiersId: widget.initial?.tiersId,
        soldeInitial: widget.initial?.soldeInitial ?? 0,
        assujettiTva: widget.initial?.assujettiTva ?? false,
      ),
    );
  }
}

// --- ESPACE PRESTATAIRES ---

class PrestatairesPage extends StatefulWidget {
  final List<Prestataire> prestataires;
  final List<PlanAccount> comptes;

  const PrestatairesPage({
    super.key,
    required this.prestataires,
    required this.comptes,
  });

  @override
  State<PrestatairesPage> createState() => _PrestatairesPageState();
}

class _PrestatairesPageState extends State<PrestatairesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.prestataires.where((prestataire) {
      final query = _query.toLowerCase().trim();
      return prestataire.entreprise.toLowerCase().contains(query) ||
          prestataire.villePort.toLowerCase().contains(query) ||
          prestataire.pays.toLowerCase().contains(query) ||
          prestataire.type.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          'Espace Prestataire',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.business_center_rounded,
                            color: Color(0xFF1A237E),
                            size: 30,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Répertoire de vos transporteurs, transitaires et partenaires locaux. Le portail prestataire pourra être activé lorsque les comptes utilisateurs et la base de données seront en place.',
                              style: TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText:
                            'Rechercher une société, une ville ou un pays...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.prestataires.length} prestataire(s) enregistré(s)',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.domain_add_rounded,
                                size: 54,
                                color: Color(0xFF9AA8B8),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.prestataires.isEmpty
                                    ? 'Aucun prestataire enregistré'
                                    : 'Aucun résultat pour « $_query »',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Ajoutez une société de transport, un transitaire ou un partenaire local.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final prestataire = filtered[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFFE8EDF4)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFEAF1FA),
                                child: Icon(
                                  Icons.business_rounded,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              title: Text(
                                prestataire.entreprise,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text(
                                  '${prestataire.type} • ${prestataire.villePort}, ${prestataire.pays}\n'
                                  '${prestataire.contact} • ${prestataire.telephone}\n'
                                  '${prestataire.services}\n'
                                  'Compte fournisseur : ${prestataire.compteComptable}',
                                  style: const TextStyle(height: 1.5),
                                ),
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                      'edit-provider-${prestataire.id}',
                                    ),
                                    tooltip: 'Modifier le prestataire',
                                    onPressed: () =>
                                        _openProviderForm(prestataire),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  const Tooltip(
                                    message: 'Portail à activer',
                                    child: Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF8492A6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'provider-add',
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('NOUVEAU PRESTATAIRE'),
        onPressed: () => _openProviderForm(),
      ),
    );
  }

  Future<void> _openProviderForm([Prestataire? initial]) async {
    final prestataire = await showDialog<Prestataire>(
      context: context,
      builder: (context) => _PrestataireFormDialog(
        prestataires: widget.prestataires,
        comptes: widget.comptes,
        initial: initial,
      ),
    );
    if (prestataire == null || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.savePrestataire(prestataire),
    )) {
      return;
    }
    _linkTiersAccount(
      widget.comptes,
      tiersId: prestataire.id,
      previousCode: initial?.compteComptable,
      newCode: prestataire.compteComptable,
    );
    if (mounted) {
      setState(() {
        final index = widget.prestataires.indexWhere(
          (item) => item.id == prestataire.id,
        );
        if (index < 0) {
          widget.prestataires.add(prestataire);
        } else {
          widget.prestataires[index] = prestataire;
        }
      });
    }
  }
}

class _VehicleDraft {
  final String id;
  final plaque = TextEditingController();
  final chauffeur = TextEditingController();
  final telephone = TextEditingController();

  _VehicleDraft([Vehicule? vehicule]) : id = vehicule?.id ?? newLocalId('veh') {
    plaque.text = vehicule?.plaque ?? '';
    chauffeur.text = vehicule?.chauffeur ?? '';
    telephone.text = vehicule?.telephone ?? '';
  }

  void dispose() {
    plaque.dispose();
    chauffeur.dispose();
    telephone.dispose();
  }
}

String _normalizePlate(String plate) =>
    plate.toUpperCase().replaceAll(RegExp(r'\s+'), '');

class _PrestataireFormDialog extends StatefulWidget {
  final List<Prestataire> prestataires;
  final List<PlanAccount> comptes;
  final Prestataire? initial;
  final String? defaultType;

  const _PrestataireFormDialog({
    required this.prestataires,
    required this.comptes,
    this.initial,
    this.defaultType,
  });

  @override
  State<_PrestataireFormDialog> createState() => _PrestataireFormDialogState();
}

class _PrestataireFormDialogState extends State<_PrestataireFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _entreprise = TextEditingController();
  final _pays = TextEditingController(text: 'Mali');
  final _villePort = TextEditingController(text: 'Bamako');
  final _contact = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _services = TextEditingController();
  final _adresse = TextEditingController();
  final _rccm = TextEditingController();
  final _vehicules = TextEditingController(text: '0');
  final _soldeInitial = TextEditingController(text: '0');
  final List<_VehicleDraft> _trucks = [];
  PlanAccount? _selectedAccount;
  late String _type;

  @override
  void initState() {
    super.initState();
    final provider = widget.initial;
    _type = provider?.type ?? widget.defaultType ?? 'Transporteur';
    _trucks.addAll(
      (provider?.vehicules ?? const <Vehicule>[]).map(_VehicleDraft.new),
    );
    if (provider == null) {
      _selectedAccount = _accountsForTiers(
        widget.comptes,
        nature: 'Fournisseur',
        classPrefix: '40',
      ).firstOrNull;
      return;
    }
    _entreprise.text = provider.entreprise;
    _pays.text = provider.pays;
    _villePort.text = provider.villePort;
    _contact.text = provider.contact;
    _telephone.text = provider.telephone;
    _email.text = provider.email;
    _services.text = provider.services;
    _adresse.text = provider.adresse;
    _rccm.text = provider.rccm;
    _vehicules.text = provider.nombreVehicules.toString();
    _soldeInitial.text = provider.soldeInitial.toString();
    for (final account in widget.comptes) {
      if (account.code == provider.compteComptable) {
        _selectedAccount = account;
        break;
      }
    }
  }

  @override
  void dispose() {
    _entreprise.dispose();
    _pays.dispose();
    _villePort.dispose();
    _contact.dispose();
    _telephone.dispose();
    _email.dispose();
    _services.dispose();
    _adresse.dispose();
    _rccm.dispose();
    _vehicules.dispose();
    for (final truck in _trucks) {
      truck.dispose();
    }
    _soldeInitial.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ce champ est obligatoire';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? 'Créer un prestataire'
            : 'Modifier le prestataire',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type de partenaire',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Transporteur',
                      child: Text('Transporteur'),
                    ),
                    DropdownMenuItem(
                      value: 'Transitaire',
                      child: Text('Transitaire'),
                    ),
                    DropdownMenuItem(
                      value: 'Chargeur',
                      child: Text('Chargeur'),
                    ),
                    DropdownMenuItem(
                      value: 'Partenaire local',
                      child: Text('Partenaire local'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 10),
                _formField(
                  _entreprise,
                  'Nom de l’entreprise ou de la société',
                  validator: _requiredValidator,
                ),
                _formField(_pays, 'Pays', validator: _requiredValidator),
                _formField(
                  _villePort,
                  'Ville / port (ex. Dakar, Abidjan, Bamako)',
                  validator: _requiredValidator,
                ),
                _formField(_contact, 'Nom du contact'),
                _formField(
                  _telephone,
                  'Téléphone',
                  keyboardType: TextInputType.phone,
                  validator: _requiredValidator,
                ),
                _formField(
                  _email,
                  'Adresse e-mail',
                  keyboardType: TextInputType.emailAddress,
                ),
                _formField(_adresse, 'Adresse', maxLines: 2),
                _formField(_rccm, 'RCCM'),
                if (_type == 'Transporteur') ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Icon(
                          Icons.local_shipping_rounded,
                          color: _gridAccent,
                          size: 20,
                        ),
                        Text(
                          'Camions du transporteur (${_trucks.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _gridText,
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('truck-add'),
                          onPressed: () =>
                              setState(() => _trucks.add(_VehicleDraft())),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Ajouter un camion'),
                        ),
                      ],
                    ),
                  ),
                  _EditableTable(
                    emptyText:
                        'Aucun camion. Ajoutez chaque plaque avec son chauffeur.',
                    columns: const [
                      ('Plaque', 150),
                      ('Chauffeur', 170),
                      ('Téléphone chauffeur', 160),
                      ('', 52),
                    ],
                    rows: [
                      for (final (i, truck) in _trucks.indexed)
                        [
                          TextFormField(
                            key: ValueKey('truck-plate-$i'),
                            controller: truck.plaque,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _cellDecoration(hint: 'AB 1234 MD'),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Plaque obligatoire'
                                : null,
                          ),
                          TextFormField(
                            key: ValueKey('truck-driver-$i'),
                            controller: truck.chauffeur,
                            decoration: _cellDecoration(hint: 'Nom'),
                          ),
                          TextFormField(
                            key: ValueKey('truck-phone-$i'),
                            controller: truck.telephone,
                            keyboardType: TextInputType.phone,
                            decoration: _cellDecoration(hint: '+223 …'),
                          ),
                          IconButton(
                            tooltip: 'Retirer ce camion',
                            onPressed: () =>
                                setState(() => _trucks.removeAt(i).dispose()),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _formField(
                  _soldeInitial,
                  'Solde initial fournisseur (FCFA)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _amountValidator,
                ),
                _formField(
                  _services,
                  'Services proposés (transport, transit, location...)',
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: const ValueKey('provider-account-picker'),
                  child: SearchableDropdownFormField<PlanAccount>(
                    key: ValueKey(
                      'provider-account-picker-${widget.comptes.length}',
                    ),
                    options: _accountsForTiers(
                      widget.comptes,
                      nature: 'Fournisseur',
                      classPrefix: '40',
                      currentCode: widget.initial?.compteComptable,
                    ),
                    value: _selectedAccount,
                    label: 'Compte comptable fournisseur *',
                    emptyText:
                        'Aucun compte fournisseur (401…) dans le plan comptable',
                    displayString: (account) =>
                        '${account.code} • ${account.libelle}',
                    onChanged: (account) =>
                        setState(() => _selectedAccount = account),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            widget.initial == null
                ? 'Enregistrer'
                : 'Enregistrer les modifications',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _formField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final account = _selectedAccount;
    if (account == null) {
      _showMessage('Sélectionnez un compte fournisseur existant.');
      return;
    }
    final name = _entreprise.text.trim();
    final rccm = _rccm.text.trim();
    final duplicate = widget.prestataires.any(
      (provider) =>
          provider.id != widget.initial?.id &&
          (_normalizeUniqueValue(provider.entreprise) ==
                  _normalizeUniqueValue(name) ||
              (rccm.isNotEmpty &&
                  _normalizeUniqueValue(provider.rccm) ==
                      _normalizeUniqueValue(rccm))),
    );
    if (duplicate) {
      await _showDuplicateAlert(context, 'Ce prestataire');
      return;
    }
    final id =
        widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final openingBalance = double.parse(
      _soldeInitial.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
    );
    final trucks = [
      for (final t in _trucks)
        if (t.plaque.text.trim().isNotEmpty)
          Vehicule(
            id: t.id,
            plaque: t.plaque.text.trim().toUpperCase(),
            chauffeur: t.chauffeur.text.trim(),
            telephone: t.telephone.text.trim(),
          ),
    ];
    final plates = trucks.map((t) => _normalizePlate(t.plaque)).toList();
    if (plates.toSet().length != plates.length) {
      _showMessage('Une même plaque est saisie deux fois.');
      return;
    }
    final owner = widget.prestataires
        .where(
          (p) =>
              p.id != widget.initial?.id &&
              p.vehicules.any(
                (v) => plates.contains(_normalizePlate(v.plaque)),
              ),
        )
        .firstOrNull;
    if (owner != null) {
      _showMessage('Une de ces plaques appartient déjà à ${owner.entreprise}.');
      return;
    }
    Navigator.pop(
      context,
      Prestataire(
        id: id,
        entreprise: _entreprise.text.trim(),
        type: _type,
        pays: _pays.text.trim(),
        villePort: _villePort.text.trim(),
        contact: _contact.text.trim().isEmpty
            ? 'Contact à définir'
            : _contact.text.trim(),
        telephone: _telephone.text.trim(),
        email: _email.text.trim(),
        services: _services.text.trim().isEmpty
            ? 'Services à préciser'
            : _services.text.trim(),
        adresse: _adresse.text.trim(),
        rccm: _rccm.text.trim(),
        nombreVehicules: _type == 'Transporteur'
            ? trucks.length
            : int.tryParse(_vehicules.text.trim()) ?? 0,
        vehicules: _type == 'Transporteur' ? trucks : const [],
        soldeInitial: openingBalance,
        compteComptable: account.code,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class JournalCodesPage extends StatefulWidget {
  final List<JournalCode> journals;
  final List<PlanAccount> comptes;

  const JournalCodesPage({
    super.key,
    required this.journals,
    required this.comptes,
  });

  @override
  State<JournalCodesPage> createState() => _JournalCodesPageState();
}

class _JournalCodesPageState extends State<JournalCodesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final journals = widget.journals.where((journal) {
      final text =
          '${journal.code} ${journal.intitule} ${journal.type} ${journal.compteTresorerie}'
              .toLowerCase();
      return text.contains(_query.toLowerCase());
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Codes journaux'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Rechercher un code, intitulé ou compte…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: journals.isEmpty
          ? const Center(
              child: Text('Aucun code journal. Ajoutez votre premier journal.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: journals.length,
              itemBuilder: (context, index) {
                final journal = journals[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.menu_book_rounded),
                    ),
                    title: Text(
                      '${journal.code} • ${journal.intitule}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Type : ${journal.type} • Compte de trésorerie : ${journal.compteTresorerie}',
                    ),
                    trailing: IconButton(
                      key: ValueKey('edit-journal-${journal.code}'),
                      tooltip: 'Modifier le code journal',
                      onPressed: () => _addJournal(journal),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'journal-add',
        onPressed: _addJournal,
        icon: const Icon(Icons.add),
        label: const Text('NOUVEAU JOURNAL'),
      ),
    );
  }

  Future<void> _addJournal([JournalCode? initial]) async {
    final journal = await showDialog<JournalCode>(
      context: context,
      builder: (context) => _JournalCodeFormDialog(
        comptes: widget.comptes,
        existingCodes: widget.journals.map((entry) => entry.code).toSet(),
        initial: initial,
      ),
    );
    if (journal == null || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.saveJournal(journal, previousCode: initial?.code),
    )) {
      return;
    }
    if (mounted) {
      setState(() {
        if (initial == null) {
          widget.journals.add(journal);
        } else {
          final index = widget.journals.indexWhere(
            (entry) => entry.code == initial.code,
          );
          if (index >= 0) widget.journals[index] = journal;
        }
      });
    }
  }
}

class _JournalCodeFormDialog extends StatefulWidget {
  final List<PlanAccount> comptes;
  final Set<String> existingCodes;
  final JournalCode? initial;

  const _JournalCodeFormDialog({
    required this.comptes,
    required this.existingCodes,
    this.initial,
  });

  @override
  State<_JournalCodeFormDialog> createState() => _JournalCodeFormDialogState();
}

class _JournalCodeFormDialogState extends State<_JournalCodeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _intitule = TextEditingController();
  late String _type;
  PlanAccount? _account;

  @override
  void initState() {
    super.initState();
    final journal = widget.initial;
    _type = journal?.type ?? 'Banque';
    if (journal == null) return;
    _code.text = journal.code;
    _intitule.text = journal.intitule;
    for (final account in widget.comptes) {
      if (account.code == journal.compteTresorerie) {
        _account = account;
        break;
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _intitule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null
          ? 'Créer un code journal'
          : 'Modifier le code journal',
    ),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('journal-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code journal *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final code = (value ?? '').trim().toUpperCase();
                  if (code.isEmpty) return 'Saisissez le code du journal';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('journal-intitule'),
                controller: _intitule,
                decoration: const InputDecoration(
                  labelText: 'Intitulé *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Saisissez l’intitulé du journal'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type de journal *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Achats', child: Text('Achats')),
                  DropdownMenuItem(value: 'Ventes', child: Text('Ventes')),
                  DropdownMenuItem(value: 'Banque', child: Text('Banque')),
                  DropdownMenuItem(value: 'Caisse', child: Text('Caisse')),
                  DropdownMenuItem(
                    value: 'Opérations diverses',
                    child: Text('Opérations diverses'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              SearchableDropdownFormField<PlanAccount>(
                key: const ValueKey('journal-account-picker'),
                options: widget.comptes
                    .where(
                      (account) =>
                          account.nature == 'Banque' ||
                          account.nature == 'Caisse',
                    )
                    .toList(),
                value: _account,
                label: 'Compte de trésorerie / contrepartie *',
                emptyText: 'Ajoutez d’abord un compte Banque ou Caisse',
                displayString: (account) =>
                    '${account.code} • ${account.libelle}',
                onChanged: (account) => setState(() => _account = account),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          _save();
        },
        child: Text(
          widget.initial == null
              ? 'Enregistrer'
              : 'Enregistrer les modifications',
        ),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _code.text.trim().toUpperCase();
    if (widget.existingCodes.any(
      (existing) =>
          _normalizeUniqueValue(existing) == _normalizeUniqueValue(code) &&
          existing != widget.initial?.code,
    )) {
      await _showDuplicateAlert(context, 'Ce code journal');
      return;
    }
    final account = _account;
    if (account == null) {
      await _showInfoAlert(
        context,
        title: 'Compte obligatoire',
        message:
            'Sélectionnez un compte de trésorerie ou de contrepartie dans le plan comptable.',
      );
      return;
    }
    Navigator.pop(
      context,
      JournalCode(
        code: code,
        intitule: _intitule.text.trim(),
        type: _type,
        compteTresorerie: account.code,
      ),
    );
  }
}

class DossierInvoicesPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final DossierInvoiceKind kind;
  final List<Prestataire> prestataires;
  final String userDisplayName;

  const DossierInvoicesPage({
    super.key,
    required this.dossiers,
    required this.kind,
    this.prestataires = const [],
    this.userDisplayName = 'Administrateur',
  });

  @override
  State<DossierInvoicesPage> createState() => _DossierInvoicesPageState();
}

class _DossierInvoicesPageState extends State<DossierInvoicesPage> {
  String _query = '';
  bool get _isClient => widget.kind == DossierInvoiceKind.client;
  bool get _isTransitaire => widget.kind == DossierInvoiceKind.forwarder;
  bool get _isTransporteur => widget.kind == DossierInvoiceKind.carrier;
  String get _title => switch (widget.kind) {
    DossierInvoiceKind.client => 'Facture Client',
    DossierInvoiceKind.provider => 'Facture Prestataire',
    DossierInvoiceKind.forwarder => 'Facture Transitaire',
    DossierInvoiceKind.carrier => 'Facture Transporteur',
  };

  DossierInvoice _invoiceFor(TransitDossier dossier) => switch (widget.kind) {
    DossierInvoiceKind.client => dossier.factureClient,
    DossierInvoiceKind.provider => dossier.facturePrestataire,
    DossierInvoiceKind.forwarder => dossier.factureTransitaire,
    DossierInvoiceKind.carrier => dossier.factureTransporteur,
  };

  Prestataire? _partnerFor(TransitDossier dossier) => switch (widget.kind) {
    DossierInvoiceKind.forwarder =>
      dossier.transitaireAffecte ??
          (dossier.prestataire?.type == 'Transitaire'
              ? dossier.prestataire
              : null),
    DossierInvoiceKind.carrier =>
      dossier.transporteurAffecte ??
          (dossier.prestataire?.type == 'Transporteur'
              ? dossier.prestataire
              : null),
    _ => dossier.prestataire,
  };

  bool _matchesPartnerKind(TransitDossier dossier) {
    if (!_isTransitaire && !_isTransporteur) return true;
    if (dossier.prestataire == null) return true;
    return _isTransitaire
        ? dossier.prestataire!.type == 'Transitaire'
        : dossier.prestataire!.type == 'Transporteur';
  }

  @override
  Widget build(BuildContext context) {
    final invoices =
        widget.dossiers
            .map((dossier) => (dossier, _invoiceFor(dossier)))
            .where((entry) => _matchesPartnerKind(entry.$1))
            .toList()
          ..sort((a, b) => b.$1.dateCreation.compareTo(a.$1.dateCreation));
    final matchingInvoices = invoices.where((entry) {
      final dossier = entry.$1;
      final invoice = entry.$2;
      final recipient = _isClient
          ? dossier.client.nom
          : _partnerFor(dossier)?.entreprise ?? 'Prestataire non affecté';
      final searchText =
          '${invoice.reference} ${dossier.numDossier} ${dossier.numBL} $recipient ${invoice.description} ${invoice.lignes.map((line) => line.description).join(' ')}'
              .toLowerCase();
      return searchText.contains(_query.toLowerCase());
    }).toList();
    final issuedTotal = invoices
        .where((entry) => entry.$2.statut == 'Clôturée')
        .fold<double>(0, (total, entry) => total + entry.$2.montant);
    final title = _title;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A237E),
          elevation: 0,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isClient
                            ? 'Factures de prestation adressées à vos clients.'
                            : _isTransitaire
                            ? 'Factures des prestations de transit.'
                            : _isTransporteur
                            ? 'Factures des transports et chargements.'
                            : 'Factures prestataires liées aux dossiers.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Total des factures émises : ${formatCurrency(issuedTotal)} FCFA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    key: const ValueKey('invoice-search'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par facture, dossier, BL ou tiers…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Factures en cours'),
                    Tab(text: 'Factures validées'),
                  ],
                  labelColor: Color(0xFF1A237E),
                  unselectedLabelColor: Colors.black54,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildInvoiceList(
                        matchingInvoices
                            .where((entry) => entry.$2.statut != 'Clôturée')
                            .toList(),
                      ),
                      _buildInvoiceList(
                        matchingInvoices
                            .where((entry) => entry.$2.statut == 'Clôturée')
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceList(List<(TransitDossier, DossierInvoice)> invoices) {
    if (invoices.isEmpty) {
      return const Center(child: Text('Aucune facture dans cette catégorie.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final dossier = invoices[index].$1;
        final invoice = invoices[index].$2;
        final recipient = _isClient
            ? dossier.client.nom
            : _partnerFor(dossier)?.entreprise ?? 'Prestataire non affecté';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: invoice.statut == 'Clôturée'
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFF3E0),
              child: Icon(
                invoice.statut == 'Clôturée'
                    ? Icons.receipt_long_rounded
                    : Icons.edit_note_rounded,
                color: invoice.statut == 'Clôturée'
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
              ),
            ),
            title: Text(
              '${invoice.reference} • ${dossier.numDossier}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '$recipient\n${invoice.description.isEmpty ? 'Ouvrir la facture pour saisir les prestations' : invoice.description} • ${invoice.statut}',
            ),
            isThreeLine: true,
            trailing: SizedBox(
              width: 148,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      '${formatCurrency(invoice.montant)} F',
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('edit-${invoice.id}'),
                    tooltip: 'Ouvrir la facture',
                    onPressed: () => _editInvoice(dossier, invoice),
                    icon: Icon(
                      invoice.statut == 'Clôturée'
                          ? Icons.lock_outline_rounded
                          : Icons.open_in_new_rounded,
                    ),
                  ),
                ],
              ),
            ),
            onTap: () => _editInvoice(dossier, invoice),
          ),
        );
      },
    );
  }

  Future<void> _editInvoice(
    TransitDossier dossier,
    DossierInvoice invoice,
  ) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DossierInvoiceDetailPage(
          invoice: invoice,
          dossier: dossier,
          kind: widget.kind,
          prestataires: widget.prestataires,
          userDisplayName: widget.userDisplayName,
        ),
      ),
    );
    if (updated == true && mounted) setState(() {});
  }
}

class _InvoiceLineDraft {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitPrice = TextEditingController();
  final containerNumber = TextEditingController();
  final bl = TextEditingController();
  final cargo = TextEditingController();
  final containerType = TextEditingController();
  final transitFee = TextEditingController();
  final volumeWeight = TextEditingController();
  final demurrage = TextEditingController();
  final toll = TextEditingController();
  final otherFee = TextEditingController();
  final truckAdvance = TextEditingController();
  final vehiclePlate = TextEditingController();

  _InvoiceLineDraft({InvoiceLine? line, TransitContainer? container}) {
    if (line != null) {
      description.text = line.description;
      quantity.text = line.quantite.toString();
      unitPrice.text = line.prixUnitaire.toStringAsFixed(0);
      containerNumber.text = line.numeroConteneur;
      bl.text = line.bl;
      cargo.text = line.marchandise;
      containerType.text = line.typeConteneur;
      transitFee.text = _draftAmount(line.fraisTransit);
      volumeWeight.text = _draftAmount(line.volumePoids);
      demurrage.text = _draftAmount(line.surestariesMagasinage);
      toll.text = _draftAmount(line.fraisPeage);
      otherFee.text = _draftAmount(line.autresFrais);
      truckAdvance.text = _draftAmount(line.avanceCamion);
      vehiclePlate.text = line.plaqueVehicule;
    } else if (container != null) {
      description.text = 'Prestation transport ${container.numero}';
      containerNumber.text = container.numero;
      cargo.text = container.marchandise;
      containerType.text = container.type;
    }
  }

  String _draftAmount(double value) =>
      value == 0 ? '' : value.toStringAsFixed(0);

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
    containerNumber.dispose();
    bl.dispose();
    cargo.dispose();
    containerType.dispose();
    transitFee.dispose();
    volumeWeight.dispose();
    demurrage.dispose();
    toll.dispose();
    otherFee.dispose();
    truckAdvance.dispose();
    vehiclePlate.dispose();
  }
}

class DossierInvoiceDetailPage extends StatefulWidget {
  final DossierInvoice invoice;
  final TransitDossier dossier;
  final DossierInvoiceKind kind;
  final List<Prestataire> prestataires;
  final String userDisplayName;

  const DossierInvoiceDetailPage({
    super.key,
    required this.invoice,
    required this.dossier,
    required this.kind,
    required this.prestataires,
    required this.userDisplayName,
  });

  @override
  State<DossierInvoiceDetailPage> createState() =>
      _DossierInvoiceDetailPageState();
}

class _DossierInvoiceDetailPageState extends State<DossierInvoiceDetailPage> {
  final List<_InvoiceLineDraft> _lines = [];
  Prestataire? _selectedPrestataire;

  bool get _isClient => widget.kind == DossierInvoiceKind.client;
  bool get _isTransitaire => widget.kind == DossierInvoiceKind.forwarder;
  bool get _isTransporteur => widget.kind == DossierInvoiceKind.carrier;
  bool get _isClosed => widget.invoice.statut == 'Clôturée';
  String get _title => switch (widget.kind) {
    DossierInvoiceKind.client => 'Facture Client',
    DossierInvoiceKind.provider => 'Facture Prestataire',
    DossierInvoiceKind.forwarder => 'Facture Transitaire',
    DossierInvoiceKind.carrier => 'Facture Transporteur',
  };

  @override
  void initState() {
    super.initState();
    final assignedProvider = switch (widget.kind) {
      DossierInvoiceKind.forwarder =>
        widget.dossier.transitaireAffecte ??
            (widget.dossier.prestataire?.type == 'Transitaire'
                ? widget.dossier.prestataire
                : null),
      DossierInvoiceKind.carrier =>
        widget.dossier.transporteurAffecte ??
            (widget.dossier.prestataire?.type == 'Transporteur'
                ? widget.dossier.prestataire
                : null),
      _ => widget.dossier.prestataire,
    };
    _selectedPrestataire =
        (widget.kind == DossierInvoiceKind.forwarder &&
                assignedProvider?.type != 'Transitaire') ||
            (widget.kind == DossierInvoiceKind.carrier &&
                assignedProvider?.type != 'Transporteur')
        ? null
        : assignedProvider;
    if (widget.invoice.lignes.isNotEmpty) {
      _lines.addAll(
        widget.invoice.lignes.map((line) => _InvoiceLineDraft(line: line)),
      );
    } else if (widget.invoice.description.isNotEmpty ||
        widget.invoice.montant > 0) {
      _lines.add(
        _InvoiceLineDraft(
          line: InvoiceLine(
            description: widget.invoice.description,
            quantite: 1,
            prixUnitaire: widget.invoice.montant,
          ),
        ),
      );
    } else if (_isClient) {
      _lines.add(
        _InvoiceLineDraft(
          line: InvoiceLine(
            description: widget.dossier.typeMarchandise.isEmpty
                ? 'Prestation de transport'
                : widget.dossier.typeMarchandise,
            quantite: widget.dossier.nbConteneurs > 0
                ? widget.dossier.nbConteneurs.toDouble()
                : 1,
            prixUnitaire: 0,
          ),
        ),
      );
    } else if (!_isClient && widget.dossier.conteneurs.isNotEmpty) {
      _lines.addAll(
        widget.dossier.conteneurs.map(
          (container) => _InvoiceLineDraft(container: container),
        ),
      );
    } else {
      _lines.add(_InvoiceLineDraft());
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipient = _isClient
        ? widget.dossier.client.nom
        : widget.dossier.prestataire?.entreprise ?? 'Prestataire non affecté';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(
          '$_title ${widget.invoice.reference}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const ValueKey('print-invoice'),
            tooltip: 'Imprimer / enregistrer en PDF',
            onPressed: _printInvoice,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Chip(
              label: Text(widget.invoice.statut),
              backgroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dossier : ${widget.dossier.numDossier}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_isClient ? 'Client' : 'Prestataire'} : ${_isClient ? recipient : _selectedPrestataire?.entreprise ?? recipient}',
                      ),
                      if (!_isClient &&
                          (widget.dossier.prestataire == null ||
                              (_isTransitaire &&
                                  widget.dossier.prestataire!.type !=
                                      'Transitaire') ||
                              (_isTransporteur &&
                                  widget.dossier.prestataire!.type !=
                                      'Transporteur'))) ...[
                        const SizedBox(height: 14),
                        SearchableDropdownFormField<Prestataire>(
                          key: const ValueKey('invoice-provider-search'),
                          options: widget.prestataires.where((provider) {
                            if (_isTransitaire) {
                              return provider.type == 'Transitaire';
                            }
                            if (_isTransporteur) {
                              return provider.type == 'Transporteur';
                            }
                            return true;
                          }).toList(),
                          value: _selectedPrestataire,
                          label: _isTransitaire
                              ? 'Rechercher et affecter un transitaire'
                              : _isTransporteur
                              ? 'Rechercher et affecter un transporteur'
                              : 'Rechercher et affecter un prestataire',
                          emptyText: 'Aucun prestataire enregistré',
                          displayString: (provider) =>
                              '${provider.entreprise} • ${provider.villePort}',
                          onChanged: (provider) =>
                              setState(() => _selectedPrestataire = provider),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Prestations facturées',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!_isClosed)
                          FilledButton.tonalIcon(
                            key: const ValueKey('add-invoice-line'),
                            onPressed: () =>
                                setState(() => _lines.add(_InvoiceLineDraft())),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter une ligne'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_lines.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Aucune prestation sur cette facture.'),
                        ),
                      ),
                    ...List.generate(_lines.length, (index) {
                      final line = _lines[index];
                      return Card(
                        key: ValueKey('invoice-line-$index'),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 340,
                                child: TextFormField(
                                  key: ValueKey('invoice-description-$index'),
                                  controller: line.description,
                                  enabled: !_isClosed,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Désignation / prestation',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              if (_isClient) ...[
                                _invoiceField(
                                  line.quantity,
                                  'Quantité (conteneurs)',
                                  'invoice-quantity-$index',
                                  numeric: true,
                                  width: 160,
                                ),
                                _invoiceField(
                                  line.unitPrice,
                                  'Prix unitaire',
                                  'invoice-price-$index',
                                  numeric: true,
                                  width: 190,
                                  suffix: 'FCFA',
                                ),
                              ] else ...[
                                _invoiceField(
                                  line.containerNumber,
                                  'N° conteneur',
                                  'invoice-container-$index',
                                ),
                                _invoiceField(
                                  line.bl,
                                  'N° BL',
                                  'invoice-bl-$index',
                                ),
                                _invoiceField(
                                  line.cargo,
                                  'Marchandise',
                                  'invoice-cargo-$index',
                                ),
                                _invoiceField(
                                  line.containerType,
                                  'Type conteneur',
                                  'invoice-container-type-$index',
                                ),
                                _invoiceField(
                                  line.transitFee,
                                  'Frais de transit',
                                  'invoice-transit-fee-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.volumeWeight,
                                  'Poids / volume',
                                  'invoice-volume-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.demurrage,
                                  'Surestaries / magasinage',
                                  'invoice-demurrage-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.toll,
                                  'Péage',
                                  'invoice-toll-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.otherFee,
                                  'Autres frais',
                                  'invoice-other-fee-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.truckAdvance,
                                  'Avance camion',
                                  'invoice-truck-advance-$index',
                                  numeric: true,
                                  suffix: 'FCFA',
                                ),
                                _invoiceField(
                                  line.vehiclePlate,
                                  'Plaque véhicule',
                                  'invoice-vehicle-plate-$index',
                                ),
                              ],
                              SizedBox(
                                width: 150,
                                child: Text(
                                  '${formatCurrency(_lineTotal(line))} FCFA',
                                  key: ValueKey('invoice-total-$index'),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A237E),
                                  ),
                                ),
                              ),
                              if (!_isClosed)
                                IconButton(
                                  tooltip: 'Supprimer cette ligne',
                                  onPressed: () => setState(() {
                                    _lines.removeAt(index).dispose();
                                  }),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'TOTAL DE LA FACTURE',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              '${formatCurrency(_total)} FCFA',
                              key: const ValueKey('invoice-grand-total'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isClosed)
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: Colors.white,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('save-invoice-exit'),
                          onPressed: _saveAndExit,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Enregistrer et quitter'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('close-invoice'),
                          onPressed: _closeInvoice,
                          icon: const Icon(Icons.lock_outline_rounded),
                          label: const Text('Valider et clôturer la facture'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double get _total =>
      _lines.fold(0, (total, line) => total + _lineTotal(line));

  double _lineTotal(_InvoiceLineDraft line) {
    if (_isClient) {
      return (_number(line.quantity.text) ?? 0) *
          (_number(line.unitPrice.text) ?? 0);
    }
    return (_number(line.transitFee.text) ?? 0) +
        (_number(line.volumeWeight.text) ?? 0) +
        (_number(line.demurrage.text) ?? 0) +
        (_number(line.toll.text) ?? 0) +
        (_number(line.otherFee.text) ?? 0) -
        (_number(line.truckAdvance.text) ?? 0);
  }

  Widget _invoiceField(
    TextEditingController controller,
    String label,
    String keyName, {
    bool numeric = false,
    String? suffix,
    double width = 180,
  }) => SizedBox(
    width: width,
    child: TextFormField(
      key: ValueKey(keyName),
      controller: controller,
      enabled: !_isClosed,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(' ', '').replaceAll(',', '.'));

  List<InvoiceLine>? _readLines({required bool requireComplete}) {
    final result = <InvoiceLine>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final description = line.description.text.trim();
      final quantityText = line.quantity.text.trim();
      final priceText = line.unitPrice.text.trim();
      final providerHasDetails = [
        line.containerNumber,
        line.bl,
        line.cargo,
        line.containerType,
        line.transitFee,
        line.volumeWeight,
        line.demurrage,
        line.toll,
        line.otherFee,
        line.truckAdvance,
        line.vehiclePlate,
      ].any((controller) => controller.text.trim().isNotEmpty);
      if (description.isEmpty &&
          quantityText == '1' &&
          priceText.isEmpty &&
          !providerHasDetails) {
        continue;
      }
      if (!_isClient) {
        final amounts = [
          line.transitFee,
          line.volumeWeight,
          line.demurrage,
          line.toll,
          line.otherFee,
          line.truckAdvance,
        ].map((controller) => _number(controller.text) ?? 0).toList();
        if (description.isEmpty ||
            amounts.any((amount) => amount < 0) ||
            _number(line.transitFee.text) == null &&
                line.transitFee.text.isNotEmpty ||
            _number(line.volumeWeight.text) == null &&
                line.volumeWeight.text.isNotEmpty ||
            _number(line.demurrage.text) == null &&
                line.demurrage.text.isNotEmpty ||
            _number(line.toll.text) == null && line.toll.text.isNotEmpty ||
            _number(line.otherFee.text) == null &&
                line.otherFee.text.isNotEmpty ||
            _number(line.truckAdvance.text) == null &&
                line.truckAdvance.text.isNotEmpty) {
          _showMessage(
            'Vérifiez la désignation et les montants de la prestation.',
          );
          return null;
        }
        if (requireComplete && _lineTotal(line) == 0) {
          _showMessage(
            'Saisissez un frais ou une avance pour chaque prestation.',
          );
          return null;
        }
        result.add(
          InvoiceLine(
            description: description,
            quantite: 1,
            prixUnitaire: 0,
            numeroConteneur: line.containerNumber.text.trim(),
            bl: line.bl.text.trim(),
            marchandise: line.cargo.text.trim(),
            typeConteneur: line.containerType.text.trim(),
            fraisTransit: amounts[0],
            volumePoids: amounts[1],
            surestariesMagasinage: amounts[2],
            fraisPeage: amounts[3],
            autresFrais: amounts[4],
            avanceCamion: amounts[5],
            plaqueVehicule: line.vehiclePlate.text.trim(),
          ),
        );
        continue;
      }
      final quantity = _number(quantityText);
      final unitPrice = priceText.isEmpty && !requireComplete
          ? 0.0
          : _number(priceText);
      if (description.isEmpty ||
          quantity == null ||
          quantity <= 0 ||
          unitPrice == null ||
          (requireComplete && unitPrice <= 0)) {
        _showMessage(
          'Complétez la désignation, la quantité et le prix de chaque ligne.',
        );
        return null;
      }
      result.add(
        InvoiceLine(
          description: description,
          quantite: quantity,
          prixUnitaire: unitPrice,
        ),
      );
    }
    if (requireComplete && result.isEmpty) {
      _showMessage('Ajoutez au moins une prestation avant de clôturer.');
      return null;
    }
    return result;
  }

  Future<void> _saveAndExit() async {
    final lines = _readLines(requireComplete: false);
    if (lines == null) return;
    if (!_isClient && _selectedPrestataire == null) {
      _showMessage('Sélectionnez un prestataire avant d’enregistrer.');
      return;
    }
    _saveLines(lines);
    if (widget.invoice.statut != 'Clôturée') {
      widget.invoice.statut = lines.isEmpty ? 'Brouillon' : 'En cours';
    }
    if (!await _persist(
      context,
      () => erpBackend.saveDossier(widget.dossier),
    )) {
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _closeInvoice() async {
    final lines = _readLines(requireComplete: true);
    if (lines == null) return;
    if (!_isClient && _selectedPrestataire == null) {
      _showMessage('Sélectionnez un prestataire avant de clôturer.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer cette facture ?'),
        content: const Text(
          'Après validation, la facture sera verrouillée et ne pourra plus être modifiée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider et clôturer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _saveLines(lines);
    final previousStatus = widget.invoice.statut;
    final previousDate = widget.invoice.dateEmission;
    widget.invoice
      ..statut = 'Clôturée'
      ..dateEmission = DateFormat('dd/MM/yyyy').format(DateTime.now());
    if (!await _persist(
      context,
      () => erpBackend.saveDossier(widget.dossier),
    )) {
      // La facture reste modifiable tant que la clôture n'est pas enregistrée.
      widget.invoice
        ..statut = previousStatus
        ..dateEmission = previousDate;
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _saveLines(List<InvoiceLine> lines) {
    if (!_isClient) {
      switch (widget.kind) {
        case DossierInvoiceKind.forwarder:
          widget.dossier.transitaireAffecte ??= _selectedPrestataire;
        case DossierInvoiceKind.carrier:
          widget.dossier.transporteurAffecte ??= _selectedPrestataire;
        case DossierInvoiceKind.provider:
          widget.dossier.prestataire ??= _selectedPrestataire;
        case DossierInvoiceKind.client:
          break;
      }
      widget.dossier.prestataire ??= _selectedPrestataire;
    }
    final total = lines.fold<double>(
      0,
      (sum, line) =>
          sum +
          (_isClient ? line.total : line.totalPrestataire - line.avanceCamion),
    );
    widget.invoice
      ..lignes = lines
      ..description = lines.map((line) => line.description).join(', ')
      ..montant = total;
  }

  Future<void> _printInvoice() async {
    final isProvider = !_isClient;
    final pdf = pw.Document();
    final recipient = isProvider
        ? (_selectedPrestataire?.entreprise ??
              widget.dossier.prestataire?.entreprise ??
              'Prestataire non affecté')
        : widget.dossier.client.nom;
    final rows = _lines;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: isProvider ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: isProvider ? PdfColors.teal900 : PdfColors.indigo900,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SYLLA TRANSIT & TRANSPORT',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  switch (widget.kind) {
                    DossierInvoiceKind.client => 'FACTURE CLIENT',
                    DossierInvoiceKind.provider => 'FACTURE PRESTATAIRE',
                    DossierInvoiceKind.forwarder => 'FACTURE TRANSITAIRE',
                    DossierInvoiceKind.carrier => 'FACTURE TRANSPORTEUR',
                  },
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Facture : ${widget.invoice.reference}    Dossier : ${widget.dossier.numDossier}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('${isProvider ? 'Prestataire' : 'Client'} : $recipient'),
          pw.Text('Bon de livraison : ${widget.dossier.numBL}'),
          pw.Text('Marchandise : ${widget.dossier.typeMarchandise}'),
          pw.Text('Conteneurs : ${widget.dossier.nbConteneurs}'),
          pw.Text(
            'Date : ${widget.invoice.dateEmission.isEmpty ? DateFormat('dd/MM/yyyy').format(DateTime.now()) : widget.invoice.dateEmission}',
          ),
          pw.SizedBox(height: 16),
          if (!isProvider)
            pw.TableHelper.fromTextArray(
              headers: ['Désignation', 'Quantité', 'Prix unitaire', 'Montant'],
              data: rows
                  .map(
                    (line) => [
                      line.description.text,
                      line.quantity.text,
                      '${formatCurrency(_number(line.unitPrice.text) ?? 0)} FCFA',
                      '${formatCurrency(_lineTotal(line))} FCFA',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo800,
              ),
              cellPadding: const pw.EdgeInsets.all(7),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Conteneur / BL',
                'Marchandise / type',
                'Transit',
                'Poids / volume',
                'Surestaries / magasinage',
                'Péage',
                'Autres frais',
                'Avance camion',
                'Plaque',
                'Net à payer',
              ],
              data: rows
                  .map(
                    (line) => [
                      '${line.containerNumber.text}\n${line.bl.text}',
                      '${line.cargo.text}\n${line.containerType.text}',
                      formatCurrency(_number(line.transitFee.text) ?? 0),
                      formatCurrency(_number(line.volumeWeight.text) ?? 0),
                      formatCurrency(_number(line.demurrage.text) ?? 0),
                      formatCurrency(_number(line.toll.text) ?? 0),
                      formatCurrency(_number(line.otherFee.text) ?? 0),
                      formatCurrency(_number(line.truckAdvance.text) ?? 0),
                      line.vehiclePlate.text,
                      '${formatCurrency(_lineTotal(line))} FCFA',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 8,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'TOTAL ${isProvider ? 'NET À PAYER' : 'FACTURE'} : ${formatCurrency(_total)} FCFA',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 14),
          child: pw.Text(
            'Saisi par : ${widget.userDisplayName}    •    Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// --- PAGE DOSSIERS ---

// --- PAGE CLIENTS ---

class ClientsPage extends StatefulWidget {
  final List<Client> clients;
  final List<PlanAccount> comptes;

  const ClientsPage({super.key, required this.clients, required this.comptes});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  String q = "";

  @override
  Widget build(BuildContext context) {
    final fil = widget.clients
        .where((c) => c.nom.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          "Portefeuille Clients",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Center(
            child: Container(
              width: 800,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: InputDecoration(
                  hintText: "Rechercher un client...",
                  prefixIcon: const Icon(Icons.search),
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Container(
          width: 800,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: fil.length,
            itemBuilder: (context, i) => Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8EAF6),
                  child: Icon(Icons.person, color: Color(0xFF1A237E)),
                ),
                title: Text(
                  fil[i].nom,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${fil[i].telephone}\nCompte client : ${fil[i].compteComptable}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  key: ValueKey('edit-client-${fil[i].id}'),
                  tooltip: 'Modifier le client',
                  onPressed: () => _openClientForm(fil[i]),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'legacy-client-add',
        backgroundColor: const Color(0xFF1A237E),
        onPressed: _showAdd,
        child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
      ),
    );
  }

  Future<void> _showAdd() => _openClientForm();

  Future<void> _openClientForm([Client? initial]) async {
    final client = await showDialog<Client>(
      context: context,
      builder: (context) => _ClientFormDialog(
        clients: widget.clients,
        comptes: widget.comptes,
        initial: initial,
      ),
    );
    if (client == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveClient(client))) return;
    _linkTiersAccount(
      widget.comptes,
      tiersId: client.id,
      previousCode: initial?.compteComptable,
      newCode: client.compteComptable,
    );
    if (mounted) {
      setState(() {
        final index = widget.clients.indexWhere((item) => item.id == client.id);
        if (index < 0) {
          widget.clients.add(client);
        } else {
          widget.clients[index] = client;
        }
      });
    }
  }
}

class _ClientFormDialog extends StatefulWidget {
  final List<Client> clients;
  final List<PlanAccount> comptes;
  final Client? initial;

  const _ClientFormDialog({
    required this.clients,
    required this.comptes,
    this.initial,
  });

  @override
  State<_ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<_ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _rccm = TextEditingController();
  final _openingBalance = TextEditingController(text: '0');
  PlanAccount? _selectedAccount;
  bool _vat = false;

  @override
  void initState() {
    super.initState();
    final client = widget.initial;
    if (client == null) {
      _selectedAccount = _accountsForTiers(
        widget.comptes,
        nature: 'Client',
        classPrefix: '41',
      ).firstOrNull;
      return;
    }
    _name.text = client.nom;
    _company.text = client.societe;
    _phone.text = client.telephone;
    _address.text = client.adresse;
    _email.text = client.email;
    _rccm.text = client.rccm;
    _openingBalance.text = client.soldeInitial.toString();
    _vat = client.assujettiTva;
    for (final account in widget.comptes) {
      if (account.code == client.compteComptable) {
        _selectedAccount = account;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    _address.dispose();
    _email.dispose();
    _rccm.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Ajouter un client' : 'Modifier le client',
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField(_name, 'Nom *', required: true),
                _textField(_company, 'Société'),
                _textField(
                  _phone,
                  'Téléphone *',
                  required: true,
                  keyboardType: TextInputType.phone,
                ),
                _textField(_address, 'Adresse', maxLines: 2),
                _textField(
                  _email,
                  'Boîte mail',
                  keyboardType: TextInputType.emailAddress,
                ),
                _textField(_rccm, 'RCCM'),
                _textField(
                  _openingBalance,
                  'Solde initial client (FCFA)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  amount: true,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _vat,
                  title: const Text('Assujetti à la TVA'),
                  onChanged: (value) => setState(() => _vat = value ?? false),
                ),
                KeyedSubtree(
                  key: const ValueKey('client-account-picker'),
                  child: SearchableDropdownFormField<PlanAccount>(
                    key: ValueKey(
                      'client-account-picker-${widget.comptes.length}',
                    ),
                    options: _accountsForTiers(
                      widget.comptes,
                      nature: 'Client',
                      classPrefix: '41',
                      currentCode: widget.initial?.compteComptable,
                    ),
                    value: _selectedAccount,
                    label: 'Compte comptable client *',
                    emptyText:
                        'Aucun compte client (411…) dans le plan comptable',
                    displayString: (account) =>
                        '${account.code} • ${account.libelle}',
                    onChanged: (account) =>
                        setState(() => _selectedAccount = account),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler"),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: Text(
            widget.initial == null
                ? 'Valider'
                : 'Enregistrer les modifications',
          ),
        ),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool amount = false,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return 'Ce champ est obligatoire';
          }
          if (amount) {
            final parsed = double.tryParse(
              (value ?? '').trim().replaceAll(' ', '').replaceAll(',', '.'),
            );
            if (parsed == null || parsed < 0) {
              return 'Saisissez un solde égal ou supérieur à zéro';
            }
          }
          return null;
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final account = _selectedAccount;
    if (account == null) {
      _showMessage('Sélectionnez un compte client existant.');
      return;
    }
    final clientName = _name.text.trim();
    final rccm = _rccm.text.trim();
    final duplicate = widget.clients.any(
      (client) =>
          client.id != widget.initial?.id &&
          (_normalizeUniqueValue(client.nom) ==
                  _normalizeUniqueValue(clientName) ||
              (rccm.isNotEmpty &&
                  _normalizeUniqueValue(client.rccm) ==
                      _normalizeUniqueValue(rccm))),
    );
    if (duplicate) {
      await _showDuplicateAlert(context, 'Ce client');
      return;
    }
    final id =
        widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final openingBalance = double.parse(
      _openingBalance.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
    );
    Navigator.pop(
      context,
      Client(
        id: id,
        nom: clientName,
        telephone: _phone.text.trim(),
        societe: _company.text.trim(),
        adresse: _address.text.trim(),
        email: _email.text.trim(),
        rccm: _rccm.text.trim(),
        soldeInitial: openingBalance,
        assujettiTva: _vat,
        compteComptable: account.code,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// --- PAGE HISTORIQUE ---

class HistoryPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  const HistoryPage({super.key, required this.dossiers});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String q = "";
  @override
  Widget build(BuildContext context) {
    Map<String, List<TransitDossier>> grouped = {};
    for (var d in widget.dossiers) {
      if (d.client.nom.toLowerCase().contains(q.toLowerCase()) ||
          d.numDossier.contains(q)) {
        grouped.putIfAbsent(d.client.nom, () => []).add(d);
      }
    }
    final names = grouped.keys.toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          "Analyse & Rapports",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Center(
            child: Container(
              width: 800,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: InputDecoration(
                  hintText: "Filtrer par Client ou Dossier...",
                  prefixIcon: const Icon(Icons.analytics_rounded),
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Container(
          width: 800,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: names.length,
            itemBuilder: (context, index) {
              final name = names[index];
              final clDs = grouped[name]!;
              double tot = clDs.fold(0, (s, d) => s + d.totalDepenses);
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8EAF6),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Cumul total : ${formatCurrency(tot)} F"),
                  children: clDs
                      .map(
                        (d) => ExpansionTile(
                          title: Text("Dossier: ${d.numDossier}"),
                          subtitle: Text(
                            "Total: ${formatCurrency(d.totalDepenses)} F",
                          ),
                          children: d.depenses
                              .map(
                                (exp) => ListTile(
                                  dense: true,
                                  title: Text(exp.titre),
                                  subtitle: Text(exp.date),
                                  trailing: Text(
                                    "-${formatCurrency(exp.montant)} F",
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- PAGE DÉTAILS ---

class DetailsDossierPage extends StatefulWidget {
  final TransitDossier dossier;
  final List<JournalCode> journals;
  const DetailsDossierPage({
    super.key,
    required this.dossier,
    this.journals = const [],
  });
  @override
  State<DetailsDossierPage> createState() => _DetailsDossierPageState();
}

class _DetailsDossierPageState extends State<DetailsDossierPage> {
  Future<void> _pdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              text:
                  "SYLLA TRANSIT - RAPPORT DOSSIER ${widget.dossier.numDossier}",
            ),
            pw.Text("Client: ${widget.dossier.client.nom}"),
            if (widget.dossier.prestataire != null)
              pw.Text(
                "Prestataire affecté: ${widget.dossier.prestataire!.entreprise}",
              ),
            pw.Text(
              "BL: ${widget.dossier.numBL} | LB: ${widget.dossier.numLB}",
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Facture Client ${widget.dossier.factureClient.reference} — ${widget.dossier.factureClient.statut}: ${formatCurrency(widget.dossier.factureClient.montant)} FCFA",
            ),
            pw.Text(
              "Facture Prestataire ${widget.dossier.facturePrestataire.reference} — ${widget.dossier.facturePrestataire.statut}: ${formatCurrency(widget.dossier.facturePrestataire.montant)} FCFA",
            ),
            pw.Text(
              "Compte client — facturé: ${formatCurrency(widget.dossier.totalFacturesClient)} FCFA, réglé: ${formatCurrency(widget.dossier.totalReglementsClient)} FCFA, solde: ${formatCurrency(widget.dossier.soldeClient)} FCFA",
            ),
            if (widget.dossier.prestataire != null)
              pw.Text(
                "Compte prestataire — facturé: ${formatCurrency(widget.dossier.totalFacturesPrestataire)} FCFA, avances: ${formatCurrency(widget.dossier.totalAvancesPrestataire)} FCFA, payé: ${formatCurrency(widget.dossier.totalReglementsPrestataire)} FCFA, solde: ${formatCurrency(widget.dossier.soldePrestataire)} FCFA",
              ),
            pw.SizedBox(height: 12),
            pw.Text("Historique des opérations"),
            pw.Table.fromTextArray(
              headers: ['Date', 'Opération', 'Détail', 'Montant'],
              data: widget.dossier.operations
                  .map(
                    (entry) => [
                      entry.date,
                      _operationLabel(entry.type),
                      entry.titre,
                      formatCurrency(entry.montant),
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Date', 'Frais du dossier', 'Catégorie', 'Montant'],
              data: widget.dossier.depenses
                  .map(
                    (e) => [
                      e.date,
                      e.titre,
                      e.categorie,
                      formatCurrency(e.montant),
                    ],
                  )
                  .toList(),
            ),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                "TOTAL DES DÉPENSES: ${formatCurrency(widget.dossier.totalDepenses)} FCFA",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(
          "Détails Dossier ${widget.dossier.numDossier}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _pdf),
          if (widget.dossier.statut == 'Clôturé')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Chip(label: Text('Clôturé')),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    const Text(
                      'DÉPENSES DU DOSSIER',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${formatCurrency(widget.dossier.totalDepenses)} FCFA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(
                            Icons.person_outline,
                            color: Colors.white,
                          ),
                          label: Text(
                            'Client : ${widget.dossier.client.nom}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.white24,
                        ),
                        Chip(
                          avatar: const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.white,
                          ),
                          label: Text(
                            'Prestataire : ${widget.dossier.prestataire?.entreprise ?? 'Non affecté'}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.white24,
                        ),
                        Chip(
                          label: Text(
                            'BL : ${widget.dossier.numBL.isEmpty ? 'Non renseigné' : widget.dossier.numBL}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.white24,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _balanceCard(
                          title: 'Compte client',
                          amountLabel: 'Facturé',
                          amount: widget.dossier.totalFacturesClient,
                          secondLabel: 'Réglé',
                          secondAmount: widget.dossier.totalReglementsClient,
                          balance: widget.dossier.soldeClient,
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF1565C0),
                        ),
                        if (widget.dossier.prestataire != null)
                          _balanceCard(
                            title: 'Compte prestataire',
                            amountLabel: 'Facturé',
                            amount: widget.dossier.totalFacturesPrestataire,
                            secondLabel: 'Avances + paiements',
                            secondAmount:
                                widget.dossier.totalAvancesPrestataire +
                                widget.dossier.totalReglementsPrestataire,
                            balance: widget.dossier.soldePrestataire,
                            icon: Icons.local_shipping_rounded,
                            color: const Color(0xFF6A1B9A),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Clôture du dossier',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_closureMessage()),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: widget.dossier.peutCloturer
                                    ? _closeDossier
                                    : null,
                                icon: const Icon(Icons.lock_outline_rounded),
                                label: const Text('Clôturer le dossier'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Historique des frais et mouvements',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _invoiceTile(
                      widget.dossier.factureClient,
                      widget.dossier.client.nom,
                    ),
                    _invoiceTile(
                      widget.dossier.facturePrestataire,
                      widget.dossier.prestataire?.entreprise ??
                          'Prestataire non affecté',
                    ),
                    _invoiceTile(
                      widget.dossier.factureTransitaire,
                      widget.dossier.transitaireAffecte?.entreprise ??
                          (widget.dossier.prestataire?.type == 'Transitaire'
                              ? widget.dossier.prestataire!.entreprise
                              : 'Transitaire non affecté'),
                    ),
                    _invoiceTile(
                      widget.dossier.factureTransporteur,
                      widget.dossier.transporteurAffecte?.entreprise ??
                          (widget.dossier.prestataire?.type == 'Transporteur'
                              ? widget.dossier.prestataire!.entreprise
                              : 'Transporteur non affecté'),
                    ),
                    if (widget.dossier.operations.isEmpty &&
                        widget.dossier.depenses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Aucun frais, facture, règlement ou avance enregistré pour ce dossier.',
                          ),
                        ),
                      ),
                    ...widget.dossier.operations.map(_operationTile),
                    ...widget.dossier.depenses.map(_expenseTile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.dossier.statut == 'Clôturé'
          ? null
          : FloatingActionButton.extended(
              heroTag: 'dossier-operation-add-${widget.dossier.id}',
              key: const ValueKey('add-dossier-operation'),
              backgroundColor: const Color(0xFF1A237E),
              onPressed: _addOperation,
              label: const Text(
                'AJOUTER UN FRAIS / MOUVEMENT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Widget _balanceCard({
    required String title,
    required String amountLabel,
    required double amount,
    required String secondLabel,
    required double secondAmount,
    required double balance,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 32).clamp(280.0, 460.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _moneyLine(amountLabel, amount),
              _moneyLine(secondLabel, secondAmount),
              const Divider(height: 20),
              _moneyLine(
                'Solde à payer',
                balance,
                bold: true,
                color: balance > 0 ? Colors.redAccent : Colors.green.shade700,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyLine(
    String label,
    double amount, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '${formatCurrency(amount)} FCFA',
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _operationTile(DossierOperation entry) {
    final isCredit =
        entry.type == DossierOperationType.clientPayment ||
        entry.type == DossierOperationType.providerAdvance ||
        entry.type == DossierOperationType.providerPayment;
    return Card(
      child: ListTile(
        leading: Icon(
          _operationIcon(entry.type),
          color: isCredit ? Colors.green.shade700 : const Color(0xFF1A237E),
        ),
        title: Text(
          entry.titre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${_operationLabel(entry.type)} • ${entry.date}'),
        trailing: Text(
          '${isCredit ? '-' : '+'}${formatCurrency(entry.montant)} F',
          style: TextStyle(
            color: isCredit ? Colors.green.shade700 : const Color(0xFF1A237E),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _invoiceTile(DossierInvoice invoice, String recipient) {
    final (title, icon, color) = switch (invoice.kind) {
      DossierInvoiceKind.client => (
        'Facture Client',
        Icons.request_quote_rounded,
        const Color(0xFF1565C0),
      ),
      DossierInvoiceKind.provider => (
        'Facture Prestataire',
        Icons.receipt_long_rounded,
        const Color(0xFF6A1B9A),
      ),
      DossierInvoiceKind.forwarder => (
        'Facture Transitaire',
        Icons.directions_boat_rounded,
        const Color(0xFF00695C),
      ),
      DossierInvoiceKind.carrier => (
        'Facture Transporteur',
        Icons.local_shipping_rounded,
        const Color(0xFFEF6C00),
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          '$title • ${invoice.reference}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$recipient • ${invoice.description.isEmpty ? 'Brouillon à compléter' : invoice.description} • ${invoice.statut}',
        ),
        trailing: Text('${formatCurrency(invoice.montant)} F'),
      ),
    );
  }

  Widget _expenseTile(Depense expense) {
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.receipt_long_rounded,
          color: Colors.redAccent,
        ),
        title: Text(
          expense.titre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Dépense ${expense.categorie} • ${expense.date}'),
        trailing: Text(
          '-${formatCurrency(expense.montant)} F',
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _closureMessage() {
    if (widget.dossier.statut == 'Clôturé') {
      return 'Dossier clôturé le ${widget.dossier.dateFin}.';
    }
    if (widget.dossier.prestataire == null) {
      return 'Clôture impossible : affectez d’abord un prestataire et complétez sa facture.';
    }
    if (widget.dossier.factureClient.statut != 'Clôturée') {
      return 'Clôture impossible : complétez et clôturez la Facture Client.';
    }
    final providerInvoice = switch (widget.dossier.prestataire!.type) {
      'Transitaire' => widget.dossier.factureTransitaire,
      'Transporteur' => widget.dossier.factureTransporteur,
      _ => widget.dossier.facturePrestataire,
    };
    if (providerInvoice.statut != 'Clôturée') {
      final invoiceName = switch (providerInvoice.kind) {
        DossierInvoiceKind.client => 'Facture Client',
        DossierInvoiceKind.provider => 'Facture Prestataire',
        DossierInvoiceKind.forwarder => 'Facture Transitaire',
        DossierInvoiceKind.carrier => 'Facture Transporteur',
      };
      return 'Clôture impossible : complétez et clôturez la $invoiceName.';
    }
    if (widget.dossier.soldeClient > 0) {
      return 'Clôture impossible : le client doit encore ${formatCurrency(widget.dossier.soldeClient)} FCFA.';
    }
    if (widget.dossier.soldePrestataire > 0) {
      return 'Clôture impossible : il reste ${formatCurrency(widget.dossier.soldePrestataire)} FCFA à payer au prestataire.';
    }
    return 'Les comptes client et prestataire sont soldés. Le dossier peut être clôturé.';
  }

  Future<void> _closeDossier() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer le dossier ?'),
        content: const Text(
          'Les comptes sont soldés. Une fois clôturé, aucun nouveau frais ou mouvement ne pourra être ajouté.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer la clôture'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !widget.dossier.peutCloturer) return;
    final previousStatus = widget.dossier.statut;
    final previousEnd = widget.dossier.dateFin;
    widget.dossier
      ..statut = 'Clôturé'
      ..dateFin = DateFormat('dd/MM/yyyy').format(DateTime.now());
    if (!await _persist(
      context,
      () => erpBackend.saveDossier(widget.dossier),
    )) {
      widget.dossier
        ..statut = previousStatus
        ..dateFin = previousEnd;
    }
    if (mounted) setState(() {});
  }

  Future<void> _addOperation() async {
    if (widget.dossier.statut == 'Clôturé') return;
    final entry = await showDialog<DossierOperation>(
      context: context,
      builder: (context) => _DossierOperationDialog(
        hasProvider: widget.dossier.prestataire != null,
        journals: widget.journals,
      ),
    );
    if (entry == null || !mounted) return;

    final dossier = widget.dossier;
    final expense = entry.type == DossierOperationType.expense
        ? Depense(
            titre: entry.titre,
            montant: entry.montant,
            categorie: entry.categorie,
            date: entry.date,
          )
        : null;
    if (expense != null) {
      dossier.depenses.add(expense);
    } else {
      dossier.operations.add(entry);
    }
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) {
      if (expense != null) {
        dossier.depenses.remove(expense);
      } else {
        dossier.operations.remove(entry);
      }
    }
    if (mounted) setState(() {});
  }
}

class _DossierOperationDialog extends StatefulWidget {
  final bool hasProvider;
  final List<JournalCode> journals;

  const _DossierOperationDialog({
    required this.hasProvider,
    required this.journals,
  });

  @override
  State<_DossierOperationDialog> createState() =>
      _DossierOperationDialogState();
}

class _DossierOperationDialogState extends State<_DossierOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  DossierOperationType _type = DossierOperationType.expense;
  String _expenseCategory = 'Douane';
  JournalCode? _journal;
  static const _expenseCategories = [
    'Douane',
    'Chauffeur',
    'Escorte',
    'Carburant',
    'Autre',
  ];

  // Les types de frais paramétrés (avec leur sous-compte) remplacent la liste par défaut.
  List<String> get _categories => _typesFrais.isEmpty
      ? _expenseCategories
      : _typesFrais.map((t) => t.libelle).toList();

  @override
  void initState() {
    super.initState();
    _expenseCategory = _categories.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = [
      DossierOperationType.expense,
      DossierOperationType.clientPayment,
      if (widget.hasProvider) ...[
        DossierOperationType.providerAdvance,
        DossierOperationType.providerPayment,
      ],
    ];
    return AlertDialog(
      title: const Text('Nouvelle opération du dossier'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<DossierOperationType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Type d’opération',
                    border: OutlineInputBorder(),
                  ),
                  items: types
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_operationLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                if (_type == DossierOperationType.expense) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _expenseCategory,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie du frais',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final type = _typesFrais
                          .where((t) => t.libelle == value)
                          .firstOrNull;
                      setState(() {
                        _expenseCategory = value;
                        // Montant par défaut du type de frais.
                        if (type != null &&
                            type.montant > 0 &&
                            _amountController.text.trim().isEmpty) {
                          _amountController.text = type.montant.toStringAsFixed(
                            0,
                          );
                        }
                        if (_titleController.text.trim().isEmpty) {
                          _titleController.text = value;
                        }
                      });
                    },
                  ),
                ],
                if (widget.journals.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<JournalCode?>(
                    isExpanded: true,
                    key: const ValueKey('operation-journal'),
                    initialValue: _journal,
                    decoration: const InputDecoration(
                      labelText: 'Code journal de caisse',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<JournalCode?>(
                        value: null,
                        child: Text('Tous / non affecté'),
                      ),
                      ...widget.journals.map(
                        (journal) => DropdownMenuItem<JournalCode?>(
                          value: journal,
                          child: Text('${journal.code} • ${journal.intitule}'),
                        ),
                      ),
                    ],
                    onChanged: (journal) => setState(() => _journal = journal),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: _type == DossierOperationType.expense
                        ? 'Description du frais'
                        : 'Référence / description',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ce champ est obligatoire'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Montant',
                    suffixText: 'FCFA',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').replaceAll(' ', '').replaceAll(',', '.'),
                    );
                    if (amount == null || amount <= 0) {
                      return 'Saisissez un montant supérieur à zéro';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(
      _amountController.text.replaceAll(' ', '').replaceAll(',', '.'),
    );
    Navigator.pop(
      context,
      DossierOperation(
        type: _type,
        titre: _titleController.text.trim(),
        categorie: _type == DossierOperationType.expense
            ? _expenseCategory
            : '',
        montant: amount,
        date: DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        codeJournal: _journal?.code ?? '',
      ),
    );
  }
}

String _operationLabel(DossierOperationType type) {
  return switch (type) {
    DossierOperationType.expense => 'Frais / dépense du dossier',
    DossierOperationType.clientInvoice => 'Facture client',
    DossierOperationType.clientPayment => 'Règlement client',
    DossierOperationType.providerInvoice => 'Facture prestataire',
    DossierOperationType.providerAdvance => 'Avance au prestataire',
    DossierOperationType.providerPayment => 'Paiement prestataire',
  };
}

IconData _operationIcon(DossierOperationType type) {
  return switch (type) {
    DossierOperationType.expense => Icons.receipt_long_rounded,
    DossierOperationType.clientInvoice => Icons.request_quote_rounded,
    DossierOperationType.clientPayment => Icons.payments_rounded,
    DossierOperationType.providerInvoice => Icons.description_rounded,
    DossierOperationType.providerAdvance =>
      Icons.account_balance_wallet_rounded,
    DossierOperationType.providerPayment => Icons.price_check_rounded,
  };
}
