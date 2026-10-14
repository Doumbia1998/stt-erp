part of '../main.dart';

// --- Fenêtres de la gestion des dossiers : saisie du dossier et facturation ---

const _containerTypeOptions = ['20 pieds', '40 pieds', '40 pieds HC', 'Autre'];

// En-tête dégradé commun aux fenêtres de saisie.
Widget _dialogHeader({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onClose,
}) => Container(
  padding: const EdgeInsets.fromLTRB(22, 16, 10, 16),
  decoration: const BoxDecoration(
    gradient: LinearGradient(colors: [_gridPrimary, _gridAccent]),
  ),
  child: Row(
    children: [
      CircleAvatar(
        backgroundColor: Colors.white24,
        child: Icon(icon, color: Colors.white),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Fermer',
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded, color: Colors.white),
      ),
    ],
  ),
);

Widget _dialogSection({
  required IconData icon,
  required String title,
  required Widget child,
  Widget? trailing,
}) => Container(
  margin: const EdgeInsets.only(bottom: 16),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _gridBorder),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 20, color: _gridAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _gridText,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
      const SizedBox(height: 14),
      child,
    ],
  ),
);

InputDecoration _inputDecoration(
  String label, {
  IconData? icon,
  String? hint,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  isDense: true,
  prefixIcon: icon == null ? null : Icon(icon, size: 19),
  filled: true,
  fillColor: const Color(0xFFFAFBFE),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
  ),
);

// Champ date de formulaire (sélecteur + effacement optionnel).
class _FormDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;

  const _FormDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? now,
        firstDate: DateTime(now.year - 15),
        lastDate: DateTime(now.year + 5),
        helpText: label,
        cancelText: 'Annuler',
        confirmText: 'Choisir',
      );
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: _inputDecoration(label, icon: Icons.event_rounded).copyWith(
        suffixIcon: clearable && value != null
            ? IconButton(
                tooltip: 'Effacer',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            : null,
      ),
      child: Text(
        value == null ? 'jj/mm/aaaa' : DateFormat('dd/MM/yyyy').format(value!),
        style: TextStyle(color: value == null ? _gridMuted : _gridText),
      ),
    ),
  );
}

// Tableau de saisie à colonnes fixes avec barre de défilement horizontale visible.
class _EditableTable extends StatefulWidget {
  final List<(String, double)> columns;
  final List<List<Widget>> rows;
  final List<Key>? rowKeys;
  final String emptyText;

  const _EditableTable({
    required this.columns,
    required this.rows,
    this.rowKeys,
    this.emptyText = 'Aucune ligne',
  });

  @override
  State<_EditableTable> createState() => _EditableTableState();
}

