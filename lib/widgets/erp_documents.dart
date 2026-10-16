part of '../main.dart';

// Impressions PDF (fiche dossier, factures) et exports CSV.

const _pdfPrimary = PdfColor.fromInt(0xFF1A237E);
const _pdfAccent = PdfColor.fromInt(0xFF3949AB);
const _pdfLight = PdfColor.fromInt(0xFFF1F3FB);

Future<void> _exportCsv(
  BuildContext context, {
  required String baseName,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  String cell(String value) => '"${value.replaceAll('"', '""')}"';
  final lines = [
    headers.map(cell).join(';'),
    for (final row in rows) row.map(cell).join(';'),
  ];
  // BOM UTF-8 + séparateur « ; » : ouverture directe dans Excel en français.
  final bytes = Uint8List.fromList(utf8.encode('﻿${lines.join('\r\n')}'));
  final name =
      '${baseName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
  await saveGeneratedFile(name, bytes, 'text/csv;charset=utf-8');
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Export enregistré : $name')));
  }
}

Future<void> _exportGrid<T>(
  BuildContext context, {
  required String baseName,
  required List<ErpGridColumn<T>> columns,
  required List<T> rows,
}) => _exportCsv(
  context,
  baseName: baseName,
  headers: columns.map((c) => c.label).toList(),
  rows: [for (final row in rows) columns.map((c) => c.value(row)).toList()],
);

pw.Widget _pdfHeader(
  String title,
  String reference,
  String date,
) => pw.Container(
  padding: const pw.EdgeInsets.all(14),
  decoration: pw.BoxDecoration(
    gradient: const pw.LinearGradient(colors: [_pdfPrimary, _pdfAccent]),
    borderRadius: pw.BorderRadius.circular(8),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SYLLA TRANSIT & TRANSPORT',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Transit • Transport • Logistique',
              style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9),
            ),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            reference,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
          ),
          if (date.isNotEmpty)
            pw.Text(
              'Date : $date',
              style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9),
            ),
        ],
      ),
    ],
  ),
);

pw.Widget _pdfInfoGrid(List<(String, String)> entries) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    color: _pdfLight,
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: pw.Wrap(
    spacing: 18,
    runSpacing: 6,
    children: [
      for (final (label, value) in entries)
        pw.SizedBox(
          width: 160,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                value.isEmpty ? '—' : value,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
    ],
  ),
);

pw.Widget _pdfTable(
  List<String> headers,
  List<List<String>> rows, {
  Set<int> numericColumns = const {},
  double fontSize = 9,
}) => pw.TableHelper.fromTextArray(
  headers: headers,
  data: rows,
  headerStyle: pw.TextStyle(
    color: PdfColors.white,
    fontWeight: pw.FontWeight.bold,
    fontSize: fontSize,
  ),
  headerDecoration: const pw.BoxDecoration(color: _pdfPrimary),
  cellStyle: pw.TextStyle(fontSize: fontSize),
  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  oddRowDecoration: const pw.BoxDecoration(color: _pdfLight),
  cellAlignments: {
    for (final index in numericColumns) index: pw.Alignment.centerRight,
  },
  border: null,
);

pw.Widget _pdfTotals(List<(String, String)> totals) => pw.Align(
  alignment: pw.Alignment.centerRight,
  child: pw.Container(
    width: 230,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _pdfPrimary, width: 1.2),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      children: [
        for (final (label, value) in totals)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(label, style: const pw.TextStyle(fontSize: 9.5)),
                pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  ),
);

Future<void> _printDocument(
  String name,
  PdfPageFormat format,
  List<pw.Widget> Function() content,
) async {
  final doc = pw.Document(title: name, author: 'Sylla Transit & Transport');
  final author = _currentUser?.name ?? '';
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => content(),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Édité le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'
          '${author.isEmpty ? '' : ' par $author'} • Page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
        ),
      ),
    ),
  );
  await Printing.layoutPdf(
    name: name,
    format: format,
    onLayout: (_) => doc.save(),
  );
}

Future<void> _printDossier(TransitDossier d, PdfPageFormat format) =>
    _printDocument(
      'Dossier ${d.numDossier}',
      format,
      () => [
        _pdfHeader('FICHE DOSSIER', d.numDossier, d.dateCreation),
        pw.SizedBox(height: 12),
        _pdfInfoGrid([
          ('Client', d.client.nom),
          ('Transitaire', d.nomTransitaire),
          ('BL', d.numBL),
          ('Statut', _dossierStatus(d).$1),
          ('Type de facturation', d.typeFacturation),
          ('Type de priorité', d.priorite),
          ('Type de marchandise', d.typeMarchandise),
          ('Lieu de la marchandise', d.lieuMarchandise),
          ('Lieu de livraison', d.lieuLivraison),
          ('Date arrivée bateau', d.dateArriveeBateau),
          ('Livraison souhaitée', d.dateLivraisonSouhaitee),
          (
            'Conteneurs 20 / 40 pieds',
            '${d.nbConteneurs20} / ${d.nbConteneurs40}',
          ),
          ('Facture client', d.estFacture ? d.factureClient.reference : ''),
          ('Saisi par', d.auteurSaisie),
        ]),
        if (d.description.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Description : ${d.description}',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'LISTE DES CONTENEURS',
          style: pw.TextStyle(
            color: _pdfPrimary,
            fontWeight: pw.FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
        pw.SizedBox(height: 6),
        _pdfTable(
          ['N°', 'Numéro conteneur', 'Type', 'Marchandise', 'Observation'],
          [
            for (final (index, c) in d.conteneurs.indexed)
              ['${index + 1}', c.numero, c.type, c.marchandise, c.observation],
          ],
        ),
      ],
    );

Future<void> _printClientInvoice(TransitDossier d, PdfPageFormat format) {
  final invoice = d.factureClient;
  return _printDocument(
    'Facture ${invoice.reference}',
    format,
    () => [
      _pdfHeader('FACTURE CLIENT', invoice.reference, invoice.dateEmission),
      pw.SizedBox(height: 12),
      _pdfInfoGrid([
        ('Client', d.client.nom),
        ('Société', d.client.societe),
        ('Téléphone', d.client.telephone),
        ('Adresse', d.client.adresse),
        ('Dossier', d.numDossier),
        ('BL', d.numBL),
        ('Marchandise', d.typeMarchandise),
        ('Transitaire', d.nomTransitaire),
      ]),
      pw.SizedBox(height: 14),
      _pdfTable(
        [
          'Désignation',
          'Numéro conteneur',
          'Type',
          'Marchandise',
          'Montant (FCFA)',
        ],
        [
          for (final line in invoice.lignes)
            [
              line.description,
              line.numeroConteneur,
              line.typeConteneur,
              line.marchandise,
              formatCurrency(line.total),
            ],
        ],
        numericColumns: {4},
      ),
      pw.SizedBox(height: 12),
      _pdfTotals([('TOTAL TTC', '${formatCurrency(invoice.montant)} FCFA')]),
      if (invoice.observations.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text(
          'Observations : ${invoice.observations}',
          style: const pw.TextStyle(fontSize: 9.5),
        ),
      ],
    ],
  );
}
