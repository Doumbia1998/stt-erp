part of '../main.dart';

// --- DÉPENSES & FRAIS : paiement des frais des camions (transporteurs et
// flotte STT) et dépenses administratives, par bons de caisse numérotés ---

const _purple = Color(0xFF7C3AED);

// Prestataire qui porte nos camions ; créé au premier camion enregistré.
Prestataire? get _flotteStt =>
    _prestataires.where((p) => p.type == typeFlotteStt).firstOrNull;

// Caisses et banques pour payer un bon.
List<JournalCode> get _caisses => _journalCodes
    .where((j) => j.type == 'Caisse' || j.type == 'Banque')
    .toList();

String _journalLabel(String code) {
  final j = _journalCodes.where((j) => j.code == code).firstOrNull;
  return j == null ? code : '${j.code} • ${j.intitule}';
}

String _typeFraisLabel(String id) =>
    _typesFrais.where((t) => t.id == id).firstOrNull?.libelle ?? '';

// Un camion d'un dossier : à partir des factures transitaire (camions des
// transporteurs) ; un dossier sans camion apparaît aussi.
class _CamionDossier {
  final TransitDossier dossier;
  final String plaque;
  final String transporteurId;
  final String chauffeur;
  final String telephone;

  const _CamionDossier({
    required this.dossier,
    this.plaque = '',
    this.transporteurId = '',
    this.chauffeur = '',
    this.telephone = '',
  });

  String get id => '${dossier.id}|${_normalizePlate(plaque)}';
  bool get estStt => _flotteStt != null && transporteurId == _flotteStt!.id;
  String get proprietaire => plaque.isEmpty
      ? ''
      : estStt
      ? 'STT (nos camions)'
      : _partnerLabel(transporteurId);
}

List<_CamionDossier> _camionsDossiers() {
  final trucks = <String, (Prestataire, Vehicule)>{
    for (final p in _prestataires)
      for (final v in p.vehicules) _normalizePlate(v.plaque): (p, v),
  };
  final rows = <String, _CamionDossier>{};
  for (final f in _facturesTransitaire) {
    for (final l in f.lignes) {
      final dossier = _dossiers.where((d) => d.id == l.dossierId).firstOrNull;
      if (dossier == null || l.plaque.trim().isEmpty) continue;
      final truck = trucks[_normalizePlate(l.plaque)];
      final row = _CamionDossier(
        dossier: dossier,
        plaque: l.plaque,
        transporteurId: l.transporteurId.isNotEmpty
            ? l.transporteurId
            : truck?.$1.id ?? '',
        chauffeur: truck?.$2.chauffeur ?? '',
        telephone: l.telephoneChauffeur.isNotEmpty
            ? l.telephoneChauffeur
            : truck?.$2.telephone ?? '',
      );
      rows.putIfAbsent(row.id, () => row);
    }
  }
  // Camions STT déjà payés sur un dossier (livraison par nos camions).
  for (final b in _bonsCaisse) {
    for (final l in b.lignes.where((l) => l.proprietaire == 'STT')) {
      final dossier = _dossiers.where((d) => d.id == l.dossierId).firstOrNull;
      if (dossier == null || l.plaque.isEmpty) continue;
      final row = _CamionDossier(
        dossier: dossier,
        plaque: l.plaque,
        transporteurId: l.transporteurId,
        chauffeur: l.chauffeur,
        telephone: l.telephone,
      );
      rows.putIfAbsent(row.id, () => row);
    }
  }
  for (final d in _dossiers) {
    if (!rows.values.any((r) => r.dossier.id == d.id)) {
      rows['${d.id}|'] = _CamionDossier(dossier: d);
    }
  }
  return rows.values.toList()
    ..sort((a, b) => b.dossier.numDossier.compareTo(a.dossier.numDossier));
}

// Frais déjà payés pour un camion d'un dossier.
double _fraisPayes(_CamionDossier c) => _bonsCaisse
    .expand((b) => b.lignes)
    .where(
      (l) =>
          l.dossierId == c.dossier.id &&
          _normalizePlate(l.plaque) == _normalizePlate(c.plaque),
    )
    .fold(0, (s, l) => s + l.montant);

Widget _fraisCard(Widget child) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _gridBorder),
  ),
  child: child,
);

Widget _fraisHeader(IconData icon, String title, String subtitle) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_purple, Color(0xFFA855F7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white),
    ),
    const SizedBox(width: 12),
    Flexible(
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gridMuted, fontSize: 12.5),
          ),
        ],
      ),
    ),
  ],
);

