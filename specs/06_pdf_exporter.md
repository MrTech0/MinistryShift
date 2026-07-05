# SPEC-06: Monthly Schedule PDF Exporter

## Metadata
- **Status**: Draft
- **Author**: Spec Author (The Architect)
- **Created Date**: 2026-06-30
- **Last Updated**: 2026-06-30

---

## 1. Objectives & Scope

### 1.1 Summary
This specification defines the requirements and technical design for exporting monthly preaching schedules into beautifully formatted PDF documents, ready for sharing or printing by congregation coordinators.

### 1.2 Out of Scope
- Direct printing drivers integration (handled by standard system dialogs).
- Custom font bundling (will use standard built-in Helvetica/Courier PDF fonts to keep package size small and compilation simple).

---

## 2. Functional Requirements

### 2.1 User Stories
- **Export Monthly PDF**: As a coordinator, I want to click an "Exportar PDF" button in the monthly view, select a target folder, and save a formatted schedule of the selected month.
- **Printed Readability**: As a preacher, I want to print the exported schedule and be able to read it clearly, with alternating colors, explicit headers, and page numbering.

### 2.2 Layout & Content Specifications
The exported document must be in landscape or portrait layout (configurable or defaulted to Landscape for wider columns) and include:
1. **Document Header**:
   - Title: `MinistryShift - Horario de Predicación Pública`
   - Selected Month & Year (e.g. `Julio de 2026`).
   - Generation timestamp.
2. **Main Schedule Table**:
   - **Column 1: Fecha (Date)**: e.g. `Sábado, 04/07`
   - **Column 2: Horario (Time)**: e.g. `09:00 - 11:00`
   - **Column 3: Ubicación (Location)**: e.g. `Plaza de la Constitución`
   - **Column 4: Capitán (Captain)**: e.g. `Juan Pérez`
   - **Column 5: Predicadores (Preachers)**: Bulleted list of assigned publishers.
3. **Document Footer**:
   - Confidentiality notice: `Documento de uso interno únicamente.`
   - Page count: `Página X de Y` centered.

---

## 3. Technology Stack & Implementation

### 3.1 Pub Packages
- `pdf: ^3.10.0` (core layout engine)
- `printing: ^5.11.0` (native share/print sheet and file saver on desktop)

### 3.2 Layout Code Outline
```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Document> generateMonthlyPdf({
  required String monthName,
  required int year,
  required List<ShiftWithPersonnel> shifts,
}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        // Header
        pw.Header(
          level: 0,
          child: pw.Row(
            mainpw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('MinistryShift - Horario de Predicación', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text('$monthName $year', style: pw.TextStyle(fontSize: 18)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        
        // Table of Shifts
        pw.TableHelper.fromTextArray(
          headers: ['Fecha', 'Horario', 'Ubicación', 'Capitán', 'Predicadores'],
          data: shifts.map((s) => [
            s.formattedDate,
            s.formattedTime,
            s.locationName,
            s.captainName,
            s.preachersList.join(', '),
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.teal300),
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
        ),
      ],
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
      ),
    ),
  );

  return pdf;
}
```

---

## 4. Test / Harness Plan

### 4.1 Test Scenarios
- **Scenario 1 (Empty Schedule)**:
  - Generate PDF for a month with zero shifts -> Verify that a page compiles showing the header and an empty/empty-message table.
- **Scenario 2 (Multi-page Breaking)**:
  - Generate PDF with 100 shifts -> Verify page breaking is handled gracefully without widget overflow errors.
- **Scenario 3 (File Saving)**:
  - Mock file saver -> Verify PDF bytes write successfully to a local file.
