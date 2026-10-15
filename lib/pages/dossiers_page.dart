part of '../main.dart';

// --- GESTION DES DOSSIERS : grille, filtres, facturation et impressions ---

enum _BillingFilter { all, billed, unbilled }

// Transitaire « LUI MEME » : le client assure lui-même son transit.
final _luiMeme = Prestataire(
  id: '__lui_meme__',
  entreprise: 'LUI MEME',
  type: 'Transitaire',
  pays: '',
  villePort: '',
  contact: '',
  telephone: '',
  email: '',
  services: '',
);

List<Prestataire> _transitaireOptions(List<Prestataire> prestataires) => [
  _luiMeme,
  ...prestataires.where((p) => p.type == 'Transitaire'),
];

(String, Color) _dossierStatus(TransitDossier d) {
  if (d.estCloture) return ('Clôturé', const Color(0xFF475569));
  if (d.estFacture) return ('Facturé', const Color(0xFF15803D));
  return ('Non facturé', const Color(0xFFEA580C));
}

const _monthNames = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

// Prochain numéro de la forme PREFIXE-MMAA-NNNN (ex. FAC-STT-1026-0001).
String _nextInvoiceNumber(
  String prefix,
  Iterable<String> existing,
  DateTime date,
) {
  final base = '$prefix-${DateFormat('MMyy').format(date)}-';
  var last = 0;
  for (final reference in existing) {
    if (!reference.startsWith(base)) continue;
    last = math.max(last, int.tryParse(reference.substring(base.length)) ?? 0);
  }
  return '$base${(last + 1).toString().padLeft(4, '0')}';
}

class DossiersPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Client> clients;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;

  const DossiersPage({
    super.key,
    required this.dossiers,
    required this.clients,
    required this.prestataires,
    required this.journals,
  });

  @override
  State<DossiersPage> createState() => _DossiersPageState();
}

class _DossiersPageState extends State<DossiersPage> {
  DateTime? _from;
  DateTime? _to;
  Client? _client;
  Prestataire? _transitaire;
  _BillingFilter _billing = _BillingFilter.all;
  String _query = '';
  int? _treeYear;
  int? _treeMonth;
  TransitDossier? _selected;
  PdfPageFormat _format = PdfPageFormat.a4;
  bool _refreshing = false;

  DateTime? _creation(TransitDossier d) =>
      _parseFrDate(d.dateCreation.isEmpty ? d.dateDebut : d.dateCreation);

  // Délai d'exécution : jusqu'à la clôture, ou jusqu'à aujourd'hui si le dossier est ouvert.
  int _executionDays(TransitDossier d) {
    final start = _creation(d);
    if (start == null) return 0;
    final end = d.estCloture ? _parseFrDate(d.dateFin) : DateTime.now();
    if (end == null) return 0;
    return math.max(0, end.difference(start).inDays);
  }

