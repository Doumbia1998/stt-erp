part of '../main.dart';

// Grille de données de l'ERP : en-tête fixe, tri par colonne, sélection,
// barres de défilement horizontale et verticale toujours visibles et
// glissement à la souris (ou au doigt) dans les deux sens.

const _gridPrimary = Color(0xFF1A237E);
const _gridAccent = Color(0xFF3949AB);
const _gridBorder = Color(0xFFE3E8F2);
const _gridText = Color(0xFF1F2A44);
const _gridMuted = Color(0xFF64748B);

class ErpGridColumn<T> {
  final String label;
  final double width;
  final String Function(T row) value;
  final Widget Function(T row)? builder;
  final Comparable<Object> Function(T row)? sortValue;
  final bool numeric;

  const ErpGridColumn({
    required this.label,
    required this.value,
    this.width = 150,
    this.builder,
    this.sortValue,
    this.numeric = false,
  });
}

// Autorise le glissement à la souris en plus du doigt et du pavé tactile.
class _DragEverywhereBehavior extends MaterialScrollBehavior {
  const _DragEverywhereBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class ErpGrid<T> extends StatefulWidget {
  final List<ErpGridColumn<T>> columns;
  final List<T> rows;
  final T? selected;
  final ValueChanged<T>? onSelect;
  final ValueChanged<T>? onOpen;
  final String emptyText;
  final IconData emptyIcon;
  final String Function(T row) rowId;
  final double rowHeight;
  // Ajoute à chaque colonne une liste déroulante de filtre (valeurs à cocher).
  final bool filterable;

  const ErpGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowId,
    this.selected,
    this.onSelect,
    this.onOpen,
    this.emptyText = 'Aucune donnée à afficher',
    this.emptyIcon = Icons.inbox_outlined,
    this.rowHeight = 42,
    this.filterable = false,
  });

  @override
  State<ErpGrid<T>> createState() => _ErpGridState<T>();
}