List<ErpGridColumn<BonCaisse>> _bonColumns() => [
  ErpGridColumn(label: 'N° bon', width: 120, value: (b) => b.reference),
  ErpGridColumn(
    label: 'Date',
    width: 110,
    value: (b) => b.date,
    sortValue: (b) => _parseFrDate(b.date) ?? DateTime(0),
  ),
  ErpGridColumn(
    label: 'Caisse',
    width: 180,
    value: (b) => _journalLabel(b.codeJournal),
  ),
  ErpGridColumn(
    label: 'Bénéficiaire',
    width: 200,
    value: (b) => b.beneficiaire,
  ),
  ErpGridColumn(label: 'Motif', width: 220, value: (b) => b.motif),
  ErpGridColumn(
    label: 'Camions',
    width: 90,
    numeric: true,
    value: (b) => '${b.nbCamions}',
  ),
  ErpGridColumn(
    label: 'Montant',
    width: 130,
    numeric: true,
    value: (b) => _amountText(b.montant),
    sortValue: (b) => b.montant,
  ),
  ErpGridColumn(label: 'Saisi par', width: 150, value: (b) => b.auteur),
];

// --- PAIEMENT FRAIS ---

class PaiementFraisPage extends StatefulWidget {
  const PaiementFraisPage({super.key});

  @override
  State<PaiementFraisPage> createState() => _PaiementFraisPageState();
}

class _PaiementFraisPageState extends State<PaiementFraisPage> {
  String _query = '';
  final Set<String> _checked = {};
  BonCaisse? _selectedBon;