  List<TransitDossier> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.dossiers.where((d) {
      final created = _creation(d);
      if (!_inPeriod(created, _from, _to)) return false;
      if (_treeYear != null && created?.year != _treeYear) return false;
      if (_treeMonth != null && created?.month != _treeMonth) return false;
      if (_client != null && d.client.id != _client!.id) return false;
      if (_transitaire != null) {
        final matches = identical(_transitaire, _luiMeme)
            ? d.transitaireAffecte == null
            : d.transitaireAffecte?.id == _transitaire!.id;
        if (!matches) return false;
      }
      if (_billing == _BillingFilter.billed && !d.estFacture) return false;
      if (_billing == _BillingFilter.unbilled && d.estFacture) return false;
      if (query.isEmpty) return true;
      return _columns
          .map((c) => c.value(d))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  late final List<ErpGridColumn<TransitDossier>> _columns = [
    ErpGridColumn(
      label: 'ID',
      width: 72,
      numeric: true,
      value: (d) => d.numero == 0 ? '' : '${d.numero}',
      sortValue: (d) => d.numero,
    ),
    ErpGridColumn(
      label: 'Statut',
      width: 140,
      value: (d) => _dossierStatus(d).$1,
      builder: (d) {
        final (label, color) = _dossierStatus(d);
        return ErpStatusChip(label, color);
      },
    ),
    ErpGridColumn(label: 'Client', width: 200, value: (d) => d.client.nom),
    ErpGridColumn(
      label: 'Transitaire',
      width: 170,
      value: (d) => d.nomTransitaire,
    ),
    ErpGridColumn(
      label: 'Numéro de dossier',
      width: 200,
      value: (d) => d.numDossier,
    ),
    ErpGridColumn(label: 'BL', width: 150, value: (d) => d.numBL),
    ErpGridColumn(
      label: 'Date de création',
      width: 125,
      value: (d) => d.dateCreation,
      sortValue: (d) => _creation(d) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Type de facturation',
      width: 150,
      value: (d) => d.typeFacturation,
    ),
    ErpGridColumn(
      label: 'Type de priorité',
      width: 145,
      value: (d) => d.priorite,
    ),
    ErpGridColumn(
      label: 'Type de marchandise',
      width: 175,
      value: (d) => d.typeMarchandise,
    ),
    ErpGridColumn(
      label: 'Lieu de la marchandise',
      width: 170,
      value: (d) => d.lieuMarchandise,
    ),
    ErpGridColumn(
      label: 'Lieu de livraison',
      width: 160,
      value: (d) => d.lieuLivraison,
    ),
    ErpGridColumn(
      label: 'Conteneurs 20 pieds',
      width: 120,
      numeric: true,
      value: (d) => '${d.nbConteneurs20}',
      sortValue: (d) => d.nbConteneurs20,
    ),
    ErpGridColumn(
      label: 'Conteneurs 40 pieds',
      width: 120,
      numeric: true,
      value: (d) => '${d.nbConteneurs40}',
      sortValue: (d) => d.nbConteneurs40,
    ),
    ErpGridColumn(
      label: 'Livraison souhaitée',
      width: 140,
      value: (d) => d.dateLivraisonSouhaitee,
      sortValue: (d) => _parseFrDate(d.dateLivraisonSouhaitee) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Description',
      width: 230,
      value: (d) => d.description,
    ),
    ErpGridColumn(
      label: 'Arrivée bateau',
      width: 130,
      value: (d) => d.dateArriveeBateau,
      sortValue: (d) => _parseFrDate(d.dateArriveeBateau) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Délai d’exécution (jours)',
      width: 150,
      numeric: true,
      value: (d) => '${_executionDays(d)}',
      sortValue: (d) => _executionDays(d),
    ),
    ErpGridColumn(
      label: 'Auteur saisie',
      width: 150,
      value: (d) => d.auteurSaisie,
    ),
    ErpGridColumn(
      label: 'Date saisie',
      width: 110,
      value: (d) => d.dateSaisie.split(' ').first,
      sortValue: (d) => _parseFrDate(d.dateSaisie) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Heure saisie',
      width: 100,
      value: (d) =>
          d.dateSaisie.contains(' ') ? d.dateSaisie.split(' ').last : '',
    ),
    ErpGridColumn(
      label: 'Facture client',
      width: 180,
      value: (d) => d.estFacture ? d.factureClient.reference : '',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final selected = rows.any((d) => d.id == _selected?.id) ? _selected : null;
    final containers = rows.fold<int>(0, (sum, d) => sum + d.conteneurs.length);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final grid = ErpGrid<TransitDossier>(
            key: const ValueKey('dossiers-grid'),
            columns: _columns,
            rows: rows,
            rowId: (d) => d.id,
            selected: selected,
            onSelect: (d) => setState(() => _selected = d),
            onOpen: _openDetails,
            emptyIcon: Icons.folder_off_outlined,
            emptyText: widget.dossiers.isEmpty
                ? 'Aucun dossier enregistré. Cliquez sur « Nouveau dossier » pour commencer.'
                : 'Aucun dossier ne correspond aux filtres.',
          );
          // Sur téléphone, la page défile et la grille garde une hauteur fixe.
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _buildToolbar(selected, wide),
                const SizedBox(height: 12),
                _buildFilterBar(rows.length, containers),
                const SizedBox(height: 12),
                SizedBox(height: 520, child: grid),
              ],
            );
          }
          // La grille garde au moins 520 px de haut ; sur un petit écran la page défile.
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _buildToolbar(selected, wide),
              const SizedBox(height: 12),
              _buildFilterBar(rows.length, containers),
              const SizedBox(height: 12),
              SizedBox(
                height: math.max(520, constraints.maxHeight - 290),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 210, child: _buildTree()),
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

  Widget _buildToolbar(TransitDossier? selected, bool wide) {
    final hasSelection = selected != null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gridPrimary, _gridAccent],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_copy_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gestion des Dossiers',
                      style: TextStyle(
                        color: _gridText,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      selected == null
                          ? 'Sélectionnez un dossier dans la grille pour le modifier, le facturer ou l’imprimer.'
                          : 'Dossier sélectionné : ${selected.numDossier} • ${selected.client.nom}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _gridMuted, fontSize: 12.5),
                    ),
                  ],
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ErpActionButton(
                key: const ValueKey('dossier-new'),
                label: 'Nouveau dossier',
                icon: Icons.create_new_folder_rounded,
                primary: true,
                onPressed: _create,
              ),
              ErpActionButton(
                key: const ValueKey('dossier-invoice'),
                label: 'Facturer le dossier',
                icon: Icons.request_quote_rounded,
                primary: true,
                color: const Color(0xFF15803D),
                onPressed: hasSelection ? () => _invoice(selected) : null,
              ),
              ErpActionButton(
                key: const ValueKey('dossier-edit'),
                label: 'Modifier',
                icon: Icons.edit_rounded,
                onPressed: hasSelection ? () => _edit(selected) : null,
              ),
              ErpActionButton(
                key: const ValueKey('dossier-delete'),
                label: 'Supprimer',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFDC2626),
                onPressed: hasSelection ? () => _delete(selected) : null,
              ),
              ErpActionButton(
                key: const ValueKey('dossier-close'),
                label: 'Clôturer',
                icon: Icons.lock_outline_rounded,
                onPressed: hasSelection ? () => _close(selected) : null,
              ),
              ErpActionButton(
                key: const ValueKey('dossier-export'),
                label: 'Exporter',
                icon: Icons.file_download_outlined,
                onPressed: () => _exportGrid(
                  context,
                  baseName: 'dossiers',
                  columns: _columns,
                  rows: _filtered,
                ),
              ),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (label, format) in [
                      ('A4', PdfPageFormat.a4),
                      ('A5', PdfPageFormat.a5),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _format == format,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _format = format),
                      ),
                  ],
                ),
              ),
              ErpActionButton(
                label: 'Impr. dossier',
                icon: Icons.print_outlined,
                onPressed: hasSelection
                    ? () => _printDossier(selected, _format)
                    : null,
              ),
              ErpActionButton(
                label: 'Impr. facture',
                icon: Icons.receipt_long_outlined,
                onPressed: hasSelection ? () => _printInvoice(selected) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(int count, int containers) {
    final transitaires = _transitaireOptions(widget.prestataires);
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
          SizedBox(
            width: 250,
            child: SearchableDropdownFormField<Client>(
              key: const ValueKey('dossier-filter-client'),
              options: widget.clients,
              value: _client,
              label: 'Client',
              emptyText: 'Tous les clients',
              required: false,
              displayString: (client) => client.nom,
              onChanged: (client) => setState(() => _client = client),
            ),
          ),
          SizedBox(
            width: 250,
            child: SearchableDropdownFormField<Prestataire>(
              key: const ValueKey('dossier-filter-transitaire'),
              options: transitaires,
              value: _transitaire,
              label: 'Transitaire',
              emptyText: 'Tous les transitaires',
              required: false,
              displayString: (p) => p.entreprise,
              onChanged: (p) => setState(() => _transitaire = p),
            ),
          ),
          SegmentedButton<_BillingFilter>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _BillingFilter.all, label: Text('Tous')),
              ButtonSegment(
                value: _BillingFilter.billed,
                label: Text('Facturés'),
              ),
              ButtonSegment(
                value: _BillingFilter.unbilled,
                label: Text('Non facturés'),
              ),
            ],
            selected: {_billing},
            onSelectionChanged: (value) =>
                setState(() => _billing = value.first),
          ),
          SizedBox(
            width: 280,
            child: TextField(
              key: const ValueKey('dossier-search'),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Rechercher dans toutes les colonnes…',
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
              '$count dossier(s) • $containers conteneur(s)',
              key: const ValueKey('dossier-count'),
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

  Widget _buildTree() {
    final years =
        widget.dossiers
            .map((d) => _creation(d)?.year)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    Widget node({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      double indent = 0,
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
          ],
        ),
      ),
    );
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
            label: 'Tous les dossiers',
            icon: Icons.folder_special_rounded,
            selected: _treeYear == null,
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
              indent: 10,
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
                  indent: 24,
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

  void _openDetails(TransitDossier dossier) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          DetailsDossierPage(dossier: dossier, journals: widget.journals),
    ),
  ).then((_) => setState(() {}));

  Future<void> _create() async {
    if (widget.clients.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Client requis',
        message:
            'Ajoutez d’abord un client dans Transitaire > Clients pour créer son dossier.',
      );
      return;
    }
    final dossier = await showDialog<TransitDossier>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DossierEditorDialog(
        clients: widget.clients,
        prestataires: widget.prestataires,
        dossiers: widget.dossiers,
      ),
    );
    if (dossier == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) return;
    if (mounted) {
      setState(() {
        widget.dossiers.add(dossier);
        _selected = dossier;
      });
    }
  }

  Future<void> _edit(TransitDossier dossier) async {
    if (dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Dossier clôturé',
        message: 'Un dossier clôturé ne peut plus être modifié.',
      );
      return;
    }
    final updated = await showDialog<TransitDossier>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DossierEditorDialog(
        clients: widget.clients,
        prestataires: widget.prestataires,
        dossiers: widget.dossiers,
        initial: dossier,
      ),
    );
    if (updated == null || !mounted) return;
    if (!await _persist(context, () => erpBackend.saveDossier(updated))) return;
    if (!mounted) return;
    setState(() {
      final index = widget.dossiers.indexWhere((d) => d.id == updated.id);
      if (index >= 0) widget.dossiers[index] = updated;
      _selected = updated;
    });
  }

  Future<void> _delete(TransitDossier dossier) async {
    final reason = dossier.estCloture
        ? 'Un dossier clôturé ne peut pas être supprimé.'
        : dossier.estFacture
        ? 'Ce dossier est facturé (${dossier.factureClient.reference}).'
        : dossier.operations.isNotEmpty || dossier.depenses.isNotEmpty
        ? 'Ce dossier contient des règlements ou des frais.'
        : null;
    if (reason != null) {
      await _showInfoAlert(
        context,
        title: 'Suppression impossible',
        message: reason,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
        title: const Text('Supprimer ce dossier ?'),
        content: Text(
          '${dossier.numDossier} (${dossier.client.nom}) et ses conteneurs seront définitivement supprimés.',
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
    if (!await _persist(context, () => erpBackend.deleteDossier(dossier))) {
      return;
    }
    if (mounted) {
      setState(() {
        widget.dossiers.removeWhere((d) => d.id == dossier.id);
        _selected = null;
      });
    }
  }

  Future<void> _invoice(TransitDossier dossier) async {
    if (dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Dossier clôturé',
        message: 'Ce dossier est clôturé : sa facture ne peut plus changer.',
      );
      return;
    }
    if (dossier.estFacture) {
      final invoice = dossier.factureClient;
      final print = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.verified_rounded,
            color: Color(0xFF15803D),
            size: 36,
          ),
          title: const Text('Dossier déjà facturé'),
          content: Text(
            'Ce dossier a déjà été facturé : facture ${invoice.reference} du '
            '${invoice.dateEmission} pour ${_amountText(invoice.montant)}.\n\n'
            'Une facture validée ne peut plus être refaite.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimer la facture'),
            ),
          ],
        ),
      );
      if (print == true && mounted) {
        await _printClientInvoice(dossier, _format);
      }
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _FacturationDialog(dossier: dossier, dossiers: widget.dossiers),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _close(TransitDossier dossier) async {
    if (dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Déjà clôturé',
        message: 'Ce dossier est clôturé depuis le ${dossier.dateFin}.',
      );
      return;
    }
    if (!dossier.peutCloturer) {
      final reasons = [
        if (!dossier.estFacture) '• le dossier n’est pas encore facturé ;',
        if (dossier.soldeClient > 0)
          '• le client doit encore ${_amountText(dossier.soldeClient)} ;',
        if (dossier.soldePrestataire > 0)
          '• il reste ${_amountText(dossier.soldePrestataire)} à payer au prestataire ;',
        if (dossier.prestataire != null &&
            dossier.estFacture &&
            dossier.soldePrestataire <= 0)
          '• la facture du prestataire n’est pas encore validée ;',
      ];
      await _showInfoAlert(
        context,
        title: 'Clôture impossible',
        message:
            'Ce dossier ne peut pas encore être clôturé :\n${reasons.join('\n')}',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer le dossier ?'),
        content: const Text(
          'Les comptes sont soldés. Une fois clôturé, le dossier ne pourra plus être modifié.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = (dossier.statut, dossier.dateFin);
    dossier
      ..statut = 'Clôturé'
      ..dateFin = DateFormat('dd/MM/yyyy').format(DateTime.now());
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) {
      dossier
        ..statut = previous.$1
        ..dateFin = previous.$2;
    }
    if (mounted) setState(() {});
  }

  Future<void> _printInvoice(TransitDossier dossier) async {
    if (!dossier.estFacture) {
      await _showInfoAlert(
        context,
        title: 'Dossier non facturé',
        message: 'Utilisez « Facturer le dossier » pour créer sa facture.',
      );
      return;
    }
    await _printClientInvoice(dossier, _format);
  }
}
