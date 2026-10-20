part of '../main.dart';

// --- VOYAGES : camions partis, construits depuis les factures transitaire ---

class _VoyageContainer {
  final String bl;
  final String numero;
  final String marchandise;

  const _VoyageContainer(this.bl, this.numero, this.marchandise);
}

// Un voyage : un camion parti à une date avec jusqu'à trois conteneurs d'un dossier.
class _VoyageRow {
  final String id;
  int numero = 0;
  final TransitDossier? dossier;
  final String transitaire;
  final String dateDepart;
  final String transporteur;
  final String plaque;
  final String chauffeur;
  final String telephone;
  final List<_VoyageContainer> conteneurs;
  final String description;
  final String origine;
  final Voyage? saisie;

  _VoyageRow({
    required this.id,
    required this.dossier,
    required this.transitaire,
    required this.dateDepart,
    required this.transporteur,
    required this.plaque,
    required this.chauffeur,
    required this.telephone,
    required this.conteneurs,
    required this.description,
    required this.origine,
    this.saisie,
  });

  DateTime? get date => _parseFrDate(dateDepart);

  _VoyageContainer? conteneur(int index) =>
      index < conteneurs.length ? conteneurs[index] : null;
}

List<_VoyageRow> _buildVoyages({
  required List<TransitDossier> dossiers,
  required List<Prestataire> prestataires,
  required List<FactureTransitaire> factures,
  required List<Voyage> voyages,
}) {
  final dossierById = {for (final d in dossiers) d.id: d};
  final partnerById = {for (final p in prestataires) p.id: p};
  // Propriétaire et chauffeur de chaque camion enregistré.
  final trucks = <String, (Prestataire, Vehicule)>{
    for (final p in prestataires)
      for (final v in p.vehicules) _normalizePlate(v.plaque): (p, v),
  };
  final rows = <_VoyageRow>[];
  for (final f in factures) {
    final groups = <String, List<FactureTransitaireLigne>>{};
    for (final l in f.lignes) {
      if (l.plaque.trim().isEmpty && l.transporteurId.isEmpty) continue;
      groups
          .putIfAbsent(
            '${l.dossierId}|${_normalizePlate(l.plaque)}|${l.dateDepart}',
            () => [],
          )
          .add(l);
    }
    for (final entry in groups.entries) {
      final lines = entry.value;
      final first = lines.first;
      final truck = trucks[_normalizePlate(first.plaque)];
      final carrier =
          partnerById[first.transporteurId]?.entreprise ??
          truck?.$1.entreprise ??
          '';
      final dossier = dossierById[first.dossierId];
      // Un camion porte au plus trois conteneurs : au-delà, un nouveau voyage.
      for (var start = 0; start < lines.length; start += 3) {
        final chunk = lines.skip(start).take(3).toList();
        rows.add(
          _VoyageRow(
            id: '${f.id}|${entry.key}|$start',
            dossier: dossier,
            transitaire: partnerById[f.transitaireId]?.entreprise ?? '',
            dateDepart: first.dateDepart,
            transporteur: carrier,
            plaque: first.plaque,
            chauffeur: truck?.$2.chauffeur ?? '',
            telephone: first.telephoneChauffeur,
            conteneurs: [
              for (final l in chunk)
                _VoyageContainer(l.bl, l.numeroConteneur, l.marchandise),
            ],
            description: dossier?.description ?? '',
            origine: f.reference,
          ),
        );
      }
    }
  }
  // Voyages saisis à la main depuis cet écran.
  for (final v in voyages) {
    final dossier = dossierById[v.dossierId];
    final truck = trucks[_normalizePlate(v.plaque)];
    rows.add(
      _VoyageRow(
        id: 'saisie|${v.id}',
        dossier: dossier,
        transitaire: dossier?.transitaireAffecte?.entreprise ?? '',
        dateDepart: v.depart,
        transporteur: truck?.$1.entreprise ?? '',
        plaque: v.plaque,
        chauffeur: v.chauffeur.isEmpty
            ? truck?.$2.chauffeur ?? ''
            : v.chauffeur,
        telephone: truck?.$2.telephone ?? '',
        conteneurs: const [],
        description: [
          if (v.origine.isNotEmpty || v.destination.isNotEmpty)
            '${v.origine} → ${v.destination}',
          if (v.statut.isNotEmpty) v.statut,
        ].join(' • '),
        origine: 'Saisie manuelle',
        saisie: v,
      ),
    );
  }
  rows.sort((a, b) {
    final byDate = (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0));
    if (byDate != 0) return byDate;
    return (a.dossier?.numDossier ?? '').compareTo(b.dossier?.numDossier ?? '');
  });
  for (final (i, row) in rows.indexed) {
    row.numero = i + 1;
  }
  return rows;
}

class VoyagesPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Voyage> voyages;
  final List<Client> clients;
  final List<Prestataire> prestataires;
  final List<FactureTransitaire> factures;

  const VoyagesPage({
    super.key,
    required this.dossiers,
    required this.voyages,
    required this.clients,
    required this.prestataires,
    required this.factures,
  });

  @override
  State<VoyagesPage> createState() => _VoyagesPageState();
}

class _VoyagesPageState extends State<VoyagesPage> {
  DateTime? _from;
  DateTime? _to;
  Client? _client;
  TransitDossier? _dossier;
  Prestataire? _transitaire;
  Prestataire? _transporteur;
  String _query = '';
  int? _treeYear;
  int? _treeMonth;
  _VoyageRow? _selected;
  bool _refreshing = false;

  List<_VoyageRow> get _all => _buildVoyages(
    dossiers: widget.dossiers,
    prestataires: widget.prestataires,
    factures: widget.factures,
    voyages: widget.voyages,
  );

  List<_VoyageRow> _filter(List<_VoyageRow> rows) {
    final query = _query.trim().toLowerCase();
    return rows.where((v) {
      final date = v.date;
      if (!_inPeriod(date, _from, _to)) return false;
      if (_treeYear != null && date?.year != _treeYear) return false;
      if (_treeMonth != null && date?.month != _treeMonth) return false;
      if (_client != null && v.dossier?.client.id != _client!.id) return false;
      if (_dossier != null && v.dossier?.id != _dossier!.id) return false;
      if (_transitaire != null && v.transitaire != _transitaire!.entreprise) {
        return false;
      }
      if (_transporteur != null &&
          v.transporteur != _transporteur!.entreprise) {
        return false;
      }
      if (query.isEmpty) return true;
      return _columns
          .map((c) => c.value(v))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  static String _containerValue(
    _VoyageRow v,
    int index,
    String Function(_VoyageContainer) field,
  ) {
    final c = v.conteneur(index);
    return c == null ? '' : field(c);
  }

  late final List<ErpGridColumn<_VoyageRow>> _columns = [
    ErpGridColumn(
      label: 'ID',
      width: 80,
      numeric: true,
      value: (v) => '${v.numero}',
      sortValue: (v) => v.numero,
    ),
    ErpGridColumn(
      label: 'Numéro Dossier',
      width: 190,
      value: (v) => v.dossier?.numDossier ?? '',
    ),
    ErpGridColumn(
      label: 'Client',
      width: 180,
      value: (v) => v.dossier?.client.nom ?? '',
    ),
    ErpGridColumn(
      label: 'Transitaire',
      width: 170,
      value: (v) => v.transitaire,
    ),
    ErpGridColumn(
      label: 'Date de départ',
      width: 140,
      value: (v) => v.dateDepart,
      sortValue: (v) => v.date ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Transporteur',
      width: 170,
      value: (v) => v.transporteur,
    ),
    ErpGridColumn(label: 'Véhicule', width: 140, value: (v) => v.plaque),
    ErpGridColumn(label: 'Chauffeur', width: 150, value: (v) => v.chauffeur),
    for (var i = 0; i < 3; i++)
      ErpGridColumn(
        label: 'BL ${i + 1}',
        width: 140,
        value: (v) => _containerValue(v, i, (c) => c.bl),
      ),
    for (var i = 0; i < 3; i++)
      ErpGridColumn(
        label: 'Numéro conteneur ${i + 1}',
        width: 170,
        value: (v) => _containerValue(v, i, (c) => c.numero),
      ),
    for (var i = 0; i < 3; i++)
      ErpGridColumn(
        label: 'Marchandise ${i + 1}',
        width: 160,
        value: (v) => _containerValue(v, i, (c) => c.marchandise),
      ),
    ErpGridColumn(
      label: 'Description',
      width: 230,
      value: (v) => v.description,
    ),
    ErpGridColumn(label: 'Origine', width: 170, value: (v) => v.origine),
  ];

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final rows = _filter(all);
    final selected = rows.where((v) => v.id == _selected?.id).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final grid = ErpGrid<_VoyageRow>(
            key: const ValueKey('voyages-grid'),
            columns: _columns,
            rows: rows,
            rowId: (v) => v.id,
            filterable: true,
            selected: selected,
            onSelect: (v) => setState(() => _selected = v),
            onOpen: _edit,
            emptyIcon: Icons.local_shipping_outlined,
            emptyText: all.isEmpty
                ? 'Aucun voyage. Les voyages apparaissent dès qu’un camion est saisi sur une facture transitaire.'
                : 'Aucun voyage ne correspond aux filtres.',
          );
          final header = [
            _buildToolbar(selected, rows),
            const SizedBox(height: 12),
            _buildFilterBar(rows.length),
            const SizedBox(height: 12),
          ];
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(10),
              children: [
                ...header,
                SizedBox(height: 520, child: grid),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ...header,
              SizedBox(
                height: math.max(520, constraints.maxHeight - 290),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 210, child: _buildTree(all)),
                    const SizedBox(width: 12),
                    Expanded(child: grid),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: child,
  );

  Widget _buildToolbar(_VoyageRow? selected, List<_VoyageRow> rows) => _card(
    child: Wrap(
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
              child: const Icon(Icons.route_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Voyages',
                    style: TextStyle(
                      color: _gridText,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    selected == null
                        ? 'Camions partis par dossier, mois par mois.'
                        : 'Voyage n° ${selected.numero} • ${selected.plaque} • ${selected.dossier?.numDossier ?? ''}',
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
          key: const ValueKey('add-voyage'),
          label: 'Nouveau voyage',
          icon: Icons.add_road_rounded,
          primary: true,
          onPressed: () => _editManual(),
        ),
        ErpActionButton(
          key: const ValueKey('voyage-edit'),
          label: 'Modifier',
          icon: Icons.edit_rounded,
          onPressed: selected == null ? null : () => _edit(selected),
        ),
        ErpActionButton(
          key: const ValueKey('voyage-export'),
          label: 'Exporter',
          icon: Icons.file_download_outlined,
          onPressed: () => _exportGrid(
            context,
            baseName: 'voyages',
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

  Widget _buildFilterBar(int count) {
    Widget dropdown<T extends Object>(
      String key,
      String label,
      String empty,
      List<T> options,
      T? value,
      String Function(T) display,
      ValueChanged<T?> onChanged,
    ) => SizedBox(
      width: 240,
      child: SearchableDropdownFormField<T>(
        key: ValueKey(key),
        options: options,
        value: value,
        label: label,
        emptyText: empty,
        required: false,
        displayString: display,
        onChanged: onChanged,
      ),
    );
    return _card(
      child: Wrap(
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
          dropdown<Client>(
            'voyage-filter-client',
            'Client',
            'Tous les clients',
            widget.clients,
            _client,
            (c) => c.nom,
            (c) => setState(() => _client = c),
          ),
          dropdown<TransitDossier>(
            'voyage-filter-dossier',
            'Dossier',
            'Tous les dossiers',
            widget.dossiers,
            _dossier,
            (d) => d.numDossier,
            (d) => setState(() => _dossier = d),
          ),
          dropdown<Prestataire>(
            'voyage-filter-transitaire',
            'Transitaire',
            'Tous les transitaires',
            widget.prestataires.where((p) => p.type == 'Transitaire').toList(),
            _transitaire,
            (p) => p.entreprise,
            (p) => setState(() => _transitaire = p),
          ),
          dropdown<Prestataire>(
            'voyage-filter-transporteur',
            'Transporteur',
            'Tous les transporteurs',
            widget.prestataires.where((p) => p.type == 'Transporteur').toList(),
            _transporteur,
            (p) => p.entreprise,
            (p) => setState(() => _transporteur = p),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: const ValueKey('voyage-search'),
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
              'Nbre de voyages : $count',
              key: const ValueKey('voyage-count'),
              style: const TextStyle(
                color: Color(0xFFC2410C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTree(List<_VoyageRow> all) {
    final years = all.map((v) => v.date?.year).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    Widget node({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      double indent = 0,
      int? count,
    }) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(left: indent, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8EAFF) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? _gridAccent : const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _gridPrimary : _gridText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
            if (count != null && count > 0)
              Text(
                '$count',
                style: const TextStyle(color: _gridMuted, fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
    int countFor(int year, [int? month]) => all
        .where(
          (v) =>
              v.date?.year == year && (month == null || v.date?.month == month),
        )
        .length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gridBorder),
      ),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          node(
            label: 'Voyages',
            icon: Icons.local_shipping_rounded,
            selected: _treeYear == null,
            count: all.length,
            onTap: () => setState(() {
              _treeYear = null;
              _treeMonth = null;
            }),
          ),
          node(
            label: 'Standard',
            icon: Icons.folder_special_rounded,
            indent: 8,
            selected: false,
            onTap: () => setState(() {
              _treeYear = null;
              _treeMonth = null;
            }),
          ),
          for (final year in years) ...[
            node(
              label: '$year',
              icon: _treeYear == year
                  ? Icons.folder_open_rounded
                  : Icons.folder_rounded,
              indent: 18,
              count: countFor(year),
              selected: _treeYear == year && _treeMonth == null,
              onTap: () => setState(() {
                _treeYear = year;
                _treeMonth = null;
              }),
            ),
            if (_treeYear == year)
              for (var month = 1; month <= 12; month++)
                node(
                  label: _monthNames[month - 1],
                  icon: Icons.calendar_month_rounded,
                  indent: 32,
                  count: countFor(year, month),
                  selected: _treeMonth == month,
                  onTap: () => setState(() => _treeMonth = month),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final data = await erpBackend.reload();
      _loadErpData(data);
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

  Future<void> _edit(_VoyageRow row) async {
    final manual = row.saisie;
    if (manual != null) return _editManual(manual);
    await _showInfoAlert(
      context,
      title: 'Voyage issu d’une facture',
      message:
          'Ce voyage vient de la facture transitaire ${row.origine}. Modifiez le camion, la date de départ ou les conteneurs dans Prestation > Facture Transitaire.',
    );
  }

  Future<void> _editManual([Voyage? initial]) async {
    if (widget.dossiers.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Dossier requis',
        message: 'Créez d’abord un dossier avant d’enregistrer un voyage.',
      );
      return;
    }
    final voyage = await showDialog<Voyage>(
      context: context,
      builder: (context) =>
          _VoyageFormDialog(dossiers: widget.dossiers, initial: initial),
    );
    if (voyage == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveVoyage(voyage))) return;
    if (!mounted) return;
    setState(() {
      final index = widget.voyages.indexWhere((entry) => entry.id == voyage.id);
      if (index < 0) {
        widget.voyages.add(voyage);
      } else {
        widget.voyages[index] = voyage;
      }
    });
  }
}
