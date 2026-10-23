part of '../main.dart';

// --- FRONTIÈRE, BUREAU DD, ENQUÊTE : voyages affectés, frais, validation,
// factures des agents réglées par la Direction ---

const _voyageModuleIcons = <String, IconData>{
  'Frontière': Icons.signpost_rounded,
  'Bureau DD': Icons.local_police_rounded,
  'Enquête': Icons.manage_search_rounded,
};

const _voyageModuleTitles = <String, String>{
  'Frontière': 'Agent Frontière',
  'Bureau DD': 'Bureau des Douanes (DD)',
  'Enquête': 'Enquêtes',
};

const _orange = Color(0xFFEA580C);
const _green = Color(0xFF15803D);
const _blue = Color(0xFF2563EB);

String _agentName(String id) {
  if (id.isEmpty) return '';
  return _agentsVoyage.where((a) => a.id == id).firstOrNull?.nom ??
      _erpUsers.where((u) => u.id == id).firstOrNull?.name ??
      '';
}

bool get _isVoyageResponsable {
  final user = _currentUser;
  if (user == null) return true;
  return user.role == 'Administrateur' ||
      user.accessModules.contains('Transport');
}

// La Direction règle les factures des agents.
bool get _isDirectionUser {
  final user = _currentUser;
  if (user == null) return true;
  return const {
        'Administrateur',
        'Direction',
        'Gérant',
        'Comptable',
      }.contains(user.role) ||
      user.accessModules.contains('Comptabilité');
}

bool get _seesAllVoyageWork => _isVoyageResponsable || _isDirectionUser;

// Un agent voit les voyages qui lui sont confiés et ceux sans agent désigné.
List<AffectationVoyage> _affectationsOf(String module) {
  final me = _currentUser?.id;
  return _affectationsVoyage
      .where((a) => a.module == module)
      .where((a) => _seesAllVoyageWork || a.agentId.isEmpty || a.agentId == me)
      .toList();
}

List<FactureAgent> _facturesAgentOf(String module) {
  final me = _currentUser?.id;
  return _facturesAgent
      .where((f) => f.module == module)
      .where((f) => _seesAllVoyageWork || f.agentId.isEmpty || f.agentId == me)
      .toList();
}

// Notifications d'un module pour l'utilisateur connecté, les plus utiles d'abord.
List<(String, IconData, Color)> _voyageNotifications(String module) {
  final items = <(String, IconData, Color)>[];
  final rows = _affectationsOf(module);
  for (final a in rows.where((a) => !a.estValide && !a.estSaisi)) {
    items.add((
      '$module : nouveau voyage à saisir • ${a.plaque} du ${a.dateDepart} • ${a.dossiers}',
      Icons.assignment_late_rounded,
      _orange,
    ));
  }
  for (final a in rows.where((a) => !a.estValide && a.estSaisi)) {
    items.add((
      '$module : saisie à valider • ${a.plaque} • ${a.dossiers}',
      Icons.fact_check_outlined,
      _blue,
    ));
  }
  final toBill = rows.where((a) => a.estValide && !a.estFacture).length;
  if (toBill > 0) {
    items.add((
      '$module : $toBill saisie(s) validée(s) à facturer',
      Icons.receipt_long_rounded,
      _green,
    ));
  }
  for (final f in _facturesAgentOf(module)) {
    if (f.estPayee) {
      items.add((
        'Facture ${f.reference} payée le ${f.dernierReglement} • ${_amountText(f.montant)}',
        Icons.verified_rounded,
        _green,
      ));
    } else if (_isDirectionUser) {
      items.add((
        'Facture ${f.reference} (${f.agentNom}) à régler • ${_amountText(f.reliquat)}',
        Icons.payments_outlined,
        _orange,
      ));
    }
  }
  return items;
}

// Photo du T1 prise au téléphone ou importée : redimensionnée et compressée.
Future<String?> _pickT1Photo(BuildContext context) async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  final source = await files.first.readAsBytes();
  if (source.length > _maxSourceBytes) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Image trop lourde',
        message: 'Choisissez une image de moins de 15 Mo.',
      );
    }
    return null;
  }
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Image illisible',
        message: 'Ce fichier n’est pas une image reconnue (JPEG, PNG, WebP…).',
      );
    }
    return null;
  }
  final oriented = img.bakeOrientation(decoded);
  const maxSide = 1600;
  final scaled = math.max(oriented.width, oriented.height) > maxSide
      ? (oriented.width >= oriented.height
            ? img.copyResize(oriented, width: maxSide)
            : img.copyResize(oriented, height: maxSide))
      : oriented;
  return base64Encode(img.encodeJpg(scaled, quality: 80));
}

