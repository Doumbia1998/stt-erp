part of '../main.dart';

// --- CAISSE : la caisse principale encaisse les factures des clients et
// approvisionne la caisse des dépenses, qui paie les bons de caisse et reverse
// son reliquat. Chaque caisse a son relevé et sa clôture du jour ---

const _caisseGreen = Color(0xFF15803D);
const _caisseRed = Color(0xFFDC2626);
const _caisseOrange = Color(0xFFC2410C);

String get _todayFr => DateFormat('dd/MM/yyyy').format(DateTime.now());

bool get _isCaissierPrincipal => _currentUser?.role == roleCaissierPrincipal;
bool get _isCaissierDepenses => _currentUser?.role == roleCaissierDepenses;

double? _parseMontant(String text) =>
    double.tryParse(text.trim().replaceAll(' ', '').replaceAll(',', '.'));

String _caisseLabel(String caisse) =>
    caisse == caissePrincipale ? 'Caisse principale' : 'Caisse des dépenses';

CaisseCloture? _clotureDuJour(String caisse) => _caisseClotures
    .where((c) => c.caisse == caisse && c.date == _todayFr)
    .firstOrNull;

CaisseMouvement? _paiementDuBon(BonCaisse bon) =>
    _caisseMouvements.where((m) => m.bonId == bon.id).firstOrNull;

TransitDossier? _dossierById(String id) =>
    _dossiers.where((d) => d.id == id).firstOrNull;

// Approvisionnements envoyés à cette caisse et pas encore réceptionnés (le
// reversement entre directement dans la caisse principale).
List<CaisseMouvement> _virementsAReceptionner(String caisse) =>
    _caisseMouvements
        .where(
          (m) =>
              m.type == CaisseMouvement.approvisionnement &&
              !m.estReceptionne &&
              m.caisseDestination == caisse,
        )
        .toList();

Widget _caisseCard(Widget child) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _gridBorder),
  ),
  child: child,
);

Widget _caisseHeader(
  IconData icon,
  String title,
  String subtitle,
  List<Color> colors,
) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
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

// Administrateur : rouvre une caisse clôturée par erreur.
Future<bool> _declotureCaisse(BuildContext context, String caisse) async {
  final cloture = _clotureDuJour(caisse);
  if (cloture == null) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Déclôturer la ${_caisseLabel(caisse).toLowerCase()} ?'),
      content: Text(
        'La clôture du ${cloture.date} faite par ${cloture.auteur} sera annulée : les mouvements de ce jour pourront de nouveau être saisis ou annulés.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('caisse-decloture-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Déclôturer'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  if (!await _persist(context, () => erpBackend.rouvrirCaisse(caisse))) {
    return false;
  }
  _caisseClotures.remove(cloture);
  return true;
}

// Bandeau d'alerte : caisse sans journal ou déjà clôturée aujourd'hui ;
// l'administrateur peut déclôturer (onReopen).
Widget? _caisseAlerte(String caisse, {VoidCallback? onReopen}) {
  final cloture = _clotureDuJour(caisse);
  final String? message;
  if (_caisseParametres.journalDe(caisse).isEmpty) {
    message =
        'Aucun journal comptable n’est choisi pour la ${_caisseLabel(caisse).toLowerCase()}. La Direction doit le définir dans « Paramètres des caisses ».';
  } else if (cloture != null) {
    message =
        '${_caisseLabel(caisse)} clôturée aujourd’hui par ${cloture.auteur} (solde ${_amountText(cloture.solde)}) : plus aucun mouvement possible ce jour.';
  } else {
    message = null;
  }
  if (message == null) return null;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFED7AA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: _caisseOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: _caisseOrange)),
        ),
        if (cloture != null &&
            onReopen != null &&
            _currentUser?.role == 'Administrateur')
          TextButton.icon(
            key: const ValueKey('caisse-decloture'),
            onPressed: onReopen,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Déclôturer'),
          ),
      ],
    ),
  );
}

Future<void> _editCaisseParametres(BuildContext context) async {
  final saved = await showDialog<CaisseParametres>(
    context: context,
    builder: (_) => const _CaisseParametresDialog(),
  );
  if (saved == null || !context.mounted) return;
  if (!await _persist(context, () => erpBackend.saveCaisseParametres(saved))) {
    return;
  }
  _caisseParametres = saved;
}

class _CaisseParametresDialog extends StatefulWidget {
  const _CaisseParametresDialog();

  @override
  State<_CaisseParametresDialog> createState() =>
      _CaisseParametresDialogState();
}

class _CaisseParametresDialogState extends State<_CaisseParametresDialog> {
  late String? _principale = _caisseParametres.principale.isEmpty
      ? null
      : _caisseParametres.principale;
  late String? _depenses = _caisseParametres.depenses.isEmpty
      ? null
      : _caisseParametres.depenses;

