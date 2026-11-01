part of '../main.dart';

// --- SUPPRESSION DES DONNÉES DE TEST (administrateur) ---
// Un élément à la fois : dossier, client, prestataire, facture, bon ou
// mouvement de caisse, supprimé avec ce qui en dépend, même s'il est
// verrouillé en temps normal.

class _TypeSuppression {
  final String cle;
  final String label;
  final IconData icon;
  // Ce qui part avec l'élément, affiché dans la confirmation.
  final String consequence;

  const _TypeSuppression(this.cle, this.label, this.icon, this.consequence);
}

const _typesSuppression = [
  _TypeSuppression(
    'dossier',
    'Dossiers',
    Icons.folder_copy_rounded,
    'Ses factures, règlements, frais, reçus de caisse, voyages et ses lignes dans les factures transitaire / transporteur sont aussi supprimés.',
  ),
  _TypeSuppression(
    'client',
    'Clients',
    Icons.people_rounded,
    'Tous ses dossiers (et ce qui en dépend) sont aussi supprimés. Son compte du plan comptable est conservé.',
  ),
  _TypeSuppression(
    'prestataire',
    'Prestataires',
    Icons.business_center_rounded,
    'Ses camions, factures transitaire et transporteur sont aussi supprimés. Les dossiers sont conservés, sans ce prestataire.',
  ),
  _TypeSuppression(
    'facture-transitaire',
    'Factures transitaire',
    Icons.directions_boat_rounded,
    'Ses lignes et ses règlements sont aussi supprimés.',
  ),
  _TypeSuppression(
    'facture-transporteur',
    'Factures transporteur',
    Icons.local_shipping_rounded,
    'Ses lignes et ses règlements sont aussi supprimés.',
  ),
  _TypeSuppression(
    'facture-agent',
    'Factures agents',
    Icons.badge_rounded,
    'Ses règlements sont supprimés ; les saisies des agents redeviennent non facturées.',
  ),
  _TypeSuppression(
    'bon-caisse',
    'Bons de caisse',
    Icons.receipt_long_rounded,
    'Son paiement par la caisse des dépenses est aussi supprimé.',
  ),
  _TypeSuppression(
    'mouvement-caisse',
    'Mouvements de caisse',
    Icons.point_of_sale_rounded,
    'Pour un encaissement, le règlement client créé dans le dossier est aussi supprimé.',
  ),
];

// Une ligne de la liste, quel que soit le type.
class _ElementSuppression {
  final String id;
  final String reference;
  final String detail;
  final String date;
  final double montant;

  const _ElementSuppression({
    required this.id,
    required this.reference,
    this.detail = '',
    this.date = '',
    this.montant = 0,
  });
}

class ReinitialisationPage extends StatefulWidget {
  const ReinitialisationPage({super.key});

  @override
  State<ReinitialisationPage> createState() => _ReinitialisationPageState();
}

class _ReinitialisationPageState extends State<ReinitialisationPage> {
  _TypeSuppression _type = _typesSuppression.first;
  String _query = '';

  bool get _isAdmin => _currentUser?.role == 'Administrateur';

