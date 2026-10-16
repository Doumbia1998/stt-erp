part of '../main.dart';

// --- TRANSPORTEURS : sociétés de transport et leurs camions ---

class TransporteursPage extends StatefulWidget {
  final List<Prestataire> prestataires;
  final List<PlanAccount> comptes;

  const TransporteursPage({
    super.key,
    required this.prestataires,
    required this.comptes,
  });

  @override
  State<TransporteursPage> createState() => _TransporteursPageState();
}

class _TransporteursPageState extends State<TransporteursPage> {
  Prestataire? _selected;
  String _query = '';

  List<Prestataire> get _carriers {
    final query = _query.trim().toLowerCase();
    return widget.prestataires.where((p) {
      if (p.type != 'Transporteur') return false;
      if (query.isEmpty) return true;
      return [
        p.entreprise,
        p.contact,
        p.telephone,
        p.adresse,
        ...p.vehicules.map((v) => '${v.plaque} ${v.chauffeur} ${v.telephone}'),
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  late final List<ErpGridColumn<Prestataire>> _columns = [
    ErpGridColumn(
      label: 'ID',
      width: 60,
      numeric: true,
      value: (p) =>
          '${widget.prestataires.where((x) => x.type == 'Transporteur').toList().indexOf(p) + 1}',
    ),
    ErpGridColumn(label: 'Société', width: 200, value: (p) => p.entreprise),
    ErpGridColumn(label: 'Contact', width: 170, value: (p) => p.contact),
    ErpGridColumn(label: 'Téléphone', width: 140, value: (p) => p.telephone),
    ErpGridColumn(label: 'RCCM', width: 130, value: (p) => p.rccm),
    ErpGridColumn(label: 'Adresse', width: 200, value: (p) => p.adresse),
    ErpGridColumn(
      label: 'Nbre véhicules',
      width: 120,
      numeric: true,
      value: (p) => '${p.vehicules.length}',
      sortValue: (p) => p.vehicules.length,
    ),
    ErpGridColumn(
      label: 'Plaques',
      width: 300,
      value: (p) => p.vehicules.map((v) => v.plaque).join(', '),
    ),
    ErpGridColumn(label: 'Compte', width: 120, value: (p) => p.compteComptable),
  ];

  static final _truckColumns = <ErpGridColumn<Vehicule>>[
    ErpGridColumn(label: 'Plaque', width: 150, value: (v) => v.plaque),
    ErpGridColumn(label: 'Chauffeur', width: 200, value: (v) => v.chauffeur),
    ErpGridColumn(
      label: 'Téléphone chauffeur',
      width: 180,
      value: (v) => v.telephone,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final carriers = _carriers;
    final selected = carriers.any((p) => p.id == _selected?.id)
        ? _selected
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final grid = ErpGrid<Prestataire>(
            key: const ValueKey('carriers-grid'),
            columns: _columns,
            rows: carriers,
            rowId: (p) => p.id,
            selected: selected,
            onSelect: (p) => setState(() => _selected = p),
            onOpen: _edit,
            emptyIcon: Icons.local_shipping_outlined,
            emptyText:
                'Aucun transporteur. Cliquez sur « Nouveau transporteur ».',
          );
          final trucks = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gridBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selected == null
                      ? 'Camions'
                      : 'Camions de ${selected.entreprise} (${selected.vehicules.length})',
                  style: const TextStyle(
                    color: _gridText,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ErpGrid<Vehicule>(
                    key: const ValueKey('carrier-trucks-grid'),
                    columns: _truckColumns,
                    rows: selected?.vehicules ?? const [],
                    rowId: (v) => v.id,
                    emptyIcon: Icons.touch_app_outlined,
                    emptyText: selected == null
                        ? 'Sélectionnez un transporteur pour voir ses camions.'
                        : 'Aucun camion enregistré pour ce transporteur.',
                  ),
                ),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _buildHeader(carriers, selected),
              const SizedBox(height: 12),
              SizedBox(
                height: math.max(480, constraints.maxHeight - 150),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: grid),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: trucks),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: grid),
                          const SizedBox(height: 12),
                          SizedBox(height: 260, child: trucks),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<Prestataire> carriers, Prestataire? selected) {
    final trucks = carriers.fold<int>(0, (s, p) => s + p.vehicules.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_gridPrimary, _gridAccent]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Transporteurs',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Nombre de transporteurs : ${carriers.length} • $trucks camion(s)',
                key: const ValueKey('carriers-count'),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Société, plaque, chauffeur…',
                    hintStyle: const TextStyle(color: Colors.white70),
                    isDense: true,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white24,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('carrier-new'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _gridPrimary,
                ),
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nouveau transporteur'),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('carrier-edit'),
                onPressed: selected == null ? null : () => _edit(selected),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Modifier'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Prestataire? initial) async {
    final carrier = await showDialog<Prestataire>(
      context: context,
      builder: (context) => _PrestataireFormDialog(
        prestataires: widget.prestataires,
        comptes: widget.comptes,
        initial: initial,
        defaultType: 'Transporteur',
      ),
    );
    if (carrier == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.savePrestataire(carrier))) {
      return;
    }
    _linkTiersAccount(
      widget.comptes,
      tiersId: carrier.id,
      previousCode: initial?.compteComptable,
      newCode: carrier.compteComptable,
    );
    if (!mounted) return;
    setState(() {
      final index = widget.prestataires.indexWhere((p) => p.id == carrier.id);
      if (index < 0) {
        widget.prestataires.add(carrier);
      } else {
        widget.prestataires[index] = carrier;
      }
      _selected = carrier;
    });
  }
}