  Widget _picker(String label, String? value, ValueChanged<String?> onChanged) {
    final journals = _caisses;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: journals.any((j) => j.code == value) ? value : null,
      decoration: _inputDecoration(label, icon: Icons.menu_book_rounded),
      items: [
        for (final j in journals)
          DropdownMenuItem(
            value: j.code,
            child: Text(
              '${j.code} • ${j.intitule}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paramètres des caisses'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choisissez le journal comptable de chaque caisse (codes journaux de type Caisse ou Banque).',
            style: TextStyle(color: _gridMuted),
          ),
          const SizedBox(height: 14),
          _picker(
            'Caisse principale (encaissements)',
            _principale,
            (v) => setState(() => _principale = v),
          ),
          const SizedBox(height: 12),
          _picker(
            'Caisse des dépenses',
            _depenses,
            (v) => setState(() => _depenses = v),
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
        onPressed:
            _principale != null && _depenses != null && _principale != _depenses
            ? () => Navigator.pop(
                context,
                CaisseParametres(
                  principale: _principale!,
                  depenses: _depenses!,
                ),
              )
            : null,
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

// Virement entre caisses : approvisionnement ou reversement du reliquat.
Future<CaisseMouvement?> _faireVirement(
  BuildContext context,
  String type,
) async {
  final source = type == CaisseMouvement.approvisionnement
      ? caissePrincipale
      : caisseDepenses;
  final solde = soldeCaisse(source, _caisseMouvements);
  final amount = TextEditingController(
    text: type == CaisseMouvement.reversement && solde > 0
        ? solde.toStringAsFixed(0)
        : '',
  );
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final value = _parseMontant(amount.text) ?? 0;
        final valid = value > 0 && value <= solde;
        return AlertDialog(
          title: Text(
            type == CaisseMouvement.approvisionnement
                ? 'Approvisionner la caisse des dépenses'
                : 'Reverser le reliquat à la caisse principale',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solde disponible (${_caisseLabel(source).toLowerCase()}) : ${_amountText(solde)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('virement-amount'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    'Montant *',
                    icon: Icons.payments_outlined,
                  ),
                ),
                if (value > solde)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Montant supérieur au solde de la caisse.',
                      style: TextStyle(color: _caisseRed, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: _inputDecoration(
                    'Observations',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  type == CaisseMouvement.approvisionnement
                      ? 'La caisse des dépenses devra réceptionner l’approvisionnement pour qu’il entre dans son solde.'
                      : 'Le reliquat entre directement dans la caisse principale.',
                  style: const TextStyle(color: _gridMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('virement-save'),
              onPressed: valid ? () => Navigator.pop(context, true) : null,
              child: const Text('Valider le virement'),
            ),
          ],
        );
      },
    ),
  );
  final value = _parseMontant(amount.text) ?? 0;
  if (ok != true || !context.mounted) return null;
  CaisseMouvement? saved;
  if (!await _persist(context, () async {
    saved = await erpBackend.virementCaisse(
      type: type,
      montant: value,
      observations: notes.text.trim(),
    );
  })) {
    return null;
  }
  _caisseMouvements.add(saved!);
  return saved;
}

// Réception des virements envoyés à cette caisse.
Future<void> _receptionnerVirements(BuildContext context, String caisse) async {
  final pending = _virementsAReceptionner(caisse);
  if (pending.isEmpty) return;
  final selected = await showDialog<CaisseMouvement>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Virements à réceptionner'),
      children: [
        for (final m in pending)
          SimpleDialogOption(
            key: ValueKey('virement-reception-${m.id}'),
            onPressed: () => Navigator.pop(context, m),
            child: ListTile(
              leading: const Icon(Icons.move_down_rounded),
              title: Text('${m.type} • ${_amountText(m.montant)}'),
              subtitle: Text(
                'Envoyé le ${m.date} par ${m.auteur}${m.observations.isEmpty ? '' : ' • ${m.observations}'}',
              ),
              trailing: const Text('Réceptionner'),
            ),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  await _persist(context, () => erpBackend.receptionnerVirement(selected));
}

// --- ÉTAT DES IMPAYÉS ---

String _marchandiseDossier(TransitDossier d) {
  if (d.typeMarchandise.isNotEmpty) return d.typeMarchandise;
  return d.conteneurs
      .map((c) => c.marchandise)
      .where((m) => m.isNotEmpty)
      .toSet()
      .join(', ');
}

String _statutFactureClient(TransitDossier d) {
  if (d.soldeClient <= 0) return statutPaye;
  if (d.totalReglementsClient > 0) return statutCommencement;
  return 'Non payé';
}

Color _statutColor(String statut) => switch (statut) {
  statutPaye => _caisseGreen,
  statutCommencement => _caisseOrange,
  _ => _caisseRed,
};

List<ErpGridColumn<TransitDossier>> _impayesColumns() => [
  ErpGridColumn(
    label: 'N° facture',
    width: 170,
    value: (d) => d.factureClient.reference,
  ),
  ErpGridColumn(
    label: 'Date',
    width: 105,
    value: (d) => d.factureClient.dateEmission,
    sortValue: (d) => _parseFrDate(d.factureClient.dateEmission) ?? DateTime(0),
  ),
  ErpGridColumn(label: 'Client', width: 190, value: (d) => d.client.nom),
  ErpGridColumn(
    label: 'Compte tiers',
    width: 120,
    value: (d) => d.client.compteComptable,
  ),
  ErpGridColumn(label: 'Dossier', width: 150, value: (d) => d.numDossier),
  ErpGridColumn(label: 'N° BL', width: 120, value: (d) => d.numBL),
  ErpGridColumn(label: 'Marchandise', width: 170, value: _marchandiseDossier),
  ErpGridColumn(
    label: 'Facturé',
    width: 130,
    numeric: true,
    value: (d) => formatCurrency(d.totalFacturesClient),
    sortValue: (d) => d.totalFacturesClient,
  ),
  ErpGridColumn(
    label: 'Réglé',
    width: 130,
    numeric: true,
    value: (d) => formatCurrency(d.totalReglementsClient),
    sortValue: (d) => d.totalReglementsClient,
  ),
  ErpGridColumn(
    label: 'Non réglé',
    width: 130,
    numeric: true,
    value: (d) => formatCurrency(math.max(0, d.soldeClient)),
    sortValue: (d) => d.soldeClient,
    builder: (d) => Text(
      formatCurrency(math.max(0, d.soldeClient)),
      style: TextStyle(
        color: d.soldeClient > 0 ? _caisseRed : _gridMuted,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  ErpGridColumn(
    label: 'Statut',
    width: 130,
    value: _statutFactureClient,
    builder: (d) {
      final statut = _statutFactureClient(d);
      final color = _statutColor(statut);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          statut,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      );
    },
  ),
];

// Factures clients validées, filtrées (non soldées par défaut) et recherchées.
class _ImpayesPanel extends StatefulWidget {
  // Caisse principale : bouton « Encaisser » sur la facture choisie.
  final Future<void> Function(TransitDossier dossier)? onEncaisser;

  const _ImpayesPanel({this.onEncaisser});

  @override
  State<_ImpayesPanel> createState() => _ImpayesPanelState();
}

class _ImpayesPanelState extends State<_ImpayesPanel> {
  static const _filters = ['Non soldées', 'Soldées', 'Toutes'];
  String _filter = _filters.first;
  String _query = '';
  TransitDossier? _selected;

  List<TransitDossier> get _rows {
    final query = _query.trim().toLowerCase();
    return _dossiers.where((d) {
      if (d.totalFacturesClient <= 0) return false;
      if (_filter == 'Non soldées' && d.soldeClient <= 0) return false;
      if (_filter == 'Soldées' && d.soldeClient > 0) return false;
      if (query.isEmpty) return true;
      return '${d.factureClient.reference} ${d.client.nom} ${d.client.compteComptable} ${d.numDossier} ${d.numBL} ${_marchandiseDossier(d)}'
          .toLowerCase()
          .contains(query);
    }).toList()..sort(
      (a, b) => b.factureClient.reference.compareTo(a.factureClient.reference),
    );
  }

  // Totaux de toutes les factures des clients recherchés (zéro sans recherche).
  ({double facture, double regle, double solde}) get _totauxRecherche {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return (facture: 0, regle: 0, solde: 0);
    final matching = _dossiers.where(
      (d) =>
          d.totalFacturesClient > 0 &&
          '${d.client.nom} ${d.client.compteComptable} ${d.factureClient.reference} ${d.numBL}'
              .toLowerCase()
              .contains(query),
    );
    final facture = matching.fold<double>(
      0,
      (s, d) => s + d.totalFacturesClient,
    );
    final regle = matching.fold<double>(
      0,
      (s, d) => s + d.totalReglementsClient,
    );
    return (facture: facture, regle: regle, solde: facture - regle);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selected = rows.where((d) => d.id == _selected?.id).firstOrNull;
    final totaux = _totauxRecherche;
    final reste = rows.fold<double>(
      0,
      (s, d) => s + math.max(0, d.soldeClient),
    );
    final onEncaisser = widget.onEncaisser;
    return _caisseCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'État des impayés',
                style: TextStyle(
                  color: _gridText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('impayes-filter'),
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: _inputDecoration(
                    'Factures',
                    icon: Icons.filter_list_rounded,
                  ),
                  items: [
                    for (final f in _filters)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) => setState(() => _filter = v ?? _filter),
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  key: const ValueKey('impayes-search'),
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Nom du client, N° facture, BL…',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (onEncaisser != null)
                ErpActionButton(
                  key: const ValueKey('encaisser'),
                  label: 'Encaisser',
                  icon: Icons.point_of_sale_rounded,
                  primary: true,
                  color: _caisseGreen,
                  onPressed: selected == null || selected.soldeClient <= 0
                      ? null
                      : () async {
                          await onEncaisser(selected);
                          if (mounted) setState(() {});
                        },
                ),
              ErpActionButton(
                label: 'Imprimer',
                icon: Icons.print_rounded,
                onPressed: rows.isEmpty
                    ? null
                    : () => _printEtatImpayes(rows, _filter),
              ),
              Text(
                '${rows.length} facture(s) • non réglé ${_amountText(reste)}',
                style: const TextStyle(
                  color: _caisseRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            key: const ValueKey('impayes-totaux'),
            spacing: 10,
            runSpacing: 10,
            children: [
              ErpMetricTile(
                label: 'Total facturé (client recherché)',
                value: _amountText(totaux.facture),
                color: _gridAccent,
                icon: Icons.request_quote_rounded,
              ),
              ErpMetricTile(
                label: 'Total réglé',
                value: _amountText(totaux.regle),
                color: _caisseGreen,
                icon: Icons.check_circle_rounded,
              ),
              ErpMetricTile(
                label: 'Solde client',
                value: _amountText(totaux.solde),
                color: _caisseRed,
                icon: Icons.account_balance_wallet_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 380,
            child: ErpGrid<TransitDossier>(
              key: const ValueKey('impayes-grid'),
              columns: _impayesColumns(),
              rows: rows,
              rowId: (d) => d.id,
              filterable: true,
              selected: selected,
              onSelect: (d) => setState(() => _selected = d),
              onOpen: onEncaisser == null
                  ? null
                  : (d) async {
                      if (d.soldeClient <= 0) return;
                      await onEncaisser(d);
                      if (mounted) setState(() {});
                    },
              emptyIcon: Icons.verified_rounded,
              emptyText: 'Aucune facture client pour ce filtre.',
            ),
          ),
        ],
      ),
    );
  }
}

class EtatImpayesPage extends StatelessWidget {
  const EtatImpayesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6FB),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _caisseCard(
            _caisseHeader(
              Icons.receipt_long_rounded,
              'État des impayés',
              'Factures clients non soldées : N° de facture, marchandise, montants réglés et non réglés.',
              const [_caisseRed, Color(0xFFF97316)],
            ),
          ),
          const SizedBox(height: 12),
          const _ImpayesPanel(),
        ],
      ),
    ),
  );
}

// --- CAISSE ENCAISSEMENT (caisse principale) ---

class CaisseEncaissementPage extends StatefulWidget {
  const CaisseEncaissementPage({super.key});

  @override
  State<CaisseEncaissementPage> createState() => _CaisseEncaissementPageState();
}

class _CaisseEncaissementPageState extends State<CaisseEncaissementPage> {
  CaisseMouvement? _selectedRecu;

  static String _clientDe(CaisseMouvement m) =>
      _dossierById(m.dossierId)?.client.nom ?? '';

  static final _recuColumns = <ErpGridColumn<CaisseMouvement>>[
    ErpGridColumn(label: 'N° reçu', width: 110, value: (m) => m.recu),
    ErpGridColumn(label: 'Date', width: 105, value: (m) => m.date),
    ErpGridColumn(label: 'Client', width: 190, value: _clientDe),
    ErpGridColumn(
      label: 'Facture',
      width: 160,
      value: (m) => _dossierById(m.dossierId)?.factureClient.reference ?? '',
    ),
    ErpGridColumn(label: 'Statut', width: 120, value: (m) => m.statutReglement),
    ErpGridColumn(label: 'Mode', width: 110, value: (m) => m.modePaiement),
    ErpGridColumn(
      label: 'Montant',
      width: 130,
      numeric: true,
      value: (m) => formatCurrency(m.montant),
      sortValue: (m) => m.montant,
    ),
    ErpGridColumn(label: 'Caissière', width: 150, value: (m) => m.auteur),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isCaissierDepenses) {
      return const ModulePlaceholderPage(
        title: 'Accès non autorisé',
        icon: Icons.lock_outline_rounded,
        moduleTitle: 'Caisse',
      );
    }
    final today = _todayFr;
    final solde = soldeCaisse(caissePrincipale, _caisseMouvements);
    final recus =
        _caisseMouvements
            .where((m) => m.type == CaisseMouvement.encaissement)
            .toList()
          ..sort((a, b) => b.recuNumero.compareTo(a.recuNumero));
    final duJour = recus.where((m) => m.date == today).toList();
    final encaisse = duJour.fold<double>(0, (s, m) => s + m.montant);
    final reste = _dossiers.fold<double>(
      0,
      (s, d) =>
          s + (d.totalFacturesClient > 0 ? math.max(0, d.soldeClient) : 0),
    );
    final pending = _virementsAReceptionner(caissePrincipale);
    final selected = recus.where((m) => m.id == _selectedRecu?.id).firstOrNull;
    final alerte = _caisseAlerte(
      caissePrincipale,
      onReopen: () async {
        if (await _declotureCaisse(context, caissePrincipale) && mounted) {
          setState(() {});
        }
      },
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _caisseCard(
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _caisseHeader(
                    Icons.savings_rounded,
                    'Caisse Encaissement',
                    'Caisse principale : encaissement des factures clients, reçus de caisse et approvisionnement de la caisse des dépenses.',
                    const [_caisseGreen, Color(0xFF22C55E)],
                  ),
                  const SizedBox(width: 12),
                  ErpActionButton(
                    key: const ValueKey('caisse-appro'),
                    label: 'Approvisionner la caisse dépenses',
                    icon: Icons.move_up_rounded,
                    primary: true,
                    color: _caisseGreen,
                    onPressed: solde <= 0
                        ? null
                        : () async {
                            await _faireVirement(
                              context,
                              CaisseMouvement.approvisionnement,
                            );
                            if (mounted) setState(() {});
                          },
                  ),
                  if (pending.isNotEmpty)
                    ErpActionButton(
                      key: const ValueKey('caisse-reception-principale'),
                      label:
                          'Réceptionner les reversements (${pending.length})',
                      icon: Icons.move_down_rounded,
                      onPressed: () async {
                        await _receptionnerVirements(context, caissePrincipale);
                        if (mounted) setState(() {});
                      },
                    ),
                  if (_isDirectionUser)
                    ErpActionButton(
                      key: const ValueKey('caisse-parametres'),
                      label: 'Paramètres des caisses',
                      icon: Icons.settings_rounded,
                      onPressed: () async {
                        await _editCaisseParametres(context);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ),
            if (alerte != null) ...[const SizedBox(height: 12), alerte],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ErpMetricTile(
                  label: 'Solde caisse principale',
                  value: _amountText(solde),
                  color: _gridAccent,
                  icon: Icons.account_balance_wallet_rounded,
                ),
                ErpMetricTile(
                  label: 'Encaissé aujourd’hui',
                  value: _amountText(encaisse),
                  color: _caisseGreen,
                  icon: Icons.south_west_rounded,
                ),
                ErpMetricTile(
                  label: 'Reste à encaisser (clients)',
                  value: _amountText(reste),
                  color: _caisseRed,
                  icon: Icons.pending_actions_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ImpayesPanel(onEncaisser: _encaisser),
            const SizedBox(height: 12),
            _caisseCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Reçus de caisse (${recus.length}) • aujourd’hui : ${duJour.length}',
                        style: const TextStyle(
                          color: _gridText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ErpActionButton(
                        key: const ValueKey('recu-print'),
                        label: 'Imprimer le reçu',
                        icon: Icons.print_rounded,
                        onPressed: selected == null
                            ? null
                            : () => _printRecuCaisse(selected),
                      ),
                      ErpActionButton(
                        key: const ValueKey('recu-cancel'),
                        label: 'Annuler',
                        icon: Icons.undo_rounded,
                        color: _caisseRed,
                        onPressed: selected == null
                            ? null
                            : () => _annuler(selected),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: ErpGrid<CaisseMouvement>(
                      key: const ValueKey('recus-grid'),
                      columns: _recuColumns,
                      rows: recus,
                      rowId: (m) => m.id,
                      selected: selected,
                      onSelect: (m) => setState(() => _selectedRecu = m),
                      onOpen: _printRecuCaisse,
                      emptyText: 'Aucun reçu de caisse.',
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

  Future<void> _encaisser(TransitDossier dossier) async {
    final result = await showDialog<_Encaissement>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EncaissementDialog(dossier: dossier),
    );
    if (result == null || !mounted) return;
    CaisseMouvement? recu;
    if (!await _persist(context, () async {
      recu = await erpBackend.encaisser(
        dossier: dossier,
        statut: result.statut,
        montant: result.montant,
        modePaiement: result.mode,
        observations: result.observations,
      );
    })) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _caisseMouvements.add(recu!);
      _selectedRecu = recu;
    });
    final print = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reçu de caisse ${recu!.recu}'),
        content: Text(
          '${_amountText(recu!.montant)} encaissé de ${dossier.client.nom} (${recu!.statutReglement}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Imprimer le reçu'),
          ),
        ],
      ),
    );
    if (print == true) await _printRecuCaisse(recu!);
  }

  Future<void> _annuler(CaisseMouvement recu) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Annuler le reçu ${recu.recu} ?'),
        content: Text(
          '${_amountText(recu.montant)} • ${_clientDe(recu)}\nLe règlement est retiré de la facture du client.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _caisseRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler le reçu'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.annulerMouvementCaisse(
        recu,
        dossier: _dossierById(recu.dossierId),
      ),
    )) {
      return;
    }
    if (mounted) {
      setState(() {
        _caisseMouvements.remove(recu);
        _selectedRecu = null;
      });
    }
  }
}

typedef _Encaissement = ({
  String statut,
  double montant,
  String mode,
  String observations,
});

// La caissière pointe le règlement : « Non payé » par défaut, « Payé » solde la
// facture, « Commencement » enregistre un paiement partiel.
class _EncaissementDialog extends StatefulWidget {
  final TransitDossier dossier;

  const _EncaissementDialog({required this.dossier});

  @override
  State<_EncaissementDialog> createState() => _EncaissementDialogState();
}

class _EncaissementDialogState extends State<_EncaissementDialog> {
  String _statut = 'Non payé';
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String? _mode;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _reste => widget.dossier.soldeClient;

  double? get _montant => switch (_statut) {
    statutPaye => _reste,
    statutCommencement => _parseMontant(_amount.text),
    _ => null,
  };

  String? get _error {
    if (_statut != statutCommencement) return null;
    final value = _montant;
    if (value == null || value <= 0) return 'Saisissez le montant reçu';
    if (value >= _reste) {
      return 'Le commencement doit être inférieur au reste (${_amountText(_reste)}). Choisissez « Payé ».';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dossier;
    final canSave = _statut != 'Non payé' && _error == null;
    return AlertDialog(
      title: Text('Encaissement • ${d.factureClient.reference}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d.client.nom}  •  compte ${d.client.compteComptable}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dossier ${d.numDossier} • BL ${d.numBL} • ${_marchandiseDossier(d)}',
                    ),
                    const SizedBox(height: 8),
                    Text('Facturé : ${_amountText(d.totalFacturesClient)}'),
                    Text(
                      'Déjà réglé : ${_amountText(d.totalReglementsClient)}',
                    ),
                    Text(
                      'Non réglé : ${_amountText(_reste)}',
                      style: const TextStyle(
                        color: _caisseRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const ValueKey('encaissement-statut'),
                initialValue: _statut,
                isExpanded: true,
                decoration: _inputDecoration(
                  'Règlement',
                  icon: Icons.fact_check_rounded,
                ),
                items: const [
                  DropdownMenuItem(value: 'Non payé', child: Text('Non payé')),
                  DropdownMenuItem(
                    value: statutPaye,
                    child: Text('Payé (solde la facture)'),
                  ),
                  DropdownMenuItem(
                    value: statutCommencement,
                    child: Text('Commencement (paiement partiel)'),
                  ),
                ],
                onChanged: (v) => setState(() => _statut = v ?? _statut),
              ),
              const SizedBox(height: 12),
              if (_statut == statutCommencement)
                TextField(
                  key: const ValueKey('encaissement-amount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    'Montant reçu *',
                    icon: Icons.payments_outlined,
                  ).copyWith(errorText: _amount.text.isEmpty ? null : _error),
                )
              else if (_statut == statutPaye)
                Text(
                  'Montant encaissé : ${_amountText(_reste)}',
                  style: const TextStyle(
                    color: _caisseGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                isExpanded: true,
                decoration: _inputDecoration(
                  'Mode de paiement',
                  icon: Icons.credit_card_rounded,
                ),
                items: [
                  for (final mode in {
                    'Espèces',
                    ..._modesReglement.map((m) => m.intitule),
                  })
                    DropdownMenuItem(value: mode, child: Text(mode)),
                ],
                onChanged: (v) => setState(() => _mode = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: _inputDecoration(
                  'Observations',
                  icon: Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'La caisse pointe le règlement ; l’imputation comptable est faite par la comptabilité.',
                style: TextStyle(color: _gridMuted, fontSize: 12),
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
        FilledButton.icon(
          key: const ValueKey('encaissement-save'),
          style: FilledButton.styleFrom(backgroundColor: _caisseGreen),
          onPressed: canSave
              ? () => Navigator.pop<_Encaissement>(context, (
                  statut: _statut,
                  montant: _montant!,
                  mode: _mode ?? 'Espèces',
                  observations: _notes.text.trim(),
                ))
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Valider l’encaissement'),
        ),
      ],
    );
  }
}

// --- CAISSE DÉPENSES ---

class CaisseDepensesPage extends StatefulWidget {
  const CaisseDepensesPage({super.key});

  @override
  State<CaisseDepensesPage> createState() => _CaisseDepensesPageState();
}

class _CaisseDepensesPageState extends State<CaisseDepensesPage> {
  final _search = TextEditingController();
  BonCaisse? _bon;
  bool _searched = false;
  DateTime? _histDu = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _histAu = DateUtils.dateOnly(DateTime.now());
  String _histType = 'Tous';

  static const _histTypes = [
    'Tous',
    CaisseMouvement.approvisionnement,
    CaisseMouvement.paiementBon,
    CaisseMouvement.reversement,
  ];

  // Mouvements de la caisse des dépenses (entrées et sorties) sur la période.
  List<CaisseEvenement> get _historique {
    final events = evenementsCaisse(caisseDepenses, _caisseMouvements)
        .where(
          (e) =>
              (_histType == 'Tous' || e.mouvement.type == _histType) &&
              _inPeriod(_parseFrDate(e.date), _histDu, _histAu),
        )
        .toList();
    events.sort(
      (a, b) => (_parseFrDate(b.date) ?? DateTime(0)).compareTo(
        _parseFrDate(a.date) ?? DateTime(0),
      ),
    );
    return events;
  }

  static BonCaisse? _bonDe(CaisseMouvement m) =>
      _bonsCaisse.where((b) => b.id == m.bonId).firstOrNull;

  static final _histColumns = <ErpGridColumn<CaisseEvenement>>[
    ErpGridColumn(
      label: 'Date',
      width: 105,
      value: (e) => e.date,
      sortValue: (e) => _parseFrDate(e.date) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Opération',
      width: 170,
      value: (e) => e.mouvement.type,
    ),
    ErpGridColumn(
      label: 'N° bon',
      width: 110,
      value: (e) => _bonDe(e.mouvement)?.reference ?? '',
    ),
    ErpGridColumn(
      label: 'Bénéficiaire / détail',
      width: 280,
      value: (e) {
        final bon = _bonDe(e.mouvement);
        if (bon != null) {
          return [
            bon.beneficiaire,
            bon.motif,
          ].where((t) => t.isNotEmpty).join(' - ');
        }
        return e.mouvement.type == CaisseMouvement.approvisionnement
            ? 'Reçu de la caisse principale'
            : 'Reversé à la caisse principale';
      },
    ),
    ErpGridColumn(
      label: 'Entrée',
      width: 130,
      numeric: true,
      value: (e) => e.recette == 0 ? '' : formatCurrency(e.recette),
      sortValue: (e) => e.recette,
    ),
    ErpGridColumn(
      label: 'Sortie',
      width: 130,
      numeric: true,
      value: (e) => e.depense == 0 ? '' : formatCurrency(e.depense),
      sortValue: (e) => e.depense,
    ),
    ErpGridColumn(label: 'Par', width: 150, value: (e) => e.mouvement.auteur),
  ];

  Widget _historiqueCard() {
    final rows = _historique;
    final entrees = rows.fold<double>(0, (s, e) => s + e.recette);
    final sorties = rows.fold<double>(0, (s, e) => s + e.depense);
    return _caisseCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Historique des dépenses et approvisionnements',
                style: TextStyle(
                  color: _gridText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ErpDateFilter(
                label: 'Date début',
                value: _histDu,
                onChanged: (v) => setState(() => _histDu = v),
              ),
              ErpDateFilter(
                label: 'Date fin',
                value: _histAu,
                onChanged: (v) => setState(() => _histAu = v),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('historique-type'),
                  initialValue: _histType,
                  isExpanded: true,
                  decoration: _inputDecoration('Opération'),
                  items: [
                    for (final t in _histTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _histType = v ?? _histType),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Exporter (Excel)',
                onPressed: () => _exportGrid(
                  context,
                  baseName: 'historique_caisse_depenses',
                  columns: _histColumns,
                  rows: rows,
                ),
                icon: const Icon(Icons.table_chart_rounded),
              ),
              Text(
                'Entrées ${_amountText(entrees)} • Sorties ${_amountText(sorties)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ErpGrid<CaisseEvenement>(
              key: const ValueKey('historique-grid'),
              columns: _histColumns,
              rows: rows,
              rowId: (e) => '${e.mouvement.id}|${e.date}|${e.recette}',
              filterable: true,
              emptyText: 'Aucun mouvement sur cette période.',
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // « BC-00012 », « 00012 », « 12 » ou le numéro du bon manuel.
  void _find() {
    final text = _search.text.trim();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final numero = int.tryParse(digits);
    setState(() {
      _searched = true;
      _bon =
          _bonsCaisse
              .where((b) => numero != null && b.numero == numero)
              .firstOrNull ??
          _bonsCaisse
              .where(
                (b) =>
                    text.isNotEmpty &&
                    b.referenceManuelle.toLowerCase() == text.toLowerCase(),
              )
              .firstOrNull;
    });
  }

  static final _bonColumns = <ErpGridColumn<BonCaisse>>[
    ErpGridColumn(label: 'N° bon', width: 110, value: (b) => b.reference),
    ErpGridColumn(label: 'Date', width: 105, value: (b) => b.date),
    ErpGridColumn(label: 'Nature', width: 170, value: (b) => b.categorie),
    ErpGridColumn(
      label: 'Bénéficiaire',
      width: 180,
      value: (b) => b.beneficiaire,
    ),
    ErpGridColumn(label: 'Motif', width: 200, value: (b) => b.motif),
    ErpGridColumn(
      label: 'Montant',
      width: 130,
      numeric: true,
      value: (b) => formatCurrency(b.montant),
      sortValue: (b) => b.montant,
    ),
    ErpGridColumn(
      label: 'Paiement',
      width: 170,
      value: (b) {
        final m = _paiementDuBon(b);
        return m == null ? 'À payer' : 'Payé le ${m.date}';
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isCaissierPrincipal) {
      return const ModulePlaceholderPage(
        title: 'Accès non autorisé',
        icon: Icons.lock_outline_rounded,
        moduleTitle: 'Caisse',
      );
    }
    final today = _todayFr;
    final solde = soldeCaisse(caisseDepenses, _caisseMouvements);
    final aPayer = _bonsCaisse.where((b) => _paiementDuBon(b) == null).toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));
    final payesDuJour = _caisseMouvements
        .where((m) => m.type == CaisseMouvement.paiementBon && m.date == today)
        .toList();
    final pending = _virementsAReceptionner(caisseDepenses);
    final alerte = _caisseAlerte(
      caisseDepenses,
      onReopen: () async {
        if (await _declotureCaisse(context, caisseDepenses) && mounted) {
          setState(() {});
        }
      },
    );
    final bon = _bonsCaisse.where((b) => b.id == _bon?.id).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _caisseCard(
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _caisseHeader(
                    Icons.payments_rounded,
                    'Caisse Dépenses',
                    'Tapez le numéro du bon de caisse, vérifiez la dépense, payez et validez. Reversez le reliquat en fin de journée.',
                    const [_purple, Color(0xFFA855F7)],
                  ),
                  const SizedBox(width: 12),
                  if (pending.isNotEmpty)
                    ErpActionButton(
                      key: const ValueKey('caisse-reception-depenses'),
                      label:
                          'Réceptionner l’approvisionnement (${pending.length})',
                      icon: Icons.move_down_rounded,
                      primary: true,
                      color: _purple,
                      onPressed: () async {
                        await _receptionnerVirements(context, caisseDepenses);
                        if (mounted) setState(() {});
                      },
                    ),
                  ErpActionButton(
                    key: const ValueKey('caisse-reversement'),
                    label: 'Reverser le reliquat',
                    icon: Icons.move_up_rounded,
                    onPressed: solde <= 0
                        ? null
                        : () async {
                            await _faireVirement(
                              context,
                              CaisseMouvement.reversement,
                            );
                            if (mounted) setState(() {});
                          },
                  ),
                  if (_isDirectionUser)
                    ErpActionButton(
                      label: 'Paramètres des caisses',
                      icon: Icons.settings_rounded,
                      onPressed: () async {
                        await _editCaisseParametres(context);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ),
            if (alerte != null) ...[const SizedBox(height: 12), alerte],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ErpMetricTile(
                  label: 'Solde caisse des dépenses',
                  value: _amountText(solde),
                  color: _purple,
                  icon: Icons.account_balance_wallet_rounded,
                ),
                ErpMetricTile(
                  label: 'Payé aujourd’hui',
                  value: _amountText(
                    payesDuJour.fold<double>(0, (s, m) => s + m.montant),
                  ),
                  color: _caisseRed,
                  icon: Icons.north_east_rounded,
                ),
                ErpMetricTile(
                  label: 'Bons à payer (${aPayer.length})',
                  value: _amountText(
                    aPayer.fold<double>(0, (s, b) => s + b.montant),
                  ),
                  color: _caisseOrange,
                  icon: Icons.pending_actions_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _caisseCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          key: const ValueKey('bon-search'),
                          controller: _search,
                          onSubmitted: (_) => _find(),
                          decoration: InputDecoration(
                            labelText: 'N° du bon de caisse',
                            hintText: 'BC-00012 ou 12',
                            isDense: true,
                            prefixIcon: const Icon(Icons.qr_code_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      ErpActionButton(
                        key: const ValueKey('bon-search-go'),
                        label: 'Rechercher',
                        icon: Icons.search_rounded,
                        primary: true,
                        color: _purple,
                        onPressed: _find,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (bon != null)
                    _bonDetails(bon, solde)
                  else if (_searched)
                    const Text(
                      'Aucun bon de caisse ne porte ce numéro.',
                      style: TextStyle(color: _caisseRed),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _caisseCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bons de caisse à payer (${aPayer.length})',
                    style: const TextStyle(
                      color: _gridText,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 280,
                    child: ErpGrid<BonCaisse>(
                      key: const ValueKey('bons-a-payer-grid'),
                      columns: _bonColumns,
                      rows: aPayer,
                      rowId: (b) => b.id,
                      selected: bon,
                      onSelect: (b) => setState(() {
                        _bon = b;
                        _search.text = b.reference;
                      }),
                      emptyIcon: Icons.verified_rounded,
                      emptyText: 'Tous les bons de caisse sont payés.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _historiqueCard(),
          ],
        ),
      ),
    );
  }

  Widget _bonDetails(BonCaisse bon, double solde) {
    final paiement = _paiementDuBon(bon);
    final camions = bon.categorie == BonCaisse.fraisCamion;
    return Container(
      key: const ValueKey('bon-details'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Bon ${bon.reference}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              Chip(label: Text(bon.categorie)),
              Chip(
                backgroundColor: paiement == null
                    ? const Color(0xFFFFEDD5)
                    : const Color(0xFFDCFCE7),
                label: Text(
                  paiement == null
                      ? 'À payer'
                      : 'Payé le ${paiement.date} par ${paiement.auteur}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              'Du ${bon.date}',
              if (bon.beneficiaire.isNotEmpty)
                'Bénéficiaire : ${bon.beneficiaire}',
              if (bon.motif.isNotEmpty) 'Motif : ${bon.motif}',
              if (bon.referenceManuelle.isNotEmpty)
                'Bon manuel : ${bon.referenceManuelle}',
              'Saisi par ${bon.auteur}',
            ].join('  •  '),
          ),
          const SizedBox(height: 10),
          for (final l in bon.lignes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      camions
                          ? [
                              l.plaque,
                              l.proprietaire == 'STT'
                                  ? 'STT'
                                  : _partnerLabel(l.transporteurId),
                              _dossierById(l.dossierId)?.numDossier ?? '',
                              l.chauffeur,
                              l.libelle.isEmpty
                                  ? _typeFraisLabel(l.typeFraisId)
                                  : l.libelle,
                            ].where((s) => s.isNotEmpty).join(' • ')
                          : '${l.libelle} • ${l.compte}',
                    ),
                  ),
                  Text(
                    _amountText(l.montant),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TOTAL',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _amountText(bon.montant),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _purple,
                ),
              ),
            ],
          ),
          if (paiement == null && bon.montant > solde)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Solde de la caisse insuffisant (${_amountText(solde)}) : demandez un approvisionnement à la caisse principale.',
                style: const TextStyle(color: _caisseRed),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (paiement == null)
                ErpActionButton(
                  key: const ValueKey('bon-pay'),
                  label: 'Payer et valider',
                  icon: Icons.check_circle_rounded,
                  primary: true,
                  color: _caisseGreen,
                  onPressed: bon.montant > solde ? null : () => _payer(bon),
                ),
              ErpActionButton(
                label: 'Imprimer le bon',
                icon: Icons.print_rounded,
                onPressed: () => _printBonCaisse(bon),
              ),
              if (paiement != null)
                ErpActionButton(
                  label: 'Annuler le paiement',
                  icon: Icons.undo_rounded,
                  color: _caisseRed,
                  onPressed: () => _annuler(paiement),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _payer(BonCaisse bon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Payer le bon ${bon.reference} ?'),
        content: Text(
          '${_amountText(bon.montant)} remis à ${bon.beneficiaire.isEmpty ? 'au bénéficiaire' : bon.beneficiaire}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('bon-pay-confirm'),
            style: FilledButton.styleFrom(backgroundColor: _caisseGreen),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Payer et valider'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    CaisseMouvement? paiement;
    if (!await _persist(context, () async {
      paiement = await erpBackend.payerBonCaisse(bon);
    })) {
      return;
    }
    if (mounted) setState(() => _caisseMouvements.add(paiement!));
  }

  Future<void> _annuler(CaisseMouvement paiement) async {
    if (!await _persist(
      context,
      () => erpBackend.annulerMouvementCaisse(paiement),
    )) {
      return;
    }
    if (mounted) setState(() => _caisseMouvements.remove(paiement));
  }
}

// --- RELEVÉ DE CAISSE ---

class _ReleveLine {
  final DateTime? date;
  final String recu;
  final String bon;
  final String compteTiers;
  final String intitule;
  final String libelle;
  final double recette;
  final double depense;
  final double solde;
  // Ligne « Report à nouveau » ou « Totaux de caisse ».
  final bool special;
  final int order;

  const _ReleveLine({
    this.date,
    this.recu = '',
    this.bon = '',
    this.compteTiers = '',
    this.intitule = '',
    required this.libelle,
    this.recette = 0,
    this.depense = 0,
    required this.solde,
    this.special = false,
    required this.order,
  });
}

class ReleveCaissePage extends StatefulWidget {
  const ReleveCaissePage({super.key});

  @override
  State<ReleveCaissePage> createState() => _ReleveCaissePageState();
}

class _ReleveCaissePageState extends State<ReleveCaissePage> {
  late String _caisse = _isCaissierDepenses ? caisseDepenses : caissePrincipale;
  DateTime? _start = DateUtils.dateOnly(DateTime.now());
  DateTime? _end = DateUtils.dateOnly(DateTime.now());
  String _query = '';

  static final _dateFormat = DateFormat('dd/MM/yy');

  bool get _caisseImposee => _isCaissierPrincipal || _isCaissierDepenses;

  _ReleveLine _ligne(CaisseEvenement e, int order, double solde) {
    final m = e.mouvement;
    final date = _parseFrDate(e.date);
    switch (m.type) {
      case CaisseMouvement.encaissement:
        final d = _dossierById(m.dossierId);
        return _ReleveLine(
          date: date,
          recu: m.recu,
          compteTiers: d?.client.compteComptable ?? '',
          intitule: d?.client.nom ?? '',
          libelle: [
            'Règlement ${d?.factureClient.reference ?? ''}',
            m.statutReglement,
            if (m.modePaiement.isNotEmpty) m.modePaiement,
          ].join(' - '),
          recette: e.recette,
          solde: solde,
          order: order,
        );
      case CaisseMouvement.paiementBon:
        final bon = _bonsCaisse.where((b) => b.id == m.bonId).firstOrNull;
        return _ReleveLine(
          date: date,
          bon: bon?.reference ?? '',
          intitule: bon?.beneficiaire ?? '',
          libelle: [
            bon?.categorie ?? 'Bon de caisse',
            if ((bon?.motif ?? '').isNotEmpty) bon!.motif,
          ].join(' - '),
          depense: e.depense,
          solde: solde,
          order: order,
        );
      default:
        final sortie = m.caisseSource == _caisse;
        return _ReleveLine(
          date: date,
          libelle: m.type == CaisseMouvement.approvisionnement
              ? (sortie
                    ? 'Approvisionnement de la caisse des dépenses'
                    : 'Approvisionnement reçu de la caisse principale')
              : (sortie
                    ? 'Reversement du reliquat à la caisse principale'
                    : 'Reversement reçu de la caisse des dépenses'),
          recette: e.recette,
          depense: e.depense,
          solde: solde,
          order: order,
        );
    }
  }

  ({List<_ReleveLine> lines, double report, double recettes, double depenses})
  get _releve {
    final events = evenementsCaisse(_caisse, _caisseMouvements)
      ..sort(
        (a, b) => (_parseFrDate(a.date) ?? DateTime(0)).compareTo(
          _parseFrDate(b.date) ?? DateTime(0),
        ),
      );
    var report = 0.0;
    final inPeriod = <CaisseEvenement>[];
    for (final e in events) {
      final date = _parseFrDate(e.date);
      if (_start != null && date != null && date.isBefore(_start!)) {
        report += e.recette - e.depense;
      } else if (_inPeriod(date, _start, _end)) {
        inPeriod.add(e);
      }
    }
    var solde = report;
    var order = 0;
    final lines = <_ReleveLine>[
      if (_start != null)
        _ReleveLine(
          date: _start,
          libelle: 'Report à nouveau',
          solde: report,
          special: true,
          order: order++,
        ),
    ];
    for (final e in inPeriod) {
      solde += e.recette - e.depense;
      lines.add(_ligne(e, order++, solde));
    }
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? lines
        : lines
              .where(
                (l) =>
                    l.special ||
                    '${l.recu} ${l.bon} ${l.compteTiers} ${l.intitule} ${l.libelle}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
    final body = visible.where((l) => !l.special);
    return (
      lines: visible,
      report: report,
      recettes: body.fold(0, (s, l) => s + l.recette),
      depenses: body.fold(0, (s, l) => s + l.depense),
    );
  }

  static Widget _cell(_ReleveLine l, String text, {Color? color}) => Text(
    text,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color,
      fontWeight: l.special ? FontWeight.bold : FontWeight.normal,
    ),
  );

  static String _num(double v) => v == 0 ? '' : formatCurrency(v);

  // Caisse principale : N° de reçu et client ; caisse des dépenses : N° de bon
  // et bénéficiaire.
  List<ErpGridColumn<_ReleveLine>> get _columns => [
    ErpGridColumn(
      label: 'Date',
      width: 95,
      value: (l) => l.date == null ? '' : _dateFormat.format(l.date!),
    ),
    if (_caisse == caissePrincipale)
      ErpGridColumn(
        label: 'N° reçu de caisse',
        width: 150,
        value: (l) => l.recu,
      )
    else
      ErpGridColumn(label: 'N° bon de caisse', width: 150, value: (l) => l.bon),
    ErpGridColumn(
      label: _caisse == caissePrincipale ? 'Intitulé client' : 'Bénéficiaire',
      width: 230,
      value: (l) => l.intitule,
    ),
    ErpGridColumn(
      label: 'Libellé',
      width: 300,
      value: (l) => l.libelle,
      builder: (l) => _cell(l, l.libelle),
    ),
    ErpGridColumn(
      label: 'Recettes',
      width: 130,
      numeric: true,
      value: (l) => _num(l.recette),
      builder: (l) => _cell(l, _num(l.recette), color: _caisseGreen),
    ),
    ErpGridColumn(
      label: 'Dépenses',
      width: 130,
      numeric: true,
      value: (l) => _num(l.depense),
      builder: (l) => _cell(l, _num(l.depense), color: _caisseRed),
    ),
    ErpGridColumn(
      label: 'Solde',
      width: 140,
      numeric: true,
      value: (l) => formatCurrency(l.solde),
      builder: (l) => _cell(l, formatCurrency(l.solde), color: _gridPrimary),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final releve = _releve;
    final soldeFinal = releve.report + releve.recettes - releve.depenses;
    final rows = [
      ...releve.lines,
      _ReleveLine(
        libelle: 'TOTAUX DE CAISSE',
        recette: releve.recettes,
        depense: releve.depenses,
        solde: soldeFinal,
        special: true,
        order: -1,
      ),
    ];
    final cloture = _clotureDuJour(_caisse);
    final canClose =
        cloture == null &&
        (_caisse == caissePrincipale
            ? !_isCaissierDepenses
            : !_isCaissierPrincipal);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_gridPrimary, _gridAccent],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    'Relevé de Caisse • ${_caisseLabel(_caisse)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canClose)
                        FilledButton.icon(
                          key: const ValueKey('caisse-cloture'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFBBF24),
                            foregroundColor: _gridText,
                          ),
                          onPressed: _cloturer,
                          icon: const Icon(Icons.lock_clock_rounded),
                          label: const Text('Clôturer la caisse du jour'),
                        ),
                      FilledButton.icon(
                        key: const ValueKey('releve-print'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _gridPrimary,
                        ),
                        onPressed: () => _printReleve(rows),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Imprimer / PDF'),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Exporter (Excel)',
                        onPressed: () => _exportGrid(
                          context,
                          baseName: 'releve_caisse',
                          columns: _columns,
                          rows: rows,
                        ),
                        icon: const Icon(Icons.table_chart_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (cloture != null) ...[
              const SizedBox(height: 12),
              _caisseAlerte(
                _caisse,
                onReopen: () async {
                  if (await _declotureCaisse(context, _caisse) && mounted) {
                    setState(() {});
                  }
                },
              )!,
            ],
            const SizedBox(height: 12),
            _caisseCard(
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('releve-caisse'),
                      initialValue: _caisse,
                      isExpanded: true,
                      decoration: _inputDecoration(
                        'Caisse',
                        icon: Icons.point_of_sale_rounded,
                      ),
                      items: [
                        for (final c in [caissePrincipale, caisseDepenses])
                          DropdownMenuItem(
                            value: c,
                            child: Text(_caisseLabel(c)),
                          ),
                      ],
                      onChanged: _caisseImposee
                          ? null
                          : (v) => setState(() => _caisse = v ?? _caisse),
                    ),
                  ),
                  ErpDateFilter(
                    label: 'Date début',
                    value: _start,
                    onChanged: (value) => setState(() => _start = value),
                  ),
                  ErpDateFilter(
                    label: 'Date fin',
                    value: _end,
                    onChanged: (value) => setState(() => _end = value),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'N° reçu, N° bon, client…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ErpMetricTile(
                  label: 'Report à nouveau',
                  value: _amountText(releve.report),
                  color: _gridMuted,
                  icon: Icons.history_rounded,
                ),
                ErpMetricTile(
                  label: 'Recettes',
                  value: _amountText(releve.recettes),
                  color: _caisseGreen,
                  icon: Icons.south_west_rounded,
                ),
                ErpMetricTile(
                  label: 'Dépenses',
                  value: _amountText(releve.depenses),
                  color: _caisseRed,
                  icon: Icons.north_east_rounded,
                ),
                ErpMetricTile(
                  label: 'Solde de caisse',
                  value: _amountText(soldeFinal),
                  color: _gridAccent,
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(440, constraints.maxHeight - 300),
              child: ErpGrid<_ReleveLine>(
                key: const ValueKey('releve-grid'),
                columns: _columns,
                rows: rows,
                rowId: (l) => '${l.order}',
                emptyIcon: Icons.account_balance_wallet_outlined,
                emptyText: 'Aucun mouvement de caisse pour cette période.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cloturer() async {
    final today = _todayFr;
    final events = evenementsCaisse(_caisse, _caisseMouvements);
    final duJour = events.where((e) => e.date == today);
    final recettes = duJour.fold<double>(0, (s, e) => s + e.recette);
    final depenses = duJour.fold<double>(0, (s, e) => s + e.depense);
    final solde = soldeCaisse(_caisse, _caisseMouvements);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Clôturer la ${_caisseLabel(_caisse).toLowerCase()} du $today ?',
        ),
        content: Text(
          'Recettes du jour : ${_amountText(recettes)}\nDépenses du jour : ${_amountText(depenses)}\nSolde en caisse : ${_amountText(solde)}\n\nAprès la clôture, plus aucun mouvement ne peut être fait ni annulé dans cette caisse aujourd’hui.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('caisse-cloture-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    CaisseCloture? cloture;
    if (!await _persist(context, () async {
      cloture = await erpBackend.cloturerCaisse(_caisse);
    })) {
      return;
    }
    if (mounted) setState(() => _caisseClotures.add(cloture!));
  }

  Future<void> _printReleve(List<_ReleveLine> rows) async {
    final logo = await _loadPdfLogo();
    const headerColor = PdfColor.fromInt(0xFF37474F);
    final principale = _caisse == caissePrincipale;
    final period =
        'Période du ${_start == null ? '…' : _dateFormat.format(_start!)} au ${_end == null ? '…' : _dateFormat.format(_end!)}';
    final doc = pw.Document(
      title: 'Relevé de caisse',
      author: 'Sylla Transit & Transport',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
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
                      _caisseLabel(_caisse),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'RELEVÉ DE CAISSE',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(period, style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Sylla Transit & Transport  |  Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              principale ? 'N° reçu de caisse' : 'N° bon de caisse',
              principale ? 'Intitulé client' : 'Bénéficiaire',
              'Libellé',
              'Recettes',
              'Dépenses',
              'Solde',
            ],
            data: [
              for (final l in rows)
                [
                  l.date == null ? '' : _dateFormat.format(l.date!),
                  principale ? l.recu : l.bon,
                  l.intitule,
                  l.libelle.replaceAll('•', '-'),
                  _num(l.recette),
                  _num(l.depense),
                  formatCurrency(l.solde),
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 10.5,
            ),
            headerDecoration: const pw.BoxDecoration(color: headerColor),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 6,
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(2.8),
              4: const pw.FlexColumnWidth(1.1),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.2),
            },
            cellAlignments: {
              for (var i = 4; i < 7; i++) i: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['La caissière', 'Visa Direction'])
                pw.Column(
                  children: [
                    pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 36),
                    pw.Container(
                      width: 160,
                      height: 0.6,
                      color: PdfColors.grey700,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Releve de caisse',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => doc.save(),
    );
  }
}

// --- DOCUMENTS ---

Future<void> _printRecuCaisse(CaisseMouvement recu) async {
  final logo = await _loadPdfLogo();
  final d = _dossierById(recu.dossierId);
  final doc = pw.Document(
    title: 'Reçu de caisse ${recu.recu}',
    author: 'Sylla Transit & Transport',
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.Image(logo, height: 38),
                pw.SizedBox(width: 8),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'STT',
                    style: pw.TextStyle(
                      color: _pdfPrimary,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'SYLLA TRANSIT & TRANSPORT',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'REÇU DE CAISSE',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'N° ${recu.recu}',
                    style: pw.TextStyle(
                      color: _pdfPrimary,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'du ${recu.date}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _pdfInfoGrid([
            ('Client', d?.client.nom ?? ''),
            ('Compte tiers', d?.client.compteComptable ?? ''),
            ('Facture', d?.factureClient.reference ?? ''),
            ('Dossier', d?.numDossier ?? ''),
            ('N° BL', d?.numBL ?? ''),
            ('Marchandise', d == null ? '' : _marchandiseDossier(d)),
            ('Règlement', recu.statutReglement),
            ('Mode', recu.modePaiement),
          ]),
          pw.SizedBox(height: 12),
          _pdfTotals([
            ('MONTANT REÇU', '${formatCurrency(recu.montant)} FCFA'),
            if (d != null)
              (
                'Reste à payer',
                '${formatCurrency(math.max(0, d.soldeClient))} FCFA',
              ),
          ]),
          if (recu.observations.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Observations : ${recu.observations}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in [
                'La caissière (${recu.auteur})',
                'Le client',
              ])
                pw.Column(
                  children: [
                    pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 30),
                    pw.Container(
                      width: 130,
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
    name: 'Recu de caisse ${recu.recu}',
    format: PdfPageFormat.a5,
    onLayout: (_) => doc.save(),
  );
}

Future<void> _printEtatImpayes(List<TransitDossier> rows, String filter) async {
  final logo = await _loadPdfLogo();
  final doc = pw.Document(
    title: 'État des impayés',
    author: 'Sylla Transit & Transport',
  );
  double sum(double Function(TransitDossier) f) =>
      rows.fold(0, (s, d) => s + f(d));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 20),
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
                  'Factures : $filter • au $_todayFr',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'ÉTAT DES IMPAYÉS',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      build: (context) => [
        _pdfTable(
          [
            'N° facture',
            'Date',
            'Client',
            'Compte',
            'Dossier',
            'BL',
            'Marchandise',
            'Facturé',
            'Réglé',
            'Non réglé',
            'Statut',
          ],
          [
            for (final d in rows)
              [
                d.factureClient.reference,
                d.factureClient.dateEmission,
                d.client.nom,
                d.client.compteComptable,
                d.numDossier,
                d.numBL,
                _marchandiseDossier(d),
                formatCurrency(d.totalFacturesClient),
                formatCurrency(d.totalReglementsClient),
                formatCurrency(math.max(0, d.soldeClient)),
                _statutFactureClient(d),
              ],
            [
              '',
              '',
              'TOTAUX',
              '',
              '',
              '',
              '',
              formatCurrency(sum((d) => d.totalFacturesClient)),
              formatCurrency(sum((d) => d.totalReglementsClient)),
              formatCurrency(sum((d) => math.max(0, d.soldeClient))),
              '',
            ],
          ],
          numericColumns: {7, 8, 9},
          fontSize: 7.5,
        ),
      ],
    ),
  );
  await Printing.layoutPdf(
    name: 'Etat des impayes',
    format: PdfPageFormat.a4.landscape,
    onLayout: (_) => doc.save(),
  );
}
