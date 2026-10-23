part of '../main.dart';

// --- FRONTIÈRE, BUREAU DD, ENQUÊTE : voyages affectés et frais de chaque agent ---

const _voyageModuleIcons = <String, IconData>{
  'Frontière': Icons.signpost_rounded,
  'Bureau DD': Icons.local_police_rounded,
  'Enquête': Icons.manage_search_rounded,
};

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
    final locked = current?.estSaisi ?? false;
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
                  ? 'Frais déjà saisis (${_amountText(current!.total)}) : affectation verrouillée'
                  : fraisParModuleVoyage[module]!.join(' • '),
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
    } else if (wanted && current != null && current.agentId != agentId) {
      final previous = current.agentId;
      current.agentId = agentId;
      if (!await _persist(
        context,
        () => erpBackend.saveAffectationVoyage(current),
      )) {
        current.agentId = previous;
        return;
      }
    } else if (!wanted && current != null && !current.estSaisi) {
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

// Page d'un module : voyages qui lui sont affectés et saisie de ses frais.
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

enum _SaisieFilter { all, todo, done }

class _VoyageModulePageState extends State<VoyageModulePage> {
  DateTime? _from;
  DateTime? _to;
  String _query = '';
  _SaisieFilter _saisie = _SaisieFilter.all;
  AffectationVoyage? _selected;
  bool _refreshing = false;

  List<String> get _fees => fraisParModuleVoyage[widget.module]!;

  // Un agent voit les voyages qui lui sont confiés et ceux sans agent désigné.
  List<AffectationVoyage> get _visible {
    final me = _currentUser?.id;
    return _affectationsVoyage
        .where((a) => a.module == widget.module)
        .where(
          (a) => _isVoyageResponsable || a.agentId.isEmpty || a.agentId == me,
        )
        .toList();
  }

  List<AffectationVoyage> _filter(List<AffectationVoyage> rows) {
    final query = _query.trim().toLowerCase();
    return rows.where((a) {
      if (!_inPeriod(_parseFrDate(a.dateDepart), _from, _to)) return false;
      if (_saisie == _SaisieFilter.todo && a.estSaisi) return false;
      if (_saisie == _SaisieFilter.done && !a.estSaisi) return false;
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

  late final List<ErpGridColumn<AffectationVoyage>> _columns = [
    ErpGridColumn(
      label: 'Statut',
      width: 120,
      value: (a) => a.estSaisi ? 'Saisi' : 'À saisir',
      builder: (a) => ErpStatusChip(
        a.estSaisi ? 'Saisi' : 'À saisir',
        a.estSaisi ? const Color(0xFF15803D) : const Color(0xFFEA580C),
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
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (a) => a.observations,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final all = _visible;
    final rows = _filter(all);
    final selected = rows.where((a) => a.id == _selected?.id).firstOrNull;
    final total = rows.fold<double>(0, (s, a) => s + a.total);
    final todo = rows.where((a) => !a.estSaisi).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(constraints.maxWidth >= 1000 ? 18 : 10),
          children: [
            _buildToolbar(selected, rows),
            const SizedBox(height: 12),
            _buildFilters(rows.length, todo, total),
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(480, constraints.maxHeight - 280),
              child: ErpGrid<AffectationVoyage>(
                key: ValueKey('voyage-module-grid-${widget.module}'),
                columns: _columns,
                rows: rows,
                rowId: (a) => a.id,
                filterable: true,
                selected: selected,
                onSelect: (a) => setState(() => _selected = a),
                onOpen: _editFees,
                emptyIcon: _voyageModuleIcons[widget.module]!,
                emptyText: all.isEmpty
                    ? 'Aucun voyage affecté. Le responsable affecte les voyages depuis Transport > Voyages.'
                    : 'Aucun voyage ne correspond aux filtres.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: child,
  );

  Widget _buildToolbar(
    AffectationVoyage? selected,
    List<AffectationVoyage> rows,
  ) => _card(
    Wrap(
      spacing: 8,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_gridPrimary, _gridAccent],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _voyageModuleIcons[widget.module],
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: _gridText,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    selected == null
                        ? 'Saisie des frais : ${_fees.join(', ')}'
                        : '${selected.plaque} • ${selected.dateDepart} • ${selected.dossiers}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _gridMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        ErpActionButton(
          key: const ValueKey('voyage-fees-edit'),
          label: 'Saisir les frais',
          icon: Icons.edit_note_rounded,
          primary: true,
          onPressed: selected == null ? null : () => _editFees(selected),
        ),
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
          onPressed: _refreshing ? null : _refresh,
          icon: _refreshing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );

  Widget _buildFilters(int count, int todo, double total) => _card(
    Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
        SegmentedButton<_SaisieFilter>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _SaisieFilter.all, label: Text('Tous')),
            ButtonSegment(value: _SaisieFilter.todo, label: Text('À saisir')),
            ButtonSegment(value: _SaisieFilter.done, label: Text('Saisis')),
          ],
          selected: {_saisie},
          onSelectionChanged: (value) => setState(() => _saisie = value.first),
        ),
        SizedBox(
          width: 260,
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
            '$count voyage(s) • $todo à saisir • ${_amountText(total)}',
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

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      _loadErpData(await erpBackend.reload());
      _selected = null;
    } on ErpBackendException catch (error) {
      if (mounted) {
        await _showInfoAlert(
          context,
          title: 'Actualisation impossible',
          message: error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _editFees(AffectationVoyage affectation) async {
    final result = await showDialog<(Map<String, double>, String)>(
      context: context,
      builder: (_) => _FraisVoyageDialog(affectation: affectation),
    );
    if (result == null || !mounted) return;
    final previous = (affectation.frais, affectation.observations);
    affectation
      ..frais = result.$1
      ..observations = result.$2;
    if (!await _persist(
      context,
      () => erpBackend.saveAffectationVoyage(affectation),
    )) {
      affectation
        ..frais = previous.$1
        ..observations = previous.$2;
    }
    if (mounted) setState(() {});
  }
}

// Saisie des frais d'un module : informations du voyage en lecture, montants à saisir.
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

  @override
  void dispose() {
    for (final c in [..._amounts.values, _observations]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _amounts.values.fold(0, (s, c) => s + (_parseAmount(c.text) ?? 0));

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
        width: 520,
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
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in _amounts.entries)
                      SizedBox(
                        width: 240,
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
        FilledButton.icon(
          key: const ValueKey('voyage-fees-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              {
                for (final entry in _amounts.entries)
                  if ((_parseAmount(entry.value.text) ?? 0) > 0)
                    entry.key: _parseAmount(entry.value.text)!,
              },
              _observations.text.trim(),
            ));
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