Future<void> _showT1Photo(
  BuildContext context,
  AffectationVoyage affectation,
) async {
  String? photo;
  try {
    photo = await erpBackend.photoT1(affectation);
  } on ErpBackendException catch (error) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Photo indisponible',
        message: error.message,
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (photo == null || photo.isEmpty) {
    await _showInfoAlert(
      context,
      title: 'Pas de T1',
      message: 'Aucune photo du T1 n’est enregistrée pour ce voyage.',
    );
    return;
  }
  final bytes = base64Decode(photo);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('T1 • ${affectation.plaque} • ${affectation.dateDepart}'),
      content: SizedBox(
        width: 640,
        child: InteractiveViewer(child: Image.memory(bytes)),
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

// Affectation d'un voyage aux trois modules, avec un agent facultatif par module.
class _AffectationDialog extends StatefulWidget {
  final _VoyageRow voyage;
  final List<AffectationVoyage> existing;

  const _AffectationDialog({required this.voyage, required this.existing});

  @override
  State<_AffectationDialog> createState() => _AffectationDialogState();
}

class _AffectationDialogState extends State<_AffectationDialog> {
  late final Map<String, bool> _checked = {
    for (final m in fraisParModuleVoyage.keys)
      m: widget.existing.any((a) => a.module == m),
  };
  late final Map<String, String> _agents = {
    for (final m in fraisParModuleVoyage.keys)
      m: widget.existing.where((a) => a.module == m).firstOrNull?.agentId ?? '',
  };

  AffectationVoyage? _current(String module) =>
      widget.existing.where((a) => a.module == module).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final v = widget.voyage;
    return AlertDialog(
      title: const Text('Affecter le voyage'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${v.plaque} • ${v.dateDepart}\n${v.numerosDossier}',
                style: const TextStyle(color: _gridMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final module in fraisParModuleVoyage.keys) ...[
                _moduleTile(module),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('voyage-assign-save'),
          onPressed: () =>
              Navigator.pop(context, (checked: _checked, agents: _agents)),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _moduleTile(String module) {
    final current = _current(module);
    final locked = current != null && (current.estSaisi || current.estValide);
    final agents = _agentsVoyage
        .where((a) => a.modules.contains(module))
        .toList();
    final agent = agents.where((a) => a.id == _agents[module]).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gridBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: ValueKey('voyage-assign-$module'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _checked[module],
            secondary: Icon(_voyageModuleIcons[module], color: _gridAccent),
            title: Text(
              module,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              locked
                  ? 'Frais déjà saisis (${_amountText(current.total)}) : affectation verrouillée'
                  : [
                      if (modulesAvecT1.contains(module)) 'T1 (photo)',
                      ...fraisParModuleVoyage[module]!,
                    ].join(' • '),
              style: const TextStyle(fontSize: 12),
            ),
            onChanged: locked
                ? null
                : (value) => setState(() => _checked[module] = value ?? false),
          ),
          if (_checked[module]!)
            SearchableDropdownFormField<AgentVoyage>(
              key: ValueKey('voyage-assign-agent-$module'),
              options: agents,
              value: agent,
              label: 'Agent (facultatif)',
              emptyText: 'Aucun utilisateur avec le module $module',
              required: false,
              displayString: (a) => a.nom,
              onChanged: (a) => setState(() => _agents[module] = a?.id ?? ''),
            ),
        ],
      ),
    );
  }
}

// Ouvre l'affectation du voyage et enregistre les changements.
Future<void> _assignVoyage(BuildContext context, _VoyageRow voyage) async {
  final existing = _affectationsVoyage
      .where((a) => a.voyageCle == voyage.id)
      .toList();
  final result =
      await showDialog<
        ({Map<String, bool> checked, Map<String, String> agents})
      >(
        context: context,
        builder: (_) => _AffectationDialog(voyage: voyage, existing: existing),
      );
  if (result == null || !context.mounted) return;
  for (final module in fraisParModuleVoyage.keys) {
    final current = existing.where((a) => a.module == module).firstOrNull;
    final wanted = result.checked[module] ?? false;
    final agentId = result.agents[module] ?? '';
    if (wanted && current == null) {
      final affectation = AffectationVoyage(
        id: newLocalId('aff'),
        voyageCle: voyage.id,
        module: module,
        agentId: agentId,
        dateDepart: voyage.dateDepart,
        plaque: voyage.plaque,
        transporteur: voyage.transporteur,
        chauffeur: voyage.chauffeur,
        telephone: voyage.telephone,
        dossiers: voyage.numerosDossier,
        clients: voyage.clients,
        transitaire: voyage.transitaire,
        conteneurs: voyage.conteneurs
            .map((c) => c.numero)
            .where((n) => n.isNotEmpty)
            .join(', '),
      );
      if (!await _persist(
        context,
        () => erpBackend.saveAffectationVoyage(affectation),
      )) {
        return;
      }
      _affectationsVoyage.add(affectation);
    } else if (wanted &&
        current != null &&
        !current.estValide &&
        current.agentId != agentId) {
      final previous = current.agentId;
      current.agentId = agentId;
      if (!await _persist(
        context,
        () => erpBackend.saveAffectationVoyage(current),
      )) {
        current.agentId = previous;
        return;
      }
    } else if (!wanted &&
        current != null &&
        !current.estSaisi &&
        !current.estValide) {
      if (!await _persist(
        context,
        () => erpBackend.deleteAffectationVoyage(current),
      )) {
        return;
      }
      _affectationsVoyage.remove(current);
    }
    if (!context.mounted) return;
  }
}

Widget _voyageCard(Widget child) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _gridBorder),
  ),
  child: child,
);

Widget _voyagePageTitle(String module, String title, String subtitle) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_gridPrimary, _gridAccent]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_voyageModuleIcons[module], color: Colors.white),
    ),
    const SizedBox(width: 12),
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _gridText,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gridMuted, fontSize: 12.5),
          ),
        ],
      ),
    ),
  ],
);

Future<void> _reloadVoyageData(BuildContext context) async {
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
  }
}

// --- TABLEAU DE BORD D'UN MODULE ---

class VoyageModuleDashboard extends StatefulWidget {
  final String module;

  const VoyageModuleDashboard({super.key, required this.module});

  @override
  State<VoyageModuleDashboard> createState() => _VoyageModuleDashboardState();
}

