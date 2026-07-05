import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/data/database/app_database.dart';

class PdfExporter {
  /// Helper to build cell header widgets.
  static pw.Widget _cellHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  /// Helper to build simple cell text widgets.
  static pw.Widget _cellData(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  /// Helper to build clickable preacher link cell.
  static pw.Widget _cellPreacherLink(Preacher? p) {
    if (p == null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text('-', style: const pw.TextStyle(fontSize: 9)),
      );
    }
    final name = '${p.firstName} ${p.lastName}';
    final hasPhone = p.phone != null && p.phone!.trim().isNotEmpty;

    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: hasPhone
          ? pw.UrlLink(
              destination: 'tel:${p.phone!.trim()}',
              child: pw.Text(
                name,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.teal900,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            )
          : pw.Text(
              name,
              style: const pw.TextStyle(fontSize: 9),
            ),
    );
  }

  /// Helper to build list of publishers with clickable tel: links.
  static pw.Widget _cellPublishersLinks(List<Preacher> preachers) {
    if (preachers.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text('-', style: const pw.TextStyle(fontSize: 9)),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Wrap(
        spacing: 4,
        runSpacing: 2,
        children: preachers.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          final name = '${p.firstName} ${p.lastName}';
          final isLast = idx == preachers.length - 1;
          final separator = isLast ? '' : ', ';
          final hasPhone = p.phone != null && p.phone!.trim().isNotEmpty;

          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              hasPhone
                  ? pw.UrlLink(
                      destination: 'tel:${p.phone!.trim()}',
                      child: pw.Text(
                        name,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.teal900,
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                    )
                  : pw.Text(
                      name,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
              if (!isLast)
                pw.Text(
                  separator,
                  style: const pw.TextStyle(fontSize: 9),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Generates the raw pw.Document (pure Dart, unit-testable)
  static pw.Document generateDocument({
    required String monthName,
    required int year,
    required List<ShiftWithPersonnel> shifts,
    pw.Font? baseFont,
    pw.Font? boldFont,
    String exportType = 'all',
  }) {
    final pdf = pw.Document(
      theme: (baseFont != null && boldFont != null)
          ? pw.ThemeData.withFont(base: baseFont, bold: boldFont)
          : null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'MinistryShift',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      exportType == 'exhibidor_only'
                          ? 'Horario de Predicación Pública (Exhibidores)'
                          : 'Horario de Predicación Pública (Todos los turnos)',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  '$monthName $year',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 2, color: PdfColors.teal800),
            pw.SizedBox(height: 20),

            // Shifts Grid Table using customized cell links
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FractionColumnWidth(0.12), // Fecha
                1: pw.FractionColumnWidth(0.15), // Horario
                2: pw.FractionColumnWidth(0.20), // Ubicación
                3: pw.FractionColumnWidth(0.23), // Capitán
                4: pw.FractionColumnWidth(0.30), // Publicadores
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal800),
                  children: [
                    _cellHeader('Fecha'),
                    _cellHeader('Horario'),
                    _cellHeader('Ubicación'),
                    _cellHeader('Capitán'),
                    _cellHeader('Publicadores'),
                  ],
                ),
                // Data rows
                ...shifts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final s = entry.value;
                  final d = s.shift.date;
                  final dateStr = '${d.day}/${d.month}/${d.year}';
                  
                  // Row background alternating colors
                  final rowBgColor = index % 2 == 1 ? PdfColors.grey100 : PdfColors.white;

                  final isExhibidor = s.shift.type == 'exhibidor';
                  final locationName = isExhibidor
                      ? s.location.name
                      : '${s.location.name} (Salida)';

                  final captainToRender = isExhibidor
                      ? s.captain
                      : (s.assignedPreachers.isNotEmpty ? s.assignedPreachers.first : null);

                  final publishersToRender = isExhibidor
                      ? s.assignedPreachers
                      : const <Preacher>[];

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBgColor),
                    children: [
                      _cellData(dateStr),
                      _cellData(s.formattedTime),
                      _cellData(locationName),
                      _cellPreacherLink(captainToRender),
                      _cellPublishersLinks(publishersToRender),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
        footer: (context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 24),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Documento de uso interno únicamente. Clica sobre el nombre de un predicador para llamarle.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf;
  }

  /// Opens PDF Preview (in-app modal or system viewer based on user preferences).
  static Future<void> exportMonthlySchedule({
    required BuildContext context,
    required String monthName,
    required int year,
    required List<ShiftWithPersonnel> shifts,
    String exportType = 'all',
  }) async {
    final authService = context.read<AuthService>();
    final db = authService.database;
    if (db == null) return;

    // Show a loading indicator dialog while loading the local font assets
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      ),
    );

    pw.Font? baseFont;
    pw.Font? boldFont;
    try {
      // Load fonts locally from embedded assets (100% offline)
      final baseData = await rootBundle.load('assets/fonts/Arial-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Arial-Bold.ttf');
      baseFont = pw.Font.ttf(baseData);
      boldFont = pw.Font.ttf(boldData);
    } catch (_) {
      // Fallback silently if assets fail to load
    }

    if (context.mounted) {
      Navigator.pop(context); // Close the loading dialog
    }

    final pdf = generateDocument(
      monthName: monthName,
      year: year,
      shifts: shifts,
      baseFont: baseFont,
      boldFont: boldFont,
      exportType: exportType,
    );
    final filename = 'ministry_shift_horario_${monthName.toLowerCase()}_$year.pdf';

    if (!context.mounted) return;

    // Retrieve PDF viewer preference (default to 'app')
    final viewerMode = await db.getMetadataValue('pdf_viewer_mode') ?? 'app';

    if (viewerMode == 'system') {
      try {
        final tempDir = await getTemporaryDirectory();
        final filePath = p.join(tempDir.path, filename);
        final file = File(filePath);
        await file.writeAsBytes(await pdf.save());

        if (Platform.isWindows) {
          await Process.run('explorer.exe', [filePath]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [filePath]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [filePath]);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Abriendo PDF en el visor del sistema: $filename'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al abrir en visor del sistema: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
      return;
    }

    // Default: Show beautiful modern in-app dialog preview with Direct Save and Open options
    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 950,
            height: 700,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vista Previa del Horario - $monthName $year',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            try {
                              final selectedPath = await FilePicker.saveFile(
                                dialogTitle: 'Guardar horario en PDF',
                                fileName: filename,
                                type: FileType.any,
                              );
                              if (selectedPath != null && selectedPath.isNotEmpty) {
                                final file = File(selectedPath);
                                await file.writeAsBytes(await pdf.save());
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Horario PDF guardado en: $selectedPath'),
                                      backgroundColor: Colors.teal,
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error al guardar PDF: $e'),
                                    backgroundColor: colorScheme.error,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Guardar PDF...'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final tempDir = await getTemporaryDirectory();
                              final filePath = p.join(tempDir.path, filename);
                              final file = File(filePath);
                              await file.writeAsBytes(await pdf.save());

                              if (Platform.isWindows) {
                                await Process.run('explorer.exe', [filePath]);
                              } else if (Platform.isMacOS) {
                                await Process.run('open', [filePath]);
                              } else if (Platform.isLinux) {
                                await Process.run('xdg-open', [filePath]);
                              }
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir en Visor del Sistema'),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PdfPreview(
                      build: (format) => pdf.save(),
                      pdfFileName: filename,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