  late final List<ErpGridColumn<_CamionDossier>> _columns = [
    ErpGridColumn(
      label: '✓',
      width: 56,
      value: (c) => _checked.contains(c.id) ? 'x' : '',
      builder: (c) => Checkbox(
        key: ValueKey('fee-truck-check-${c.id}'),
        value: _checked.contains(c.id),
        onChanged: (value) => setState(() {
          if (value ?? false) {
            _checked.add(c.id);
          } else {
            _checked.remove(c.id);
          }
        }),
      ),
    ),
    ErpGridColumn(
      label: 'Dossier',
      width: 170,
      value: (c) => c.dossier.numDossier,
    ),
    ErpGridColumn(
      label: 'Client',
      width: 190,
      value: (c) => c.dossier.client.nom,
    ),
    ErpGridColumn(label: 'N° BL', width: 130, value: (c) => c.dossier.numBL),
    ErpGridColumn(label: 'Camion', width: 130, value: (c) => c.plaque),
    ErpGridColumn(
      label: 'Propriétaire',
      width: 180,
      value: (c) => c.proprietaire,
    ),
    ErpGridColumn(label: 'Chauffeur', width: 150, value: (c) => c.chauffeur),
    ErpGridColumn(label: 'Tél.', width: 130, value: (c) => c.telephone),
    ErpGridColumn(
      label: 'Frais payés',
      width: 130,
      numeric: true,
      value: (c) => _amountText(_fraisPayes(c)),
      sortValue: _fraisPayes,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final all = _camionsDossiers();
    final rows = all.where((c) {
      if (query.isEmpty) return true;
      return '${c.plaque} ${_normalizePlate(c.plaque)} ${c.dossier.client.nom} ${c.dossier.numBL} ${c.dossier.numDossier} ${c.chauffeur} ${c.proprietaire}'
          .toLowerCase()
          .contains(query);
    }).toList();
    final checked = all.where((c) => _checked.contains(c.id)).toList();
    final bons =
        _bonsCaisse.where((b) => b.categorie == BonCaisse.fraisCamion).toList()
          ..sort((a, b) => b.numero.compareTo(a.numero));
    final selectedBon = bons.where((b) => b.id == _selectedBon?.id).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fraisCard(
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _fraisHeader(
                    Icons.local_gas_station_rounded,
                    'Paiement Frais',
                    'Cochez un ou plusieurs camions, saisissez leurs frais et imprimez le bon de caisse.',
                  ),
                  const SizedBox(width: 12),
                  ErpActionButton(
                    key: const ValueKey('fee-voucher-new'),
                    label: 'Bon de caisse (${checked.length})',
                    icon: Icons.receipt_long_rounded,
                    primary: true,
                    color: _purple,
                    onPressed: checked.isEmpty
                        ? null
                        : () => _newVoucher(checked),
                  ),
                  ErpActionButton(
                    key: const ValueKey('fleet-manage'),
                    label: 'Nos camions (STT)',
                    icon: Icons.local_shipping_rounded,
                    onPressed: _manageFleet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _fraisCard(
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 340,
                    child: TextField(
                      key: const ValueKey('fee-truck-search'),
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'N° camion, client ou N° BL…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (checked.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(_checked.clear),
                      icon: const Icon(Icons.clear_rounded),
                      label: Text('Décocher (${checked.length})'),
                    ),
                  Text(
                    '${rows.length} camion(s) / dossier(s)',
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
              height: 380,
              child: ErpGrid<_CamionDossier>(
                key: const ValueKey('fee-trucks-grid'),
                columns: _columns,
                rows: rows,
                rowId: (c) => c.id,
                filterable: true,
                onSelect: (c) => setState(() {
                  if (!_checked.remove(c.id)) _checked.add(c.id);
                }),
                emptyIcon: Icons.local_shipping_outlined,
                emptyText: 'Aucun dossier ne correspond à la recherche.',
              ),
            ),
            const SizedBox(height: 12),
            _fraisCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Bons de caisse des frais (${bons.length})',
                        style: const TextStyle(
                          color: _gridText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ErpActionButton(
                        key: const ValueKey('fee-voucher-print'),
                        label: 'Imprimer',
                        icon: Icons.print_rounded,
                        onPressed: selectedBon == null
                            ? null
                            : () => _printBonCaisse(selectedBon),
                      ),
                      ErpActionButton(
                        label: 'Supprimer',
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFDC2626),
                        onPressed: selectedBon == null
                            ? null
                            : () => _deleteBon(selectedBon),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: ErpGrid<BonCaisse>(
                      key: const ValueKey('fee-vouchers-grid'),
                      columns: _bonColumns(),
                      rows: bons,
                      rowId: (b) => b.id,
                      selected: selectedBon,
                      onSelect: (b) => setState(() => _selectedBon = b),
                      onOpen: _printBonCaisse,
                      emptyText: 'Aucun bon de caisse de frais.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newVoucher(List<_CamionDossier> camions) async {
    if (_typesFrais.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Types de frais requis',
        message:
            'Créez d’abord les types de frais (gasoil, frais de route…) dans Dépenses & Frais > Types de frais.',
      );
      return;
    }
    final bon = await showDialog<BonCaisse>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BonFraisDialog(camions: camions),
    );
    if (bon == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveBonCaisse(bon))) return;
    if (!mounted) return;
    setState(() {
      _bonsCaisse.add(bon);
      _checked.clear();
      _selectedBon = bon;
    });
    await _offerPrint(context, bon);
  }

  Future<void> _deleteBon(BonCaisse bon) async {
    if (!await _confirmDeleteBon(context, bon)) return;
    if (!mounted) return;
    if (!await _persist(context, () => erpBackend.deleteBonCaisse(bon))) {
      return;
    }
    if (mounted) {
      setState(() {
        _bonsCaisse.remove(bon);
        _selectedBon = null;
      });
    }
  }

  Future<void> _manageFleet() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FlotteSttDialog(),
    );
    if (mounted) setState(() {});
  }
}

Future<bool> _confirmDeleteBon(BuildContext context, BonCaisse bon) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer le bon ${bon.reference} ?'),
        content: Text(
          '${_amountText(bon.montant)} • ${bon.beneficiaire}\nLe bon et ses lignes seront supprimés.',
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
    ) ??
    false;

Future<void> _offerPrint(BuildContext context, BonCaisse bon) async {
  final print = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Bon de caisse ${bon.reference}'),
      content: Text(
        '${_amountText(bon.montant)} enregistré${bon.nbCamions > 0 ? ' pour ${bon.nbCamions} camion(s)' : ''}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          key: const ValueKey('voucher-print-now'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.print_rounded),
          label: const Text('Imprimer le bon'),
        ),
      ],
    ),
  );
  if (print == true) await _printBonCaisse(bon);
}

// Ligne en cours de saisie d'un bon de frais.
class _FraisDraft {
  final TransitDossier? dossier;
  final String plaque;
  final String proprietaire;
  final String transporteurId;
  final String chauffeur;
  final String telephone;
  TypeFrais? type;
  final TextEditingController montant;

  _FraisDraft({
    required this.dossier,
    required this.plaque,
    required this.proprietaire,
    required this.transporteurId,
    required this.chauffeur,
    required this.telephone,
    this.type,
  }) : montant = TextEditingController(
         text: type == null || type.montant == 0
             ? ''
             : type.montant.toStringAsFixed(0),
       );

  _FraisDraft copy() => _FraisDraft(
    dossier: dossier,
    plaque: plaque,
    proprietaire: proprietaire,
    transporteurId: transporteurId,
    chauffeur: chauffeur,
    telephone: telephone,
    type: type,
  );
}

// Saisie d'un bon de caisse de frais pour un ou plusieurs camions.
class _BonFraisDialog extends StatefulWidget {
  final List<_CamionDossier> camions;

  const _BonFraisDialog({required this.camions});

  @override
  State<_BonFraisDialog> createState() => _BonFraisDialogState();
}