class _EditableTableState extends State<_EditableTable> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.columns.fold<double>(0, (sum, c) => sum + c.$2);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gridBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ScrollConfiguration(
        behavior: const _DragEverywhereBehavior(),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10,
          radius: const Radius.circular(8),
          interactive: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  Container(
                    height: 40,
                    color: const Color(0xFFEEF1FA),
                    child: Row(
                      children: [
                        for (final (label, columnWidth) in widget.columns)
                          Container(
                            width: columnWidth,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _gridPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        widget.emptyText,
                        style: const TextStyle(color: _gridMuted),
                      ),
                    ),
                  for (final (index, cells) in widget.rows.indexed)
                    Container(
                      key: widget.rowKeys?[index],
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: index.isEven
                            ? Colors.white
                            : const Color(0xFFF9FAFD),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFFEFF2F8)),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (final (i, cell) in cells.indexed)
                            Container(
                              width: widget.columns[i].$2,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: cell,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _cellDecoration({String? hint}) => InputDecoration(
  isDense: true,
  hintText: hint,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
  ),
);

class _ContainerDraft {
  final number = TextEditingController();
  final cargo = TextEditingController();
  final observation = TextEditingController();
  String type = '40 pieds';

  _ContainerDraft([TransitContainer? container]) {
    if (container == null) return;
    number.text = container.numero;
    cargo.text = container.marchandise;
    observation.text = container.observation;
    type = _containerTypeOptions.contains(container.type)
        ? container.type
        : 'Autre';
  }

  bool get isEmpty =>
      number.text.trim().isEmpty &&
      cargo.text.trim().isEmpty &&
      observation.text.trim().isEmpty;

  void dispose() {
    number.dispose();
    cargo.dispose();
    observation.dispose();
  }
}

// Création et modification d'un dossier client.
class _DossierEditorDialog extends StatefulWidget {
  final List<Client> clients;
  final List<Prestataire> prestataires;
  final List<TransitDossier> dossiers;
  final TransitDossier? initial;

  const _DossierEditorDialog({
    required this.clients,
    required this.prestataires,
    required this.dossiers,
    this.initial,
  });

  @override
  State<_DossierEditorDialog> createState() => _DossierEditorDialogState();
}

class _DossierEditorDialogState extends State<_DossierEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _bl = TextEditingController();
  final _goodsType = TextEditingController();
  final _goodsLocation = TextEditingController();
  final _deliveryLocation = TextEditingController();
  final _description = TextEditingController();
  final List<_ContainerDraft> _containers = [];
  Client? _client;
  Prestataire? _transitaire;
  DateTime _creation = DateTime.now();
  DateTime? _shipArrival;
  DateTime? _wishedDelivery;
  String _billingType = 'Tarif complet';
  String _priority = 'Priorité normale';

  static const _billingTypes = ['Tarif complet', 'Tarif partiel', 'À définir'];
  static const _priorities = ['Priorité normale', 'Priorité élevée', 'Urgent'];

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d == null) {
      _number.text = 'STT-${DateFormat('yyMMdd-HHmm').format(DateTime.now())}';
      _containers.add(_ContainerDraft());
      return;
    }
    _number.text = d.numDossier;
    _bl.text = d.numBL;
    _goodsType.text = d.typeMarchandise;
    _goodsLocation.text = d.lieuMarchandise;
    _deliveryLocation.text = d.lieuLivraison;
    _description.text = d.description;
    _client = d.client;
    _transitaire = d.transitaireAffecte ?? _luiMeme;
    _creation = _parseFrDate(d.dateCreation) ?? DateTime.now();
    _shipArrival = _parseFrDate(d.dateArriveeBateau);
    _wishedDelivery = _parseFrDate(d.dateLivraisonSouhaitee);
    if (_billingTypes.contains(d.typeFacturation)) {
      _billingType = d.typeFacturation;
    }
    if (_priorities.contains(d.priorite)) _priority = d.priorite;
    _containers.addAll(d.conteneurs.map(_ContainerDraft.new));
    if (_containers.isEmpty) _containers.add(_ContainerDraft());
  }

  @override
  void dispose() {
    for (final controller in [
      _number,
      _bl,
      _goodsType,
      _goodsLocation,
      _deliveryLocation,
      _description,
    ]) {
      controller.dispose();
    }
    for (final container in _containers) {
      container.dispose();
    }
    super.dispose();
  }

  String _fr(DateTime? date) =>
      date == null ? '' : DateFormat('dd/MM/yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: math.min(screen.width - 28, 980),
        height: math.min(screen.height - 28, 900),
        child: Column(
          children: [
            _dialogHeader(
              icon: Icons.folder_copy_rounded,
              title: _isEdit ? 'Modifier le dossier' : 'Nouveau dossier client',
              subtitle: _isEdit
                  ? '${widget.initial!.numDossier} • ${widget.initial!.client.nom}'
                  : 'Client, transitaire, marchandise et conteneurs',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFFF4F6FB),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 700 ? 2 : 1;
                      final fieldWidth =
                          (constraints.maxWidth -
                              32 -
                              32 -
                              (columns - 1) * 14) /
                          columns;
                      Widget sized(Widget child, {bool full = false}) =>
                          SizedBox(
                            width: full
                                ? fieldWidth * columns + (columns - 1) * 14
                                : fieldWidth,
                            child: child,
                          );
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _dialogSection(
                            icon: Icons.assignment_outlined,
                            title: 'Informations du dossier',
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: [
                                sized(
                                  SearchableDropdownFormField<Client>(
                                    key: const ValueKey(
                                      'dossier-client-search',
                                    ),
                                    options: widget.clients,
                                    value: _client,
                                    label: 'Client *',
                                    emptyText: 'Aucun client enregistré',
                                    displayString: (c) => c.nom,
                                    onChanged: (c) =>
                                        setState(() => _client = c),
                                  ),
                                ),
                                sized(
                                  SearchableDropdownFormField<Prestataire>(
                                    key: const ValueKey(
                                      'dossier-transitaire-search',
                                    ),
                                    options: _transitaireOptions(
                                      widget.prestataires,
                                    ),
                                    value: _transitaire,
                                    label: 'Transitaire *',
                                    emptyText: 'Aucun transitaire',
                                    displayString: (p) => p.entreprise,
                                    onChanged: (p) =>
                                        setState(() => _transitaire = p),
                                  ),
                                ),
                                sized(
                                  TextFormField(
                                    key: const ValueKey('dossier-number'),
                                    controller: _number,
                                    decoration: _inputDecoration(
                                      'Numéro de dossier *',
                                      icon: Icons.tag_rounded,
                                    ),
                                    validator: _validateNumber,
                                  ),
                                ),
                                sized(
                                  TextFormField(
                                    key: const ValueKey('dossier-bl'),
                                    controller: _bl,
                                    decoration: _inputDecoration(
                                      'BL (connaissement)',
                                      icon: Icons.article_outlined,
                                    ),
                                  ),
                                ),
                                sized(
                                  _FormDateField(
                                    label: 'Date de création',
                                    value: _creation,
                                    clearable: false,
                                    onChanged: (date) => setState(
                                      () => _creation = date ?? _creation,
                                    ),
                                  ),
                                ),
                                sized(
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _billingType,
                                    decoration: _inputDecoration(
                                      'Type de facturation',
                                      icon: Icons.receipt_long_outlined,
                                    ),
                                    items: [
                                      for (final type in _billingTypes)
                                        DropdownMenuItem(
                                          value: type,
                                          child: Text(type),
                                        ),
                                    ],
                                    onChanged: (value) => setState(
                                      () =>
                                          _billingType = value ?? _billingType,
                                    ),
                                  ),
                                ),
                                sized(
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _priority,
                                    decoration: _inputDecoration(
                                      'Type de priorité',
                                      icon: Icons.flag_outlined,
                                    ),
                                    items: [
                                      for (final priority in _priorities)
                                        DropdownMenuItem(
                                          value: priority,
                                          child: Text(priority),
                                        ),
                                    ],
                                    onChanged: (value) => setState(
                                      () => _priority = value ?? _priority,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _dialogSection(
                            icon: Icons.inventory_2_outlined,
                            title: 'Marchandise et livraison',
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: [
                                sized(
                                  TextFormField(
                                    controller: _goodsType,
                                    decoration: _inputDecoration(
                                      'Type de marchandise',
                                      icon: Icons.category_outlined,
                                    ),
                                  ),
                                ),
                                sized(
                                  TextFormField(
                                    controller: _goodsLocation,
                                    decoration: _inputDecoration(
                                      'Lieu de la marchandise',
                                      icon: Icons.location_on_outlined,
                                    ),
                                  ),
                                ),
                                sized(
                                  TextFormField(
                                    controller: _deliveryLocation,
                                    decoration: _inputDecoration(
                                      'Lieu de livraison',
                                      icon: Icons.flag_circle_outlined,
                                    ),
                                  ),
                                ),
                                sized(
                                  _FormDateField(
                                    label: 'Date arrivée bateau',
                                    value: _shipArrival,
                                    onChanged: (date) =>
                                        setState(() => _shipArrival = date),
                                  ),
                                ),
                                sized(
                                  _FormDateField(
                                    label: 'Date de livraison souhaitée',
                                    value: _wishedDelivery,
                                    onChanged: (date) =>
                                        setState(() => _wishedDelivery = date),
                                  ),
                                ),
                                sized(
                                  TextFormField(
                                    controller: _description,
                                    maxLines: 3,
                                    minLines: 2,
                                    decoration: _inputDecoration(
                                      'Description',
                                      icon: Icons.notes_rounded,
                                    ),
                                  ),
                                  full: true,
                                ),
                              ],
                            ),
                          ),
                          _dialogSection(
                            icon: Icons.view_in_ar_rounded,
                            title: 'Liste des conteneurs',
                            trailing: FilledButton.tonalIcon(
                              key: const ValueKey('container-add'),
                              onPressed: () => setState(
                                () => _containers.add(_ContainerDraft()),
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Ajouter'),
                            ),
                            child: _EditableTable(
                              emptyText:
                                  'Aucun conteneur. Utilisez « Ajouter » pour en saisir un.',
                              columns: const [
                                ('N°', 46),
                                ('Numéro conteneur', 200),
                                ('Type de conteneur', 160),
                                ('Marchandise', 210),
                                ('Observation', 240),
                                ('', 52),
                              ],
                              rowKeys: [
                                for (var i = 0; i < _containers.length; i++)
                                  ValueKey('container-row-$i'),
                              ],
                              rows: [
                                for (final (i, c) in _containers.indexed)
                                  _containerCells(i, c),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            _dialogFooter(
              onCancel: () => Navigator.pop(context),
              onValidate: _save,
              validateLabel: _isEdit
                  ? 'Enregistrer les modifications'
                  : 'Créer le dossier',
              validateKey: const ValueKey('dossier-save'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _containerCells(int index, _ContainerDraft c) => [
    Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        '${index + 1}',
        style: const TextStyle(color: _gridMuted, fontWeight: FontWeight.w600),
      ),
    ),
    TextFormField(
      key: ValueKey('container-number-$index'),
      controller: c.number,
      textCapitalization: TextCapitalization.characters,
      decoration: _cellDecoration(hint: 'MSKU1234567'),
    ),
    DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: c.type,
      decoration: _cellDecoration(),
      items: [
        for (final type in _containerTypeOptions)
          DropdownMenuItem(value: type, child: Text(type)),
      ],
      onChanged: (value) => setState(() => c.type = value ?? c.type),
    ),
    TextFormField(
      controller: c.cargo,
      decoration: _cellDecoration(hint: 'Marchandise'),
    ),
    TextFormField(
      controller: c.observation,
      decoration: _cellDecoration(hint: 'Observation'),
    ),
    IconButton(
      tooltip: 'Retirer ce conteneur',
      onPressed: () => setState(() {
        _containers.removeAt(index);
        c.dispose();
      }),
      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
    ),
  ];

  String? _validateNumber(String? value) {
    final number = value?.trim() ?? '';
    if (number.isEmpty) return 'Champ obligatoire';
    final duplicate = widget.dossiers.any(
      (d) =>
          d.id != widget.initial?.id &&
          _normalizeUniqueValue(d.numDossier) == _normalizeUniqueValue(number),
    );
    return duplicate ? 'Ce numéro de dossier existe déjà' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final client = _client;
    final transitaire = _transitaire;
    if (client == null || transitaire == null) return;
    final containers = [
      for (final c in _containers)
        if (!c.isEmpty)
          TransitContainer(
            numero: c.number.text.trim().toUpperCase(),
            type: c.type,
            marchandise: c.cargo.text.trim(),
            observation: c.observation.text.trim(),
          ),
    ];
    final numbers = containers
        .map((c) => c.numero)
        .where((n) => n.isNotEmpty)
        .toList();
    if (numbers.toSet().length != numbers.length) {
      await _showInfoAlert(
        context,
        title: 'Conteneur en double',
        message: 'Un même numéro de conteneur est saisi deux fois.',
      );
      return;
    }
    final isLuiMeme = identical(transitaire, _luiMeme);
    final initial = widget.initial;
    final dossier =
        TransitDossier(
            id: initial?.id ?? newLocalId('dossier'),
            numDossier: _number.text.trim(),
            numBL: _bl.text.trim(),
            numLB: initial?.numLB ?? '',
            client: client,
            nbConteneurs: containers.length,
            dateDebut: initial?.dateDebut ?? _fr(_creation),
            transitaire: transitaire.entreprise,
            dateCreation: _fr(_creation),
            typeFacturation: _billingType,
            priorite: _priority,
            typeMarchandise: _goodsType.text.trim(),
            lieuMarchandise: _goodsLocation.text.trim(),
            lieuLivraison: _deliveryLocation.text.trim(),
            dateArriveeBateau: _fr(_shipArrival),
            dateLivraisonSouhaitee: _fr(_wishedDelivery),
            description: _description.text.trim(),
            prestataire: isLuiMeme ? null : transitaire,
            factureClient: initial?.factureClient,
            facturePrestataire: initial?.facturePrestataire,
            factureTransitaire: initial?.factureTransitaire,
            factureTransporteur: initial?.factureTransporteur,
            conteneurs: containers,
            dateFin: initial?.dateFin ?? '-',
            statut: initial?.statut ?? 'Ouvert',
            depenses: initial?.depenses,
            operations: initial?.operations,
            version: initial?.version ?? 0,
            numero: initial?.numero ?? 0,
            auteurSaisie: initial?.auteurSaisie ?? (_currentUser?.name ?? ''),
            dateSaisie:
                initial?.dateSaisie ??
                DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
          )
          ..transitaireAffecte = isLuiMeme ? null : transitaire
          ..transporteurAffecte = initial?.transporteurAffecte;
    if (mounted) Navigator.pop(context, dossier);
  }
}

Widget _dialogFooter({
  required VoidCallback onCancel,
  required VoidCallback? onValidate,
  required String validateLabel,
  Key? validateKey,
  Widget? leading,
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  decoration: const BoxDecoration(
    color: Colors.white,
    border: Border(top: BorderSide(color: _gridBorder)),
  ),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final buttons = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Annuler')),
          const SizedBox(width: 8),
          Flexible(
            child: FilledButton.icon(
              key: validateKey,
              onPressed: onValidate,
              icon: const Icon(Icons.check_rounded),
              label: Text(validateLabel, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(
                backgroundColor: _gridPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      );
      // Sur téléphone, le total passe au-dessus des boutons.
      if (constraints.maxWidth < 560) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leading != null) ...[leading, const SizedBox(height: 8)],
            Align(alignment: Alignment.centerRight, child: buttons),
          ],
        );
      }
      return Row(
        children: [
          if (leading != null) Expanded(child: leading) else const Spacer(),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: buttons,
          ),
        ],
      );
    },
  ),
);

// Pastille d'information en lecture seule (fenêtres de facturation).
Widget _infoTile(String label, String value, {double width = 200}) => Container(
  width: width,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  decoration: BoxDecoration(
    color: const Color(0xFFF4F6FB),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: _gridMuted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        value.isEmpty ? '—' : value,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _gridText, fontWeight: FontWeight.w600),
      ),
    ],
  ),
);

class _InvoiceAmountDraft {
  final String description;
  final TransitContainer? container;
  final TextEditingController amount;

  _InvoiceAmountDraft(this.description, this.container, double value)
    : amount = TextEditingController(
        text: value == 0 ? '' : value.toStringAsFixed(0),
      );
}

// « Facturation d'un dossier client » : un montant par conteneur, total TTC calculé.
class _FacturationDialog extends StatefulWidget {
  final TransitDossier dossier;
  final List<TransitDossier> dossiers;

  const _FacturationDialog({required this.dossier, required this.dossiers});

  @override
  State<_FacturationDialog> createState() => _FacturationDialogState();
}

class _FacturationDialogState extends State<_FacturationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _observations = TextEditingController();
  final List<_InvoiceAmountDraft> _lines = [];
  DateTime _date = DateTime.now();
  bool _saving = false;

  TransitDossier get _dossier => widget.dossier;
  DossierInvoice get _invoice => _dossier.factureClient;

  @override
  void initState() {
    super.initState();
    final invoice = _invoice;
    if (invoice.estValidee) {
      _reference.text = invoice.reference;
      _observations.text = invoice.observations;
      _date = _parseFrDate(invoice.dateEmission) ?? DateTime.now();
    } else {
      _reference.text = _nextInvoiceNumber(
        'FAC-STT',
        widget.dossiers.map((d) => d.factureClient.reference),
        _date,
      );
    }
    double previous(String containerNumber) => invoice.lignes
        .where((l) => l.numeroConteneur == containerNumber)
        .fold(0, (sum, l) => sum + l.total);
    for (final c in _dossier.conteneurs) {
      _lines.add(
        _InvoiceAmountDraft(
          'Conteneur ${c.numero}'.trim(),
          c,
          invoice.estValidee ? previous(c.numero) : 0,
        ),
      );
    }
    if (_lines.isEmpty) {
      _lines.add(
        _InvoiceAmountDraft(
          'Prestation dossier ${_dossier.numDossier}',
          null,
          invoice.estValidee ? invoice.montant : 0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _observations.dispose();
    for (final line in _lines) {
      line.amount.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _lines.fold(0, (sum, l) => sum + (_parseAmount(l.amount.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final d = _dossier;
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: math.min(screen.width - 28, 900),
        height: math.min(screen.height - 28, 860),
        child: Column(
          children: [
            _dialogHeader(
              icon: Icons.request_quote_rounded,
              title: 'Facturation d’un dossier client',
              subtitle: '${d.numDossier} • ${d.client.nom}',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFFF4F6FB),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _dialogSection(
                        icon: Icons.folder_open_rounded,
                        title: 'Dossier',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _infoTile('Dossier', d.numDossier),
                            _infoTile('Client', d.client.nom),
                            _infoTile('Transitaire', d.nomTransitaire),
                            _infoTile('Date de création', d.dateCreation),
                            _infoTile('Type de facturation', d.typeFacturation),
                            _infoTile('Marchandise', d.typeMarchandise),
                            _infoTile(
                              'Conteneurs 20 pieds',
                              '${d.nbConteneurs20}',
                              width: 140,
                            ),
                            _infoTile(
                              'Conteneurs 40 pieds',
                              '${d.nbConteneurs40}',
                              width: 140,
                            ),
                          ],
                        ),
                      ),
                      _dialogSection(
                        icon: Icons.receipt_long_rounded,
                        title: 'Facture',
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            SizedBox(
                              width: 300,
                              child: TextFormField(
                                key: const ValueKey('invoice-number'),
                                controller: _reference,
                                decoration: _inputDecoration(
                                  'Numéro de facture *',
                                  icon: Icons.tag_rounded,
                                ),
                                validator: _validateReference,
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: _FormDateField(
                                label: 'Date de facture',
                                value: _date,
                                clearable: false,
                                onChanged: (date) =>
                                    setState(() => _date = date ?? _date),
                              ),
                            ),
                            SizedBox(
                              width: 540,
                              child: TextFormField(
                                controller: _observations,
                                maxLines: 2,
                                decoration: _inputDecoration(
                                  'Observations',
                                  icon: Icons.notes_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _dialogSection(
                        icon: Icons.view_in_ar_rounded,
                        title: 'Liste des conteneurs',
                        child: _EditableTable(
                          columns: const [
                            ('Numéro conteneur', 190),
                            ('Type de conteneur', 150),
                            ('Marchandise', 200),
                            ('Montant (FCFA)', 190),
                          ],
                          rows: [
                            for (final (i, line) in _lines.indexed)
                              [
                                Text(
                                  line.container?.numero ?? line.description,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(line.container?.type ?? '—'),
                                Text(
                                  line.container?.marchandise ?? '—',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                TextFormField(
                                  key: ValueKey('invoice-amount-$i'),
                                  controller: line.amount,
                                  textAlign: TextAlign.right,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _cellDecoration(hint: '0'),
                                  onChanged: (_) => setState(() {}),
                                  validator: (value) {
                                    final amount = _parseAmount(value ?? '');
                                    return amount == null || amount < 0
                                        ? 'Montant invalide'
                                        : null;
                                  },
                                ),
                              ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _dialogFooter(
              onCancel: () => Navigator.pop(context),
              onValidate: _saving ? null : _validate,
              validateLabel: _invoice.estValidee
                  ? 'Enregistrer la facture'
                  : 'Valider la facture',
              validateKey: const ValueKey('invoice-validate'),
              leading: Row(
                children: [
                  const Text(
                    'Total TTC : ',
                    style: TextStyle(color: _gridMuted, fontSize: 15),
                  ),
                  Flexible(
                    child: Text(
                      '${formatCurrency(_total)} FCFA',
                      key: const ValueKey('invoice-total'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
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

  String? _validateReference(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.isEmpty) return 'Champ obligatoire';
    final duplicate = widget.dossiers.any(
      (d) =>
          d.id != _dossier.id &&
          _normalizeUniqueValue(d.factureClient.reference) ==
              _normalizeUniqueValue(reference),
    );
    return duplicate ? 'Ce numéro de facture existe déjà' : null;
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_total <= 0) {
      await _showInfoAlert(
        context,
        title: 'Montant requis',
        message: 'Saisissez au moins un montant pour facturer ce dossier.',
      );
      return;
    }
    final invoice = _invoice;
    final previous = (
      invoice.reference,
      invoice.lignes,
      invoice.montant,
      invoice.statut,
      invoice.dateEmission,
      invoice.observations,
      invoice.description,
    );
    invoice
      ..reference = _reference.text.trim()
      ..lignes = [
        for (final line in _lines)
          InvoiceLine(
            description: line.description,
            quantite: 1,
            prixUnitaire: _parseAmount(line.amount.text) ?? 0,
            numeroConteneur: line.container?.numero ?? '',
            typeConteneur: line.container?.type ?? '',
            marchandise:
                line.container?.marchandise ?? _dossier.typeMarchandise,
            bl: _dossier.numBL,
          ),
      ]
      ..montant = _total
      ..statut = 'Clôturée'
      ..dateEmission = DateFormat('dd/MM/yyyy').format(_date)
      ..observations = _observations.text.trim()
      ..description = 'Facturation du dossier ${_dossier.numDossier}';
    setState(() => _saving = true);
    final saved = await _persist(
      context,
      () => erpBackend.saveDossier(_dossier),
    );
    if (!saved) {
      invoice
        ..reference = previous.$1
        ..lignes = previous.$2
        ..montant = previous.$3
        ..statut = previous.$4
        ..dateEmission = previous.$5
        ..observations = previous.$6
        ..description = previous.$7;
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }
}