class _ErpGridState<T> extends State<ErpGrid<T>> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  int? _sortColumn;
  bool _ascending = true;
  // Valeurs retenues par colonne filtrée.
  final Map<int, Set<String>> _filters = {};

  static const _headerHeight = 48.0;
  static const _scrollbarThickness = 12.0;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  List<T> get _filteredRows {
    if (_filters.isEmpty) return widget.rows;
    return widget.rows
        .where(
          (row) => _filters.entries.every(
            (f) => f.value.contains(widget.columns[f.key].value(row)),
          ),
        )
        .toList();
  }

  List<T> get _sortedRows {
    final index = _sortColumn;
    final filtered = _filteredRows;
    if (index == null) return filtered;
    final column = widget.columns[index];
    final key = column.sortValue ?? (T row) => column.value(row).toLowerCase();
    final rows = [...filtered]
      ..sort((a, b) {
        final result = key(a).compareTo(key(b));
        return _ascending ? result : -result;
      });
    return rows;
  }

  Future<void> _openFilter(int index) async {
    final column = widget.columns[index];
    final values = widget.rows.map(column.value).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _ColumnFilterDialog(
        label: column.label,
        values: values,
        selected: _filters[index] ?? values.toSet(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.length >= values.length) {
        _filters.remove(index);
      } else {
        _filters[index] = result;
      }
    });
  }

  void _sortBy(int index) => setState(() {
    if (_sortColumn == index) {
      _ascending = !_ascending;
    } else {
      _sortColumn = index;
      _ascending = true;
    }
  });

  // Fait défiler horizontalement d'environ une largeur d'écran.
  void _scrollBy(double direction) {
    if (!_horizontal.hasClients) return;
    final position = _horizontal.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        );
    _horizontal.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.columns.fold<double>(
      0,
      (sum, c) => sum + c.width,
    );
    final rows = _sortedRows;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gridBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A237E),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: const _DragEverywhereBehavior(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.max(totalWidth, constraints.maxWidth);
                  return Scrollbar(
                    controller: _vertical,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: _scrollbarThickness,
                    radius: const Radius.circular(8),
                    interactive: true,
                    // La liste verticale est à l'intérieur du défilement horizontal.
                    notificationPredicate: (notification) =>
                        notification.depth == 1,
                    child: Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: _scrollbarThickness,
                      radius: const Radius.circular(8),
                      interactive: true,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          // Laisse la place aux barres pour ne pas masquer les données.
                          padding: const EdgeInsets.only(
                            bottom: _scrollbarThickness + 4,
                            right: _scrollbarThickness + 4,
                          ),
                          child: SizedBox(
                            width: width,
                            child: Column(
                              children: [
                                _buildHeader(),
                                Expanded(
                                  // La liste reste en place même vide : la barre
                                  // verticale a toujours une position à suivre.
                                  child: Stack(
                                    children: [
                                      ListView.builder(
                                        controller: _vertical,
                                        itemExtent: widget.rowHeight,
                                        itemCount: rows.length,
                                        itemBuilder: (context, index) =>
                                            _buildRow(rows[index], index),
                                      ),
                                      if (rows.isEmpty)
                                        _buildEmpty(constraints.maxWidth),
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
                },
              ),
            ),
          ),
          _buildFooter(rows.length, totalWidth),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
    height: _headerHeight,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [_gridPrimary, _gridAccent]),
    ),
    child: Row(
      children: [
        for (var index = 0; index < widget.columns.length; index++)
          InkWell(
            onTap: () => _sortBy(index),
            child: Container(
              width: widget.columns[index].width,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white24)),
              ),
              alignment: widget.columns[index].numeric
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.columns[index].label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (_sortColumn == index)
                    Icon(
                      _ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  if (widget.filterable)
                    InkWell(
                      key: ValueKey('grid-filter-$index'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _openFilter(index),
                      child: Tooltip(
                        message: 'Filtrer la colonne',
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            _filters.containsKey(index)
                                ? Icons.filter_alt_rounded
                                : Icons.filter_alt_outlined,
                            size: 16,
                            color: _filters.containsKey(index)
                                ? const Color(0xFFFDE68A)
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildRow(T row, int index) {
    final selected =
        widget.selected != null &&
        widget.rowId(widget.selected as T) == widget.rowId(row);
    final background = selected
        ? const Color(0xFFE8EAFF)
        : index.isEven
        ? Colors.white
        : const Color(0xFFF7F9FD);
    return Material(
      key: ValueKey('grid-row-${widget.rowId(row)}'),
      color: background,
      child: InkWell(
        onTap: widget.onSelect == null ? null : () => widget.onSelect!(row),
        onDoubleTap: widget.onOpen == null ? null : () => widget.onOpen!(row),
        hoverColor: const Color(0xFFF0F2FF),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? _gridAccent : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: Color(0xFFEFF2F8)),
            ),
          ),
          child: Row(
            children: [
              for (final column in widget.columns)
                Container(
                  width:
                      column.width - (column == widget.columns.first ? 3 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: column.numeric
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child:
                      column.builder?.call(row) ??
                      Text(
                        column.value(row),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _gridText,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontFeatures: column.numeric
                              ? const [FontFeature.tabularFigures()]
                              : null,
                        ),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(double visibleWidth) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: visibleWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.emptyIcon, size: 46, color: const Color(0xFFB4BED0)),
            const SizedBox(height: 10),
            Text(
              widget.emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gridMuted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildFooter(int count, double totalWidth) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF7F9FD),
      border: Border(top: BorderSide(color: _gridBorder)),
    ),
    child: Row(
      children: [
        Flexible(
          child: Text(
            '$count ligne(s) • ${widget.columns.length} colonnes',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gridMuted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Glissez ou utilisez les flèches pour voir toutes les colonnes',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _gridMuted, fontSize: 11.5),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Colonnes précédentes',
          visualDensity: VisualDensity.compact,
          onPressed: () => _scrollBy(-1),
          icon: const Icon(Icons.chevron_left_rounded, color: _gridPrimary),
        ),
        IconButton(
          tooltip: 'Colonnes suivantes',
          visualDensity: VisualDensity.compact,
          onPressed: () => _scrollBy(1),
          icon: const Icon(Icons.chevron_right_rounded, color: _gridPrimary),
        ),
      ],
    ),
  );
}

// Liste de filtre d'une colonne : recherche et valeurs à cocher.
class _ColumnFilterDialog extends StatefulWidget {
  final String label;
  final List<String> values;
  final Set<String> selected;

  const _ColumnFilterDialog({
    required this.label,
    required this.values,
    required this.selected,
  });

  @override
  State<_ColumnFilterDialog> createState() => _ColumnFilterDialogState();
}

class _ColumnFilterDialogState extends State<_ColumnFilterDialog> {
  late final Set<String> _checked = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = widget.values
        .where((v) => query.isEmpty || v.toLowerCase().contains(query))
        .toList();
    final allVisible = visible.every(_checked.contains);
    return AlertDialog(
      title: Text('Filtrer : ${widget.label}'),
      content: SizedBox(
        width: 340,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('grid-filter-search'),
              autofocus: true,
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
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: allVisible,
              title: const Text(
                '(Tout sélectionner)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _checked.addAll(visible);
                } else {
                  _checked.removeAll(visible);
                }
              }),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final v in visible)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _checked.contains(v),
                      title: Text(v.isEmpty ? '(Vide)' : v),
                      onChanged: (c) => setState(
                        () =>
                            (c ?? false) ? _checked.add(v) : _checked.remove(v),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, widget.values.toSet()),
          child: const Text('Effacer le filtre'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('grid-filter-apply'),
          // Après une recherche, seules les valeurs trouvées et cochées sont gardées.
          onPressed: () => Navigator.pop(
            context,
            query.isEmpty ? _checked : _checked.intersection(visible.toSet()),
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// Pastille de statut colorée utilisée dans les grilles.
class ErpStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const ErpStatusChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// Bouton d'action de barre d'outils (désactivé tant qu'aucune ligne n'est choisie).
class ErpActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? color;

  const ErpActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: style.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? null
                : (color ?? _gridPrimary),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: style.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : (color ?? _gridPrimary),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? const Color(0xFFDDE2EC)
                : (color ?? _gridPrimary).withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

// Carte de chiffre clé (total facturé, payé, reliquat…).
class ErpMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const ErpMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 190),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: _gridMuted, fontSize: 11.5),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// Sélecteur de date compact avec bouton d'effacement.
class ErpDateFilter extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const ErpDateFilter({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: InkWell(
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
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.event_rounded, size: 18),
          suffixIcon: value == null
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          value == null
              ? 'jj/mm/aaaa'
              : DateFormat('dd/MM/yyyy').format(value!),
          style: TextStyle(
            color: value == null ? _gridMuted : _gridText,
            fontSize: 13.5,
          ),
        ),
      ),
    ),
  );
}

// Conversion « jj/mm/aaaa[ hh:mm] » -> DateTime (null si vide ou invalide).
DateTime? _parseFrDate(String value) {
  final match = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
    int.parse(match.group(4) ?? '0'),
    int.parse(match.group(5) ?? '0'),
  );
}

bool _inPeriod(DateTime? date, DateTime? from, DateTime? to) {
  if (from == null && to == null) return true;
  if (date == null) return false;
  final day = DateTime(date.year, date.month, date.day);
  if (from != null && day.isBefore(DateTime(from.year, from.month, from.day))) {
    return false;
  }
  if (to != null && day.isAfter(DateTime(to.year, to.month, to.day))) {
    return false;
  }
  return true;
}

String _amountText(double value) => '${formatCurrency(value)} F';

// Montant saisi (espaces et virgule acceptés).
double? _parseAmount(String text) {
  final cleaned = text.trim().replaceAll(RegExp(r'[\s  ]'), '');
  if (cleaned.isEmpty) return 0;
  return double.tryParse(cleaned.replaceAll(',', '.'));
}