class _BonFraisDialogState extends State<_BonFraisDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<_FraisDraft> _lines = [
    for (final c in widget.camions)
      _FraisDraft(
        dossier: c.dossier,
        plaque: c.plaque,
        proprietaire: c.plaque.isEmpty
            ? ''
            : (c.estStt ? 'STT' : 'Transporteur'),
        transporteurId: c.transporteurId,
        chauffeur: c.chauffeur,
        telephone: c.telephone,
        type: _typesFrais.first,
      ),
  ];
  late final _beneficiaire = TextEditingController(
    text: widget.camions
        .map((c) => c.chauffeur)
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(', '),
  );
  final _observations = TextEditingController();
  DateTime _date = DateTime.now();
  JournalCode? _caisse = _caisses.firstOrNull;

  @override
  void dispose() {
    for (final l in _lines) {
      l.montant.dispose();
    }
    _beneficiaire.dispose();
    _observations.dispose();
    super.dispose();
  }

  double get _total =>
      _lines.fold(0, (s, l) => s + (_parseAmount(l.montant.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width - 40, 980.0);
    return AlertDialog(
      title: const Text('Nouveau bon de caisse • frais des camions'),
      content: SizedBox(
        width: width,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 190,
                      child: _FormDateField(
                        label: 'Date',
                        value: _date,
                        clearable: false,
                        onChanged: (d) => setState(() => _date = d ?? _date),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<JournalCode>(
                        key: const ValueKey('voucher-caisse'),
                        isExpanded: true,
                        initialValue: _caisse,
                        decoration: _inputDecoration(
                          'Caisse *',
                          icon: Icons.point_of_sale_rounded,
                        ),
                        items: [
                          for (final j in _caisses)
                            DropdownMenuItem(
                              value: j,
                              child: Text('${j.code} • ${j.intitule}'),
                            ),
                        ],
                        validator: (j) =>
                            j == null ? 'Choisissez la caisse' : null,
                        onChanged: (j) => setState(() => _caisse = j),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: TextFormField(
                        controller: _beneficiaire,
                        decoration: _inputDecoration(
                          'Bénéficiaire(s)',
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final (i, line) in _lines.indexed) _lineRow(i, line),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('voucher-add-stt'),
                      onPressed: _addSttTruck,
                      icon: const Icon(Icons.add_road_rounded),
                      label: const Text('Ajouter un camion STT'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observations,
                  decoration: _inputDecoration(
                    'Observations',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total : ${_amountText(_total)}',
                  key: const ValueKey('voucher-total'),
                  style: const TextStyle(
                    color: _gridPrimary,
                    fontSize: 18,
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
          key: const ValueKey('voucher-save'),
          style: FilledButton.styleFrom(backgroundColor: _purple),
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Enregistrer le bon'),
        ),
      ],
    );
  }

  Widget _lineRow(int i, _FraisDraft line) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: line.proprietaire == 'STT'
          ? const Color(0xFFF5F3FF)
          : const Color(0xFFF7F9FD),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _gridBorder),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 250,
          child: Text(
            [
              line.plaque.isEmpty ? 'Sans camion' : line.plaque,
              if (line.proprietaire == 'STT') 'STT',
              if (line.dossier != null) line.dossier!.numDossier,
              if (line.chauffeur.isNotEmpty) line.chauffeur,
            ].join(' • '),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<TypeFrais>(
            key: ValueKey('voucher-line-$i-type'),
            isExpanded: true,
            initialValue: line.type,
            decoration: _cellDecoration(hint: 'Type de frais'),
            items: [
              for (final t in _typesFrais)
                DropdownMenuItem(value: t, child: Text(t.libelle)),
            ],
            validator: (t) => t == null ? 'Type requis' : null,
            onChanged: (t) => setState(() {
              line.type = t;
              if (t != null && t.montant > 0 && line.montant.text.isEmpty) {
                line.montant.text = t.montant.toStringAsFixed(0);
              }
            }),
          ),
        ),
        SizedBox(
          width: 150,
          child: TextFormField(
            key: ValueKey('voucher-line-$i-amount'),
            controller: line.montant,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _cellDecoration(hint: 'Montant'),
            validator: (value) {
              final amount = _parseAmount(value ?? '');
              return amount == null || amount <= 0 ? 'Montant > 0' : null;
            },
            onChanged: (_) => setState(() {}),
          ),
        ),
        IconButton(
          tooltip: 'Autre frais pour ce camion',
          onPressed: () => setState(() => _lines.insert(i + 1, line.copy())),
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Retirer la ligne',
          onPressed: _lines.length == 1
              ? null
              : () => setState(() => _lines.removeAt(i).montant.dispose()),
          icon: const Icon(
            Icons.remove_circle_outline_rounded,
            color: Colors.redAccent,
          ),
        ),
      ],
    ),
  );

  // Nos camions livrent souvent les marchandises des camions des transporteurs.
  Future<void> _addSttTruck() async {
    final fleet = _flotteStt;
    if (fleet == null || fleet.vehicules.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Aucun camion STT',
        message:
            'Enregistrez d’abord nos camions avec le bouton « Nos camions (STT) ».',
      );
      return;
    }
    final dossiers = widget.camions.map((c) => c.dossier).toSet().toList();
    final picked = await showDialog<(Vehicule, TransitDossier)>(
      context: context,
      builder: (_) => _PickSttTruckDialog(fleet: fleet, dossiers: dossiers),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _lines.add(
        _FraisDraft(
          dossier: picked.$2,
          plaque: picked.$1.plaque,
          proprietaire: 'STT',
          transporteurId: fleet.id,
          chauffeur: picked.$1.chauffeur,
          telephone: picked.$1.telephone,
          type: _typesFrais.first,
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      BonCaisse(
        id: newLocalId('bc'),
        categorie: BonCaisse.fraisCamion,
        date: DateFormat('dd/MM/yyyy').format(_date),
        codeJournal: _caisse?.code ?? '',
        beneficiaire: _beneficiaire.text.trim(),
        motif: 'Frais des camions',
        observations: _observations.text.trim(),
        auteur: _currentUser?.name ?? '',
        lignes: [
          for (final l in _lines)
            BonCaisseLigne(
              dossierId: l.dossier?.id ?? '',
              plaque: l.plaque.toUpperCase(),
              proprietaire: l.proprietaire,
              transporteurId: l.transporteurId,
              chauffeur: l.chauffeur,
              telephone: l.telephone,
              typeFraisId: l.type?.id ?? '',
              compte: l.type?.compte ?? '',
              libelle: l.type?.libelle ?? '',
              montant: _parseAmount(l.montant.text) ?? 0,
            ),
        ],
      ),
    );
  }
}

class _PickSttTruckDialog extends StatefulWidget {
  final Prestataire fleet;
  final List<TransitDossier> dossiers;

  const _PickSttTruckDialog({required this.fleet, required this.dossiers});

  @override
  State<_PickSttTruckDialog> createState() => _PickSttTruckDialogState();
}

class _PickSttTruckDialogState extends State<_PickSttTruckDialog> {
  late Vehicule? _truck = widget.fleet.vehicules.firstOrNull;
  late TransitDossier? _dossier = widget.dossiers.firstOrNull;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Camion STT (livraison)'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<Vehicule>(
            key: const ValueKey('stt-truck-pick'),
            isExpanded: true,
            initialValue: _truck,
            decoration: _inputDecoration(
              'Notre camion',
              icon: Icons.local_shipping_rounded,
            ),
            items: [
              for (final v in widget.fleet.vehicules)
                DropdownMenuItem(
                  value: v,
                  child: Text(
                    v.chauffeur.isEmpty
                        ? v.plaque
                        : '${v.plaque} • ${v.chauffeur}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _truck = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TransitDossier>(
            isExpanded: true,
            initialValue: _dossier,
            decoration: _inputDecoration(
              'Dossier livré',
              icon: Icons.folder_outlined,
            ),
            items: [
              for (final d in widget.dossiers)
                DropdownMenuItem(
                  value: d,
                  child: Text('${d.numDossier} • ${d.client.nom}'),
                ),
            ],
            onChanged: (d) => setState(() => _dossier = d),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const ValueKey('stt-truck-confirm'),
        onPressed: _truck == null || _dossier == null
            ? null
            : () => Navigator.pop(context, (_truck!, _dossier!)),
        child: const Text('Ajouter'),
      ),
    ],
  );
}

// Nos camions (flotte STT) : plaque, chauffeur, téléphone.
class _FlotteSttDialog extends StatefulWidget {
  const _FlotteSttDialog();

  @override
  State<_FlotteSttDialog> createState() => _FlotteSttDialogState();
}

class _FlotteSttDialogState extends State<_FlotteSttDialog> {
  final _plate = TextEditingController();
  final _driver = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _plate.dispose();
    _driver.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save(List<Vehicule> vehicules) async {
    setState(() => _saving = true);
    var fleet = _flotteStt;
    final created = fleet == null;
    fleet ??= Prestataire(
      id: newLocalId('prest'),
      entreprise: 'STT – FLOTTE PROPRE',
      type: typeFlotteStt,
      pays: 'Mali',
      villePort: '',
      contact: '',
      telephone: '',
      email: '',
      services: 'Nos camions',
    );
    final previous = fleet.vehicules;
    fleet.vehicules = vehicules;
    final target = fleet;
    final ok = await _persist(
      context,
      () => erpBackend.savePrestataire(target),
    );
    if (!ok) {
      target.vehicules = previous;
    } else if (created) {
      _prestataires.add(target);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _add() async {
    final plate = _plate.text.trim().toUpperCase();
    if (plate.isEmpty) return;
    final taken = _prestataires.any(
      (p) => p.vehicules.any(
        (v) => _normalizePlate(v.plaque) == _normalizePlate(plate),
      ),
    );
    if (taken) {
      await _showInfoAlert(
        context,
        title: 'Camion déjà enregistré',
        message: 'La plaque $plate existe déjà.',
      );
      return;
    }
    await _save([
      ...?_flotteStt?.vehicules,
      Vehicule(
        id: newLocalId('veh'),
        plaque: plate,
        chauffeur: _driver.text.trim(),
        telephone: _phone.text.trim(),
      ),
    ]);
    if (!mounted) return;
    _plate.clear();
    _driver.clear();
    _phone.clear();
  }

  @override
  Widget build(BuildContext context) {
    final trucks = _flotteStt?.vehicules ?? const <Vehicule>[];
    return AlertDialog(
      title: const Text('Nos camions (flotte STT)'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (trucks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Aucun camion STT pour le moment.',
                    style: TextStyle(color: _gridMuted),
                  ),
                ),
              for (final v in trucks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.local_shipping_rounded,
                    color: _purple,
                  ),
                  title: Text(v.plaque),
                  subtitle: Text(
                    [
                      v.chauffeur,
                      v.telephone,
                    ].where((s) => s.isNotEmpty).join(' • '),
                  ),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    onPressed: _saving
                        ? null
                        : () => _save([...trucks]..remove(v)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              const Divider(),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 160,
                    child: TextField(
                      key: const ValueKey('fleet-plate'),
                      controller: _plate,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _inputDecoration(
                        'Plaque *',
                        icon: Icons.local_shipping_outlined,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: TextField(
                      key: const ValueKey('fleet-driver'),
                      controller: _driver,
                      decoration: _inputDecoration(
                        'Chauffeur',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        'Téléphone',
                        icon: Icons.phone_rounded,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('fleet-add'),
                    style: FilledButton.styleFrom(backgroundColor: _purple),
                    onPressed: _saving ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

// --- DÉPENSES ADMINISTRATIVES (bons de caisse du PDG, du DG…) ---

class DepensesAdministrativesPage extends StatefulWidget {
  const DepensesAdministrativesPage({super.key});

  @override
  State<DepensesAdministrativesPage> createState() =>
      _DepensesAdministrativesPageState();
}

class _DepensesAdministrativesPageState
    extends State<DepensesAdministrativesPage> {
  BonCaisse? _selected;
  String _query = '';

  late final List<ErpGridColumn<BonCaisse>> _columns = [
    ..._bonColumns().where((c) => c.label != 'Camions'),
    ErpGridColumn(
      label: 'Compte',
      width: 220,
      value: (b) => b.lignes
          .map((l) => l.compte)
          .where((c) => c.isNotEmpty)
          .toSet()
          .join(', '),
    ),
    ErpGridColumn(
      label: 'Bon manuel',
      width: 130,
      value: (b) => b.referenceManuelle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final bons =
        _bonsCaisse
            .where((b) => b.categorie == BonCaisse.depenseAdministrative)
            .where(
              (b) =>
                  query.isEmpty ||
                  _columns
                      .map((c) => c.value(b))
                      .join(' ')
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort((a, b) => b.numero.compareTo(a.numero));
    final selected = bons.where((b) => b.id == _selected?.id).firstOrNull;
    final total = bons.fold<double>(0, (s, b) => s + b.montant);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fraisCard(
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _fraisHeader(
                    Icons.account_balance_wallet_rounded,
                    'Dépenses administratives',
                    'Bons de caisse du PDG, du DG et autres : motif et compte comptable obligatoires.',
                  ),
                  const SizedBox(width: 12),
                  ErpActionButton(
                    key: const ValueKey('admin-voucher-new'),
                    label: 'Nouveau bon de caisse',
                    icon: Icons.add_card_rounded,
                    primary: true,
                    color: _purple,
                    onPressed: _create,
                  ),
                  ErpActionButton(
                    label: 'Imprimer',
                    icon: Icons.print_rounded,
                    onPressed: selected == null
                        ? null
                        : () => _printBonCaisse(selected),
                  ),
                  ErpActionButton(
                    label: 'Supprimer',
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFDC2626),
                    onPressed: selected == null
                        ? null
                        : () => _delete(selected),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _fraisCard(
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Bénéficiaire, motif, compte…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${bons.length} bon(s) • ${_amountText(total)}',
                    key: const ValueKey('admin-vouchers-count'),
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
              height: 480,
              child: ErpGrid<BonCaisse>(
                key: const ValueKey('admin-vouchers-grid'),
                columns: _columns,
                rows: bons,
                rowId: (b) => b.id,
                filterable: true,
                selected: selected,
                onSelect: (b) => setState(() => _selected = b),
                onOpen: _printBonCaisse,
                emptyIcon: Icons.account_balance_wallet_outlined,
                emptyText: 'Aucune dépense administrative.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final bon = await showDialog<BonCaisse>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BonAdministratifDialog(),
    );
    if (bon == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveBonCaisse(bon))) return;
    if (!mounted) return;
    setState(() {
      _bonsCaisse.add(bon);
      _selected = bon;
    });
    await _offerPrint(context, bon);
  }

  Future<void> _delete(BonCaisse bon) async {
    if (!await _confirmDeleteBon(context, bon)) return;
    if (!mounted) return;
    if (!await _persist(context, () => erpBackend.deleteBonCaisse(bon))) {
      return;
    }
    if (mounted) {
      setState(() {
        _bonsCaisse.remove(bon);
        _selected = null;
      });
    }
  }
}

class _BonAdministratifDialog extends StatefulWidget {
  const _BonAdministratifDialog();

  @override
  State<_BonAdministratifDialog> createState() =>
      _BonAdministratifDialogState();
}

class _BonAdministratifDialogState extends State<_BonAdministratifDialog> {
  static const _beneficiaires = ['PDG', 'DG', 'Autre'];

  final _formKey = GlobalKey<FormState>();
  final _autre = TextEditingController();
  final _motif = TextEditingController();
  final _manuel = TextEditingController();
  final _montant = TextEditingController();
  DateTime _date = DateTime.now();
  JournalCode? _caisse = _caisses.firstOrNull;
  String _beneficiaire = 'PDG';
  TypeFrais? _type;
  PlanAccount? _compte;
  int _accountVersion = 0;

  List<PlanAccount> get _accounts => [..._planAccounts]
    ..sort((a, b) {
      final ca = a.code.startsWith('6') ? 0 : 1;
      final cb = b.code.startsWith('6') ? 0 : 1;
      return ca != cb ? ca - cb : a.code.compareTo(b.code);
    });

  @override
  void dispose() {
    for (final c in [_autre, _motif, _manuel, _montant]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bon de caisse • dépense administrative'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 190,
                    child: _FormDateField(
                      label: 'Date',
                      value: _date,
                      clearable: false,
                      onChanged: (d) => setState(() => _date = d ?? _date),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<JournalCode>(
                      isExpanded: true,
                      initialValue: _caisse,
                      decoration: _inputDecoration(
                        'Caisse *',
                        icon: Icons.point_of_sale_rounded,
                      ),
                      items: [
                        for (final j in _caisses)
                          DropdownMenuItem(
                            value: j,
                            child: Text('${j.code} • ${j.intitule}'),
                          ),
                      ],
                      validator: (j) =>
                          j == null ? 'Choisissez la caisse' : null,
                      onChanged: (j) => setState(() => _caisse = j),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in _beneficiaires)
                    ChoiceChip(
                      key: ValueKey('admin-beneficiary-$b'),
                      label: Text(b),
                      selected: _beneficiaire == b,
                      onSelected: (_) => setState(() => _beneficiaire = b),
                    ),
                ],
              ),
              if (_beneficiaire == 'Autre') ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _autre,
                  decoration: _inputDecoration(
                    'Bénéficiaire *',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Champ obligatoire' : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('admin-motif'),
                controller: _motif,
                maxLines: 2,
                decoration: _inputDecoration(
                  'Motif *',
                  icon: Icons.notes_rounded,
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Le motif est obligatoire'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TypeFrais>(
                isExpanded: true,
                initialValue: _type,
                decoration: _inputDecoration(
                  'Type de frais (facultatif)',
                  icon: Icons.category_outlined,
                ),
                items: [
                  for (final t in _typesFrais)
                    DropdownMenuItem(value: t, child: Text(t.libelle)),
                ],
                onChanged: (t) => setState(() {
                  _type = t;
                  final account = _planAccounts
                      .where((a) => a.code == t?.compte)
                      .firstOrNull;
                  if (account != null) {
                    _compte = account;
                    _accountVersion++;
                  }
                  if (t != null && t.montant > 0 && _montant.text.isEmpty) {
                    _montant.text = t.montant.toStringAsFixed(0);
                  }
                }),
              ),
              const SizedBox(height: 12),
              SearchableDropdownFormField<PlanAccount>(
                key: ValueKey('admin-account-$_accountVersion'),
                options: _accounts,
                value: _compte,
                label: 'Compte comptable *',
                emptyText: 'Aucun compte dans le plan comptable',
                displayString: (a) => '${a.code} — ${a.libelle}',
                onChanged: (a) => setState(() => _compte = a),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextFormField(
                      key: const ValueKey('admin-amount'),
                      controller: _montant,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _inputDecoration(
                        'Montant *',
                        icon: Icons.payments_outlined,
                      ).copyWith(suffixText: 'F'),
                      validator: (value) {
                        final amount = _parseAmount(value ?? '');
                        return amount == null || amount <= 0
                            ? 'Montant > 0'
                            : null;
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextFormField(
                      controller: _manuel,
                      decoration: _inputDecoration(
                        'N° du bon manuel',
                        icon: Icons.tag_rounded,
                      ),
                    ),
                  ),
                ],
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
        key: const ValueKey('admin-voucher-save'),
        style: FilledButton.styleFrom(backgroundColor: _purple),
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final beneficiaire = _beneficiaire == 'Autre'
              ? _autre.text.trim()
              : _beneficiaire;
          Navigator.pop(
            context,
            BonCaisse(
              id: newLocalId('bc'),
              categorie: BonCaisse.depenseAdministrative,
              date: DateFormat('dd/MM/yyyy').format(_date),
              codeJournal: _caisse?.code ?? '',
              beneficiaire: beneficiaire,
              motif: _motif.text.trim(),
              referenceManuelle: _manuel.text.trim(),
              auteur: _currentUser?.name ?? '',
              lignes: [
                BonCaisseLigne(
                  typeFraisId: _type?.id ?? '',
                  compte: _compte?.code ?? '',
                  libelle: _type?.libelle ?? _motif.text.trim(),
                  montant: _parseAmount(_montant.text) ?? 0,
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.check_rounded),
        label: const Text('Enregistrer le bon'),
      ),
    ],
  );
}

// Bon de caisse imprimé : numéro, caisse, bénéficiaire, lignes et signatures.
Future<void> _printBonCaisse(BonCaisse bon) async {
  final logo = await _loadPdfLogo();
  final doc = pw.Document(
    title: 'Bon de caisse ${bon.reference}',
    author: 'Sylla Transit & Transport',
  );
  final camions = bon.categorie == BonCaisse.fraisCamion;
  String dossier(String id) =>
      _dossiers.where((d) => d.id == id).firstOrNull?.numDossier ?? '';
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.Image(logo, height: 46),
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
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'BON DE CAISSE',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'N° ${bon.reference}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: _pdfPrimary,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'du ${bon.date}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _pdfInfoGrid([
            ('Nature', bon.categorie),
            ('Caisse', _journalLabel(bon.codeJournal)),
            ('Bénéficiaire', bon.beneficiaire),
            ('Motif', bon.motif),
            if (bon.referenceManuelle.isNotEmpty)
              ('Bon manuel', bon.referenceManuelle),
            ('Saisi par', bon.auteur),
          ]),
          pw.SizedBox(height: 12),
          _pdfTable(
            camions
                ? [
                    'Camion',
                    'Propriétaire',
                    'Dossier',
                    'Chauffeur',
                    'Frais',
                    'Compte',
                    'Montant',
                  ]
                : ['Libellé', 'Compte', 'Montant'],
            [
              for (final l in bon.lignes)
                camions
                    ? [
                        l.plaque,
                        l.proprietaire == 'STT'
                            ? 'STT'
                            : _partnerLabel(l.transporteurId),
                        dossier(l.dossierId),
                        [
                          l.chauffeur,
                          l.telephone,
                        ].where((s) => s.isNotEmpty).join(' • '),
                        l.libelle.isEmpty
                            ? _typeFraisLabel(l.typeFraisId)
                            : l.libelle,
                        l.compte,
                        formatCurrency(l.montant),
                      ]
                    : [l.libelle, l.compte, formatCurrency(l.montant)],
            ],
            numericColumns: {camions ? 6 : 2},
            fontSize: 8.5,
          ),
          pw.SizedBox(height: 10),
          _pdfTotals([('TOTAL', '${formatCurrency(bon.montant)} FCFA')]),
          if (bon.observations.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Observations : ${bon.observations}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in [
                'Le caissier',
                'Le bénéficiaire',
                'Visa Direction',
              ])
                pw.Column(
                  children: [
                    pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 40),
                    pw.Container(
                      width: 140,
                      height: 0.6,
                      color: PdfColors.grey700,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(
    name: 'Bon de caisse ${bon.reference}',
    onLayout: (_) => doc.save(),
  );
}