class _VoyageModuleDashboardState extends State<VoyageModuleDashboard> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final rows = _affectationsOf(module);
    final factures = _facturesAgentOf(module);
    final todo = rows.where((a) => !a.estValide && !a.estSaisi).length;
    final toValidate = rows.where((a) => !a.estValide && a.estSaisi).length;
    final toBill = rows.where((a) => a.estValide && !a.estFacture);
    final unpaid = factures.where((f) => !f.estPayee).toList();
    final paid = factures.fold<double>(0, (s, f) => s + f.totalRegle);
    final notifications = _voyageNotifications(module);
    final now = DateTime.now();
    final thisMonth = rows.where((a) {
      final d = _parseFrDate(a.dateDepart);
      return d != null && d.year == now.year && d.month == now.month;
    }).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _voyageCard(
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _voyagePageTitle(
                  module,
                  'Tableau de bord • ${_voyageModuleTitles[module]}',
                  'Bonjour ${_currentUser?.name ?? ''} : voici vos voyages, vos saisies et vos factures.',
                ),
                IconButton.filledTonal(
                  tooltip: 'Actualiser les données',
                  onPressed: _refreshing
                      ? null
                      : () async {
                          setState(() => _refreshing = true);
                          await _reloadVoyageData(context);
                          if (mounted) setState(() => _refreshing = false);
                        },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ErpMetricTile(
                key: ValueKey('dashboard-$module-assigned'),
                label: 'Voyages affectés',
                value: '${rows.length} (ce mois : $thisMonth)',
                color: _gridAccent,
                icon: Icons.local_shipping_rounded,
              ),
              ErpMetricTile(
                key: ValueKey('dashboard-$module-todo'),
                label: 'À saisir',
                value: '$todo',
                color: _orange,
                icon: Icons.assignment_late_rounded,
              ),
              ErpMetricTile(
                label: 'À valider',
                value: '$toValidate',
                color: _blue,
                icon: Icons.fact_check_outlined,
              ),
              ErpMetricTile(
                label: 'Validés à facturer',
                value:
                    '${toBill.length} • ${_amountText(toBill.fold(0, (s, a) => s + a.total))}',
                color: _green,
                icon: Icons.receipt_long_rounded,
              ),
              ErpMetricTile(
                label: 'Factures en attente',
                value:
                    '${unpaid.length} • ${_amountText(unpaid.fold(0, (s, f) => s + f.reliquat))}',
                color: const Color(0xFFDC2626),
                icon: Icons.hourglass_bottom_rounded,
              ),
              ErpMetricTile(
                label: 'Déjà payé',
                value: _amountText(paid),
                color: _green,
                icon: Icons.verified_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              final notificationsCard = _voyageCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          color: _gridAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Notifications (${notifications.length})',
                          style: const TextStyle(
                            color: _gridText,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (notifications.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Rien à signaler pour le moment.',
                          style: TextStyle(color: _gridMuted),
                        ),
                      ),
                    for (final (text, icon, color) in notifications.take(12))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(icon, size: 17, color: color),
                        ),
                        title: Text(text),
                      ),
                  ],
                ),
              );
              final invoicesCard = _voyageCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: _gridAccent),
                        SizedBox(width: 8),
                        Text(
                          'Dernières factures',
                          style: TextStyle(
                            color: _gridText,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (factures.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Aucune facture. Cochez vos saisies validées pour en créer une.',
                          style: TextStyle(color: _gridMuted),
                        ),
                      ),
                    for (final f in factures.reversed.take(8))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${f.reference} • ${f.dateEmission}'),
                        subtitle: Text(
                          f.estPayee
                              ? 'Payée le ${f.dernierReglement}'
                              : 'Reliquat ${_amountText(f.reliquat)}',
                        ),
                        trailing: ErpStatusChip(
                          f.estPayee ? 'Payée' : 'Non payée',
                          f.estPayee ? _green : _orange,
                        ),
                      ),
                  ],
                ),
              );
              if (!wide) {
                return Column(
                  children: [
                    notificationsCard,
                    const SizedBox(height: 12),
                    invoicesCard,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: notificationsCard),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: invoicesCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- SAISIE DES FRAIS D'UN MODULE (onglets À saisir / Saisis / Validés) ---

class VoyageModulePage extends StatefulWidget {
  final String module;
  final String title;

  const VoyageModulePage({
    super.key,
    required this.module,
    required this.title,
  });

  @override
  State<VoyageModulePage> createState() => _VoyageModulePageState();
}

enum _SaisieTab { todo, saisis, valides }

class _VoyageModulePageState extends State<VoyageModulePage> {
  DateTime? _from;
  DateTime? _to;
  String _query = '';
  _SaisieTab _tab = _SaisieTab.todo;
  AffectationVoyage? _selected;
  final Set<String> _checked = {};
  bool _refreshing = false;

  List<String> get _fees => fraisParModuleVoyage[widget.module]!;
  bool get _withT1 => modulesAvecT1.contains(widget.module);

  bool _inTab(AffectationVoyage a, _SaisieTab tab) => switch (tab) {
    _SaisieTab.todo => !a.estValide && !a.estSaisi,
    _SaisieTab.saisis => !a.estValide && a.estSaisi,
    _SaisieTab.valides => a.estValide,
  };

  List<AffectationVoyage> _filter(List<AffectationVoyage> rows) {
    final query = _query.trim().toLowerCase();
    return rows.where((a) {
      if (!_inTab(a, _tab)) return false;
      if (!_inPeriod(_parseFrDate(a.dateDepart), _from, _to)) return false;
      if (query.isEmpty) return true;
      return _columns
          .map((c) => c.value(a))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList()..sort(
      (a, b) => (_parseFrDate(b.dateDepart) ?? DateTime(0)).compareTo(
        _parseFrDate(a.dateDepart) ?? DateTime(0),
      ),
    );
  }

  String _invoiceRef(AffectationVoyage a) =>
      _facturesAgent.where((f) => f.id == a.factureId).firstOrNull?.reference ??
      '';

  late final List<ErpGridColumn<AffectationVoyage>> _columns = [
    ErpGridColumn(
      label: 'Statut',
      width: 130,
      value: (a) => a.estValide
          ? (a.estFacture ? 'Facturé' : 'Validé')
          : (a.estSaisi ? 'Saisi' : 'À saisir'),
      builder: (a) => ErpStatusChip(
        a.estValide
            ? (a.estFacture ? 'Facturé' : 'Validé')
            : (a.estSaisi ? 'Saisi' : 'À saisir'),
        a.estValide ? _green : (a.estSaisi ? _blue : _orange),
      ),
    ),
    ErpGridColumn(
      label: 'Date de départ',
      width: 125,
      value: (a) => a.dateDepart,
      sortValue: (a) => _parseFrDate(a.dateDepart) ?? DateTime(0),
    ),
    ErpGridColumn(label: 'Dossier', width: 200, value: (a) => a.dossiers),
    ErpGridColumn(label: 'Client', width: 180, value: (a) => a.clients),
    ErpGridColumn(
      label: 'Transitaire',
      width: 160,
      value: (a) => a.transitaire,
    ),
    ErpGridColumn(
      label: 'Transporteur',
      width: 160,
      value: (a) => a.transporteur,
    ),
    ErpGridColumn(label: 'Camion', width: 130, value: (a) => a.plaque),
    ErpGridColumn(label: 'Chauffeur', width: 140, value: (a) => a.chauffeur),
    ErpGridColumn(
      label: 'Tél. chauffeur',
      width: 140,
      value: (a) => a.telephone,
    ),
    ErpGridColumn(label: 'Conteneurs', width: 200, value: (a) => a.conteneurs),
    if (modulesAvecT1.contains(widget.module))
      ErpGridColumn(
        label: 'T1',
        width: 90,
        value: (a) => a.aT1 ? 'Photo' : '',
        builder: (a) => a.aT1
            ? const Icon(Icons.image_rounded, color: _green, size: 20)
            : const Text('—', style: TextStyle(color: _gridMuted)),
      ),
    for (final fee in fraisParModuleVoyage[widget.module]!)
      ErpGridColumn(
        label: fee,
        width: 130,
        numeric: true,
        value: (a) => _amountText(a.frais[fee] ?? 0),
        sortValue: (a) => a.frais[fee] ?? 0,
      ),
    ErpGridColumn(
      label: 'Total',
      width: 130,
      numeric: true,
      value: (a) => _amountText(a.total),
      sortValue: (a) => a.total,
    ),
    ErpGridColumn(
      label: 'Agent',
      width: 150,
      value: (a) => _agentName(a.agentId),
    ),
    ErpGridColumn(label: 'Saisi par', width: 150, value: (a) => a.saisiPar),
    ErpGridColumn(label: 'Validé le', width: 140, value: (a) => a.valideLe),
    ErpGridColumn(label: 'Facture', width: 170, value: _invoiceRef),
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (a) => a.observations,
    ),
  ];

  // Dans l'onglet « Validés », une case à cocher par saisie pas encore facturée.
  late final _checkColumn = ErpGridColumn<AffectationVoyage>(
    label: '✓',
    width: 56,
    value: (a) => _checked.contains(a.id) ? 'x' : '',
    builder: (a) => a.estFacture
        ? const Icon(Icons.lock_outline_rounded, size: 18, color: _gridMuted)
        : Checkbox(
            key: ValueKey('voyage-check-${a.id}'),
            value: _checked.contains(a.id),
            onChanged: (value) => setState(() {
              if (value ?? false) {
                _checked.add(a.id);
              } else {
                _checked.remove(a.id);
              }
            }),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final all = _affectationsOf(widget.module);
    final rows = _filter(all);
    final selected = rows.where((a) => a.id == _selected?.id).firstOrNull;
    _checked.removeWhere(
      (id) => !rows.any((a) => a.id == id && a.estValide && !a.estFacture),
    );
    final counts = {
      for (final tab in _SaisieTab.values)
        tab: all.where((a) => _inTab(a, tab)).length,
    };
    final total = rows.fold<double>(0, (s, a) => s + a.total);
    final columns = _tab == _SaisieTab.valides
        ? [_checkColumn, ..._columns]
        : _columns;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(constraints.maxWidth >= 1000 ? 18 : 10),
          children: [
            _buildToolbar(selected, rows),
            const SizedBox(height: 12),
            _buildFilters(rows.length, counts, total),
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(480, constraints.maxHeight - 280),
              child: ErpGrid<AffectationVoyage>(
                key: ValueKey('voyage-module-grid-${widget.module}'),
                columns: columns,
                rows: rows,
                rowId: (a) => a.id,
                filterable: true,
                selected: selected,
                onSelect: (a) => setState(() => _selected = a),
                onOpen: (a) => a.estValide ? _showDetails(a) : _editFees(a),
                emptyIcon: _voyageModuleIcons[widget.module]!,
                emptyText: all.isEmpty
                    ? 'Aucun voyage affecté. Le responsable affecte les voyages depuis Transport > Voyages.'
                    : 'Aucun voyage dans cet onglet.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(
    AffectationVoyage? selected,
    List<AffectationVoyage> rows,
  ) {
    final editable = selected != null && !selected.estValide;
    final toBill = rows
        .where((a) => _checked.contains(a.id) && !a.estFacture)
        .toList();
    return _voyageCard(
      Wrap(
        spacing: 8,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _voyagePageTitle(
            widget.module,
            widget.title,
            selected == null
                ? 'Saisie des frais : ${[if (_withT1) 'T1 (photo)', ..._fees].join(', ')}'
                : '${selected.plaque} • ${selected.dateDepart} • ${selected.dossiers}',
          ),
          const SizedBox(width: 12),
          ErpActionButton(
            key: const ValueKey('voyage-fees-edit'),
            label: 'Saisir les frais',
            icon: Icons.edit_note_rounded,
            primary: true,
            onPressed: editable ? () => _editFees(selected) : null,
          ),
          ErpActionButton(
            key: const ValueKey('voyage-validate'),
            label: 'Valider',
            icon: Icons.verified_rounded,
            color: _green,
            onPressed: editable && selected.estSaisi
                ? () => _validate(selected)
                : null,
          ),
          if (_withT1)
            ErpActionButton(
              label: 'Voir le T1',
              icon: Icons.image_outlined,
              onPressed: selected != null && selected.aT1
                  ? () => _showT1Photo(context, selected)
                  : null,
            ),
          if (_tab == _SaisieTab.valides) ...[
            ErpActionButton(
              key: const ValueKey('voyage-check-all'),
              label: 'Tout cocher',
              icon: Icons.done_all_rounded,
              onPressed: () => setState(() {
                _checked.addAll(
                  rows.where((a) => !a.estFacture).map((a) => a.id),
                );
              }),
            ),
            ErpActionButton(
              key: const ValueKey('voyage-create-invoice'),
              label: 'Créer la facture (${toBill.length})',
              icon: Icons.receipt_long_rounded,
              primary: true,
              color: _green,
              onPressed: toBill.isEmpty ? null : () => _createInvoice(toBill),
            ),
          ],
          ErpActionButton(
            label: 'Exporter',
            icon: Icons.file_download_outlined,
            onPressed: () => _exportGrid(
              context,
              baseName: widget.module.toLowerCase().replaceAll(' ', '_'),
              columns: _columns,
              rows: rows,
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Actualiser les données',
            onPressed: _refreshing
                ? null
                : () async {
                    setState(() => _refreshing = true);
                    await _reloadVoyageData(context);
                    if (mounted) {
                      setState(() {
                        _refreshing = false;
                        _selected = null;
                      });
                    }
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(int count, Map<_SaisieTab, int> counts, double total) =>
      _voyageCard(
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_SaisieTab>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _SaisieTab.todo,
                  label: Text(
                    'À saisir (${counts[_SaisieTab.todo]})',
                    key: const ValueKey('voyage-tab-todo'),
                  ),
                ),
                ButtonSegment(
                  value: _SaisieTab.saisis,
                  label: Text(
                    'Saisis (${counts[_SaisieTab.saisis]})',
                    key: const ValueKey('voyage-tab-saisis'),
                  ),
                ),
                ButtonSegment(
                  value: _SaisieTab.valides,
                  label: Text(
                    'Validés (${counts[_SaisieTab.valides]})',
                    key: const ValueKey('voyage-tab-valides'),
                  ),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() {
                _tab = value.first;
                _selected = null;
              }),
            ),
            ErpDateFilter(
              label: 'Période du',
              value: _from,
              onChanged: (value) => setState(() => _from = value),
            ),
            ErpDateFilter(
              label: 'Au',
              value: _to,
              onChanged: (value) => setState(() => _to = value),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Recherche…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count voyage(s) • ${_amountText(total)}',
                key: ValueKey('voyage-module-count-${widget.module}'),
                style: const TextStyle(
                  color: Color(0xFFC2410C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _showDetails(AffectationVoyage a) => _showInfoAlert(
    context,
    title: 'Saisie validée',
    message:
        'Validée le ${a.valideLe} par ${a.validePar}. Total ${_amountText(a.total)}.'
        '${a.estFacture ? ' Facture ${_invoiceRef(a)}.' : ''}\nUne saisie validée ne peut plus être modifiée.',
  );

  Future<void> _editFees(AffectationVoyage affectation) async {
    if (affectation.estValide) return _showDetails(affectation);
    final result = await showDialog<_FraisResult>(
      context: context,
      builder: (_) => _FraisVoyageDialog(affectation: affectation),
    );
    if (result == null || !mounted) return;
    final previous = (
      affectation.frais,
      affectation.observations,
      affectation.aT1,
    );
    affectation
      ..frais = result.frais
      ..observations = result.observations
      ..t1Image = result.t1Image;
    final ok = await _persist(
      context,
      () => erpBackend.saveAffectationVoyage(
        affectation,
        valider: result.valider,
      ),
    );
    if (!ok) {
      affectation
        ..frais = previous.$1
        ..observations = previous.$2
        ..aT1 = previous.$3
        ..t1Image = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _validate(AffectationVoyage affectation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Valider la saisie ?'),
        content: Text(
          '${affectation.plaque} • ${affectation.dossiers}\nTotal ${_amountText(affectation.total)}'
          '${_withT1 ? (affectation.aT1 ? ' • T1 joint' : ' • sans T1') : ''}\n\n'
          'Une fois validée, la saisie ne pourra plus être modifiée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('voyage-validate-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _persist(
      context,
      () => erpBackend.saveAffectationVoyage(affectation, valider: true),
    );
    if (mounted) setState(() {});
  }

  Future<void> _createInvoice(List<AffectationVoyage> lines) async {
    final agentIds = lines.map((a) => a.agentId).toSet();
    final me = _currentUser;
    final agentId = agentIds.length == 1 && agentIds.first.isNotEmpty
        ? agentIds.first
        : (me?.id ?? '');
    final now = DateTime.now();
    final reference = _nextInvoiceNumber(
      prefixeFactureAgent[widget.module]!,
      _facturesAgent.map((f) => f.reference),
      now,
    );
    final confirmed = await showDialog<String>(
      context: context,
      builder: (_) => _NewAgentInvoiceDialog(
        reference: reference,
        count: lines.length,
        total: lines.fold(0, (s, a) => s + a.total),
        agent: _agentName(agentId).isEmpty
            ? (me?.name ?? '')
            : _agentName(agentId),
      ),
    );
    if (confirmed == null || !mounted) return;
    final facture = FactureAgent(
      id: newLocalId('fag'),
      reference: reference,
      module: widget.module,
      agentId: agentId,
      agentNom: _agentName(agentId).isEmpty
          ? (me?.name ?? '')
          : _agentName(agentId),
      dateEmission: DateFormat('dd/MM/yyyy').format(now),
      observations: confirmed,
      affectations: lines.map((a) => a.id).toList(),
      auteur: me?.name ?? '',
    );
    if (!await _persist(context, () => erpBackend.saveFactureAgent(facture))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _facturesAgent.add(facture);
      for (final a in lines) {
        a.factureId = facture.id;
      }
      _checked.clear();
    });
    final print = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Facture créée'),
        content: Text(
          'La facture ${facture.reference} (${_amountText(facture.montant)}) est créée. Elle sera réglée par la Direction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Imprimer en PDF'),
          ),
        ],
      ),
    );
    if (print == true) await _printFactureAgent(facture);
  }
}

class _NewAgentInvoiceDialog extends StatefulWidget {
  final String reference;
  final int count;
  final double total;
  final String agent;

  const _NewAgentInvoiceDialog({
    required this.reference,
    required this.count,
    required this.total,
    required this.agent,
  });

  @override
  State<_NewAgentInvoiceDialog> createState() => _NewAgentInvoiceDialogState();
}

class _NewAgentInvoiceDialogState extends State<_NewAgentInvoiceDialog> {
  final _observations = TextEditingController();

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle facture'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'N° ${widget.reference}\nAgent : ${widget.agent}\n'
            '${widget.count} saisie(s) validée(s) • ${_amountText(widget.total)}',
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _observations,
            maxLines: 2,
            decoration: _inputDecoration(
              'Observations',
              icon: Icons.notes_rounded,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        key: const ValueKey('agent-invoice-confirm'),
        onPressed: () => Navigator.pop(context, _observations.text.trim()),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Créer la facture'),
      ),
    ],
  );
}

typedef _FraisResult = ({
  Map<String, double> frais,
  String observations,
  String? t1Image,
  bool valider,
});

// Saisie des frais d'un module : informations du voyage en lecture,
// photo du T1 (Frontière) et montants à saisir.
class _FraisVoyageDialog extends StatefulWidget {
  final AffectationVoyage affectation;

  const _FraisVoyageDialog({required this.affectation});

  @override
  State<_FraisVoyageDialog> createState() => _FraisVoyageDialogState();
}

class _FraisVoyageDialogState extends State<_FraisVoyageDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _amounts = {
    for (final fee in fraisParModuleVoyage[widget.affectation.module]!)
      fee: TextEditingController(
        text: (widget.affectation.frais[fee] ?? 0) == 0
            ? ''
            : widget.affectation.frais[fee]!.toStringAsFixed(0),
      ),
  };
  late final _observations = TextEditingController(
    text: widget.affectation.observations,
  );
  // null : photo inchangée ; '' : retirée ; sinon nouvelle photo.
  String? _t1;

  bool get _withT1 => modulesAvecT1.contains(widget.affectation.module);
  bool get _hasT1 => _t1 == null ? widget.affectation.aT1 : _t1!.isNotEmpty;

  @override
  void dispose() {
    for (final c in [..._amounts.values, _observations]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _amounts.values.fold(0, (s, c) => s + (_parseAmount(c.text) ?? 0));

  void _close({required bool valider}) {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop<_FraisResult>(context, (
      frais: {
        for (final entry in _amounts.entries)
          if ((_parseAmount(entry.value.text) ?? 0) > 0)
            entry.key: _parseAmount(entry.value.text)!,
      },
      observations: _observations.text.trim(),
      t1Image: _t1,
      valider: valider,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.affectation;
    Widget info(String label, String value) => SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _gridMuted, fontSize: 11.5),
          ),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              color: _gridText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      title: Text('${a.module} • saisie des frais'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: [
                      info('Dossier', a.dossiers),
                      info('Transitaire', a.transitaire),
                      info('Transporteur', a.transporteur),
                      info('Camion', a.plaque),
                      info('Chauffeur', a.chauffeur),
                      info('Tél. chauffeur', a.telephone),
                    ],
                  ),
                ),
                if (_withT1) ...[const SizedBox(height: 14), _buildT1()],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in _amounts.entries)
                      SizedBox(
                        width: 250,
                        child: TextFormField(
                          key: ValueKey('voyage-fee-${entry.key}'),
                          controller: entry.value,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            entry.key,
                            icon: Icons.payments_outlined,
                          ).copyWith(suffixText: 'F'),
                          validator: (value) {
                            final amount = _parseAmount(value ?? '');
                            return amount == null || amount < 0
                                ? 'Montant invalide'
                                : null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observations,
                  maxLines: 2,
                  decoration: _inputDecoration(
                    'Observations',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total : ${_amountText(_total)}',
                  key: const ValueKey('voyage-fees-total'),
                  style: const TextStyle(
                    color: _gridPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
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
        OutlinedButton.icon(
          key: const ValueKey('voyage-fees-save'),
          onPressed: () => _close(valider: false),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
        FilledButton.icon(
          key: const ValueKey('voyage-fees-validate'),
          style: FilledButton.styleFrom(backgroundColor: _green),
          onPressed: _total > 0 || _hasT1 ? () => _close(valider: true) : null,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Enregistrer et valider'),
        ),
      ],
    );
  }

  Widget _buildT1() {
    final photo = _t1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gridBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3FB),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo != null && photo.isNotEmpty
                ? Image.memory(base64Decode(photo), fit: BoxFit.cover)
                : Icon(
                    _hasT1 ? Icons.image_rounded : Icons.add_a_photo_outlined,
                    size: 34,
                    color: _hasT1 ? _green : _gridMuted,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'T1 (photo du document)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _hasT1
                      ? 'Photo jointe.'
                      : 'Prenez une photo avec le téléphone ou importez une image.',
                  style: const TextStyle(color: _gridMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('voyage-t1-pick'),
                      onPressed: () async {
                        final picked = await _pickT1Photo(context);
                        if (picked != null && mounted) {
                          setState(() => _t1 = picked);
                        }
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(_hasT1 ? 'Remplacer' : 'Photo / image'),
                    ),
                    if (_hasT1)
                      TextButton.icon(
                        onPressed: () => setState(() => _t1 = ''),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Retirer'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FACTURES DES AGENTS (création côté agent, règlement par la Direction) ---

class FacturesAgentPage extends StatefulWidget {
  final String module;
  final List<JournalCode> journals;
  final List<ModeReglement> modes;

  const FacturesAgentPage({
    super.key,
    required this.module,
    required this.journals,
    required this.modes,
  });

  @override
  State<FacturesAgentPage> createState() => _FacturesAgentPageState();
}

class _FacturesAgentPageState extends State<FacturesAgentPage> {
  FactureAgent? _selected;
  ReglementFacture? _selectedPayment;
  _PaidFilter _paid = _PaidFilter.all;
  String _query = '';

  late final List<ErpGridColumn<FactureAgent>> _columns = [
    ErpGridColumn(
      label: 'Statut',
      width: 120,
      value: (f) => f.estPayee ? 'Payée' : 'Non payée',
      builder: (f) => ErpStatusChip(
        f.estPayee ? 'Payée' : 'Non payée',
        f.estPayee ? _green : _orange,
      ),
    ),
    ErpGridColumn(label: 'Référence', width: 170, value: (f) => f.reference),
    ErpGridColumn(
      label: 'Date',
      width: 110,
      value: (f) => f.dateEmission,
      sortValue: (f) => _parseFrDate(f.dateEmission) ?? DateTime(0),
    ),
    ErpGridColumn(label: 'Agent', width: 170, value: (f) => f.agentNom),
    ErpGridColumn(
      label: 'Saisies',
      width: 90,
      numeric: true,
      value: (f) => '${f.affectations.length}',
      sortValue: (f) => f.affectations.length,
    ),
    ErpGridColumn(
      label: 'Montant',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.montant),
      sortValue: (f) => f.montant,
    ),
    ErpGridColumn(
      label: 'Réglé',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.totalRegle),
      sortValue: (f) => f.totalRegle,
    ),
    ErpGridColumn(
      label: 'Reliquat',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.reliquat),
      sortValue: (f) => f.reliquat,
    ),
    ErpGridColumn(
      label: 'Payée le',
      width: 110,
      value: (f) => f.estPayee ? f.dernierReglement : '',
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (f) => f.observations,
    ),
  ];

  List<AffectationVoyage> _linesOf(FactureAgent f) =>
      _affectationsVoyage.where((a) => f.affectations.contains(a.id)).toList();

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final all = _facturesAgentOf(widget.module);
    final rows = all.where((f) {
      if (_paid == _PaidFilter.paid && !f.estPayee) return false;
      if (_paid == _PaidFilter.unpaid && f.estPayee) return false;
      if (query.isEmpty) return true;
      return _columns
          .map((c) => c.value(f))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList()..sort((a, b) => b.numero.compareTo(a.numero));
    final selected = rows.where((f) => f.id == _selected?.id).firstOrNull;
    final reliquat = rows.fold<double>(0, (s, f) => s + f.reliquat);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _voyageCard(
            Wrap(
              spacing: 8,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _voyagePageTitle(
                  widget.module,
                  'Factures • ${_voyageModuleTitles[widget.module]}',
                  _isDirectionUser
                      ? 'La Direction enregistre ici le règlement des agents.'
                      : 'Vos factures et leur règlement par la Direction.',
                ),
                const SizedBox(width: 12),
                ErpActionButton(
                  key: const ValueKey('agent-invoice-print'),
                  label: 'Imprimer PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  primary: true,
                  onPressed: selected == null
                      ? null
                      : () => _printFactureAgent(selected),
                ),
                ErpActionButton(
                  label: 'Supprimer',
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFDC2626),
                  onPressed: selected == null || selected.reglements.isNotEmpty
                      ? null
                      : () => _delete(selected),
                ),
                ErpActionButton(
                  label: 'Exporter',
                  icon: Icons.file_download_outlined,
                  onPressed: () => _exportGrid(
                    context,
                    baseName: 'factures_${widget.module.toLowerCase()}',
                    columns: _columns,
                    rows: rows,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _voyageCard(
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_PaidFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _PaidFilter.all,
                      label: Text('Toutes'),
                    ),
                    ButtonSegment(
                      value: _PaidFilter.unpaid,
                      label: Text('Non payées'),
                    ),
                    ButtonSegment(
                      value: _PaidFilter.paid,
                      label: Text('Payées'),
                    ),
                  ],
                  selected: {_paid},
                  onSelectionChanged: (value) =>
                      setState(() => _paid = value.first),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Recherche…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                Text(
                  '${rows.length} facture(s) • reliquat ${_amountText(reliquat)}',
                  key: ValueKey('agent-invoices-count-${widget.module}'),
                  style: const TextStyle(
                    color: Color(0xFFC2410C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: ErpGrid<FactureAgent>(
              key: ValueKey('agent-invoices-grid-${widget.module}'),
              columns: _columns,
              rows: rows,
              rowId: (f) => f.id,
              filterable: true,
              selected: selected,
              onSelect: (f) => setState(() {
                _selected = f;
                _selectedPayment = null;
              }),
              emptyIcon: Icons.receipt_long_outlined,
              emptyText:
                  'Aucune facture. Dans « ${_voyageModuleTitles[widget.module]} », onglet Validés, cochez les saisies puis « Créer la facture ».',
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            _buildDetails(selected),
            const SizedBox(height: 12),
            _buildPayments(selected),
          ],
        ],
      ),
    );
  }

  Widget _buildDetails(FactureAgent f) {
    final fees = fraisParModuleVoyage[f.module]!;
    final withT1 = modulesAvecT1.contains(f.module);
    return _voyageCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saisies de la facture ${f.reference}',
            style: const TextStyle(
              color: _gridText,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ErpGrid<AffectationVoyage>(
              key: const ValueKey('agent-invoice-lines'),
              columns: [
                ErpGridColumn(
                  label: 'Date de départ',
                  width: 120,
                  value: (a) => a.dateDepart,
                ),
                ErpGridColumn(
                  label: 'Dossier',
                  width: 190,
                  value: (a) => a.dossiers,
                ),
                ErpGridColumn(
                  label: 'Camion',
                  width: 120,
                  value: (a) => a.plaque,
                ),
                ErpGridColumn(
                  label: 'Transporteur',
                  width: 150,
                  value: (a) => a.transporteur,
                ),
                if (withT1)
                  ErpGridColumn(
                    label: 'T1',
                    width: 80,
                    value: (a) => a.aT1 ? 'Oui' : 'Non',
                  ),
                for (final fee in fees)
                  ErpGridColumn(
                    label: fee,
                    width: 130,
                    numeric: true,
                    value: (a) => _amountText(a.frais[fee] ?? 0),
                  ),
                ErpGridColumn(
                  label: 'Total',
                  width: 130,
                  numeric: true,
                  value: (a) => _amountText(a.total),
                ),
              ],
              rows: _linesOf(f),
              rowId: (a) => a.id,
              onOpen: withT1 ? (a) => _showT1Photo(context, a) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayments(FactureAgent f) => _voyageCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Règlements (Direction)',
              style: TextStyle(
                color: _gridText,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isDirectionUser) ...[
              FilledButton.icon(
                key: const ValueKey('agent-payment-new'),
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: f.estPayee ? null : () => _addPayment(f),
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Nouveau paiement'),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPayment == null
                    ? null
                    : () => _deletePayment(f, _selectedPayment!),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Supprimer'),
              ),
            ] else
              Text(
                f.estPayee
                    ? 'Payée le ${f.dernierReglement}.'
                    : 'En attente du règlement par la Direction.',
                style: const TextStyle(color: _gridMuted),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ErpGrid<ReglementFacture>(
            key: const ValueKey('agent-payments-grid'),
            columns: [
              ErpGridColumn(label: 'Date', width: 150, value: (r) => r.date),
              ErpGridColumn(
                label: 'Montant',
                width: 130,
                numeric: true,
                value: (r) => _amountText(r.montant),
              ),
              ErpGridColumn(
                label: 'Caisse',
                width: 180,
                value: (r) {
                  final j = widget.journals
                      .where((j) => j.code == r.codeJournal)
                      .firstOrNull;
                  return j == null
                      ? r.codeJournal
                      : '${j.code} • ${j.intitule}';
                },
              ),
              ErpGridColumn(
                label: 'Mode',
                width: 150,
                value: (r) => r.modePaiement,
              ),
              ErpGridColumn(
                label: 'Saisi par',
                width: 150,
                value: (r) => r.auteur,
              ),
              ErpGridColumn(
                label: 'Observations',
                width: 220,
                value: (r) => r.observations,
              ),
            ],
            rows: f.reglements,
            rowId: (r) => r.id,
            selected: _selectedPayment,
            onSelect: (r) => setState(() => _selectedPayment = r),
            emptyText: 'Aucun règlement.',
          ),
        ),
      ],
    ),
  );

  Future<void> _addPayment(FactureAgent f) async {
    if (widget.journals.isEmpty && widget.modes.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Caisse requise',
        message: 'Créez d’abord une caisse dans Comptabilité > Code journaux.',
      );
      return;
    }
    final operation = await showDialog<DossierOperation>(
      context: context,
      builder: (context) => _PaymentDialog(
        journals: widget.journals,
        modes: widget.modes,
        balance: f.reliquat,
        invoiceReference: f.reference,
      ),
    );
    if (operation == null || !mounted) return;
    final payment = ReglementFacture(
      date: operation.date,
      montant: operation.montant,
      codeJournal: operation.codeJournal,
      modePaiement: operation.modePaiement,
      numeroCheque: operation.numeroCheque,
      observations: operation.observations,
      auteur: operation.auteur,
      saisiLe: operation.saisiLe,
    );
    f.reglements.add(payment);
    if (!await _persist(context, () => erpBackend.saveFactureAgent(f))) {
      f.reglements.remove(payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _deletePayment(FactureAgent f, ReglementFacture payment) async {
    final index = f.reglements.indexOf(payment);
    if (index < 0) return;
    f.reglements.removeAt(index);
    if (!await _persist(context, () => erpBackend.saveFactureAgent(f))) {
      f.reglements.insert(index, payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _delete(FactureAgent f) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la facture ?'),
        content: Text(
          'La facture ${f.reference} sera supprimée ; ses ${f.affectations.length} saisie(s) redeviendront à facturer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _persist(context, () => erpBackend.deleteFactureAgent(f))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _facturesAgent.remove(f);
      for (final a in _affectationsVoyage.where((a) => a.factureId == f.id)) {
        a.factureId = '';
      }
      _selected = null;
    });
  }
}

// Facture PDF d'un agent : toutes ses saisies, le total et les règlements.
Future<void> _printFactureAgent(FactureAgent f) async {
  final logo = await _loadPdfLogo();
  final lines = _affectationsVoyage
      .where((a) => f.affectations.contains(a.id))
      .toList();
  final fees = fraisParModuleVoyage[f.module]!;
  final withT1 = modulesAvecT1.contains(f.module);
  final doc = pw.Document(
    title: 'Facture ${f.reference}',
    author: 'Sylla Transit & Transport',
  );
  final headers = [
    'Départ',
    'Dossier',
    'Client',
    'Transitaire',
    'Transporteur',
    'Camion',
    'Chauffeur',
    'Tél.',
    if (withT1) 'T1',
    ...fees,
    'Total',
  ];
  final numeric = {
    for (var i = headers.length - fees.length - 1; i < headers.length; i++) i,
  };
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 40),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'STT',
                  style: pw.TextStyle(
                    color: _pdfPrimary,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'SYLLA TRANSIT & TRANSPORT',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  'Agent : ${f.agentNom}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'FACTURE ${f.module.toUpperCase()}',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'N° ${f.reference} du ${f.dateEmission}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.Text(
                  f.estPayee
                      ? 'SOLDÉE le ${f.dernierReglement}'
                      : 'Non soldée • reliquat ${formatCurrency(f.reliquat)} FCFA',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: f.estPayee
                        ? PdfColors.green800
                        : PdfColors.orange800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sylla Transit & Transport  |  Page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        _pdfTable(
          headers,
          [
            for (final a in lines)
              [
                a.dateDepart,
                a.dossiers,
                a.clients,
                a.transitaire,
                a.transporteur,
                a.plaque,
                a.chauffeur,
                a.telephone,
                if (withT1) a.aT1 ? 'Oui' : 'Non',
                for (final fee in fees) formatCurrency(a.frais[fee] ?? 0),
                formatCurrency(a.total),
              ],
          ],
          numericColumns: numeric,
          fontSize: 7.5,
        ),
        pw.SizedBox(height: 12),
        _pdfTotals([
          for (final fee in fees)
            (
              fee,
              '${formatCurrency(lines.fold<double>(0, (s, a) => s + (a.frais[fee] ?? 0)))} FCFA',
            ),
          ('Total facture', '${formatCurrency(f.montant)} FCFA'),
          ('Total payé', '${formatCurrency(f.totalRegle)} FCFA'),
          ('Reliquat', '${formatCurrency(f.reliquat)} FCFA'),
        ]),
        if (f.reglements.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Règlements de la Direction',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          _pdfTable(
            ['Date', 'Montant', 'Caisse', 'Mode', 'Saisi par'],
            [
              for (final r in f.reglements)
                [
                  r.date,
                  formatCurrency(r.montant),
                  r.codeJournal,
                  r.modePaiement,
                  r.auteur,
                ],
            ],
            numericColumns: {1},
            fontSize: 8,
          ),
        ],
        if (f.observations.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Observations : ${f.observations}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ],
    ),
  );
  await Printing.layoutPdf(
    name: 'Facture ${f.reference}',
    format: PdfPageFormat.a4.landscape,
    onLayout: (_) => doc.save(),
  );
}