  List<_ElementSuppression> get _elements => switch (_type.cle) {
    'dossier' => [
      for (final d in _dossiers)
        _ElementSuppression(
          id: d.id,
          reference: d.numDossier,
          detail: [
            d.client.nom,
            if (d.numBL.isNotEmpty) 'BL ${d.numBL}',
            if (d.estFacture) d.factureClient.reference,
          ].join(' • '),
          date: d.dateCreation,
          montant: d.totalFacturesClient,
        ),
    ],
    'client' => [
      for (final c in _clients)
        _ElementSuppression(
          id: c.id,
          reference: c.nom,
          detail:
              '${c.compteComptable} • ${_dossiers.where((d) => d.client.id == c.id).length} dossier(s)',
        ),
    ],
    'prestataire' => [
      for (final p in _prestataires)
        _ElementSuppression(
          id: p.id,
          reference: p.entreprise,
          detail: '${p.type} • ${p.compteComptable}',
        ),
    ],
    'facture-transitaire' => [
      for (final f in _facturesTransitaire)
        _ElementSuppression(
          id: f.id,
          reference: f.reference,
          detail: _partnerLabel(f.transitaireId),
          date: f.dateEmission,
          montant: f.montant,
        ),
    ],
    'facture-transporteur' => [
      for (final f in _facturesTransporteur)
        _ElementSuppression(
          id: f.id,
          reference: f.reference,
          detail: '${_partnerLabel(f.transporteurId)} • ${f.plaque}',
          date: f.dateEmission,
          montant: f.montant,
        ),
    ],
    'facture-agent' => [
      for (final f in _facturesAgent)
        _ElementSuppression(
          id: f.id,
          reference: f.reference,
          detail: f.module,
          date: f.dateEmission,
          montant: f.montant,
        ),
    ],
    'bon-caisse' => [
      for (final b in _bonsCaisse)
        _ElementSuppression(
          id: b.id,
          reference: b.reference,
          detail: '${b.categorie} • ${b.beneficiaire}',
          date: b.date,
          montant: b.montant,
        ),
    ],
    _ => [
      for (final m in _caisseMouvements)
        _ElementSuppression(
          id: m.id,
          reference: m.recu.isNotEmpty
              ? m.recu
              : _bonsCaisse
                        .where((b) => b.id == m.bonId)
                        .firstOrNull
                        ?.reference ??
                    m.type,
          detail: [
            m.type,
            if (m.dossierId.isNotEmpty)
              _dossierById(m.dossierId)?.client.nom ?? '',
            m.auteur,
          ].where((t) => t.isNotEmpty).join(' • '),
          date: m.date,
          montant: m.montant,
        ),
    ],
  };

  late final List<ErpGridColumn<_ElementSuppression>> _columns = [
    ErpGridColumn(label: 'Référence', width: 200, value: (e) => e.reference),
    ErpGridColumn(label: 'Détail', width: 360, value: (e) => e.detail),
    ErpGridColumn(label: 'Date', width: 110, value: (e) => e.date),
    ErpGridColumn(
      label: 'Montant',
      width: 140,
      numeric: true,
      value: (e) => e.montant == 0 ? '' : formatCurrency(e.montant),
      sortValue: (e) => e.montant,
    ),
    ErpGridColumn(
      label: 'Supprimer',
      width: 100,
      value: (_) => '',
      builder: (e) => IconButton(
        key: ValueKey('delete-${_type.cle}-${e.id}'),
        tooltip: 'Supprimer',
        icon: const Icon(Icons.delete_rounded, color: Color(0xFFDC2626)),
        onPressed: () => _supprimer(e),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const ModulePlaceholderPage(
        title: 'Accès non autorisé',
        icon: Icons.lock_outline_rounded,
        moduleTitle: 'Gestion',
      );
    }
    final query = _query.trim().toLowerCase();
    final rows = _elements
        .where(
          (e) =>
              query.isEmpty ||
              '${e.reference} ${e.detail} ${e.date}'.toLowerCase().contains(
                query,
              ),
        )
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supprimer des données de test',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Pendant la conception seulement : chaque élément est supprimé définitivement, avec ce qui en dépend, même s’il est verrouillé en temps normal (règlements, paiement en caisse…). Réservé à l’administrateur.',
                          style: TextStyle(color: Color(0xFF7F1D1D)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _caisseCard(
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<_TypeSuppression>(
                      key: const ValueKey('delete-type'),
                      initialValue: _type,
                      isExpanded: true,
                      decoration: _inputDecoration(
                        'Type de données',
                        icon: _type.icon,
                      ),
                      items: [
                        for (final t in _typesSuppression)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (t) => setState(() => _type = t ?? _type),
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      key: const ValueKey('delete-search'),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Rechercher…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${rows.length} élément(s)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 520,
              child: ErpGrid<_ElementSuppression>(
                key: const ValueKey('delete-grid'),
                columns: _columns,
                rows: rows,
                rowId: (e) => e.id,
                emptyIcon: Icons.inbox_outlined,
                emptyText: 'Aucun élément de ce type.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _supprimer(_ElementSuppression e) async {
    final type = _type;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${e.reference} » ?'),
        content: Text(
          '${e.detail.isEmpty ? '' : '${e.detail}\n\n'}${type.consequence}\n\nCette suppression est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.supprimerElement(type.cle, e.id),
    )) {
      return;
    }
    if (!mounted) return;
    await _actualiserDonnees(context);
    if (mounted) setState(() {});
  }
}
