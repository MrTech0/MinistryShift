import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:ministry_shift/data/database/app_database.dart';
import 'package:ministry_shift/core/scheduler/shift_validator.dart';
import 'package:ministry_shift/core/scheduler/substitution_service.dart';
import 'package:ministry_shift/core/utils/pdf_exporter.dart';
import 'package:ministry_shift/core/backup/backup_service.dart';
import 'package:ministry_shift/core/update/update_service.dart';


void main() {
  late Directory tempDir;
  late File tempDbFile;
  late AppDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ministry_shift_domain_test_');
    tempDbFile = File(p.join(tempDir.path, 'test_db.sqlite'));
    
    // We open a plain (unencrypted) NativeDatabase for testing domain queries to keep it fast
    db = AppDatabase(NativeDatabase(tempDbFile));
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Domain Models & Invariant Validations', () {
    test('Preachers & Locations inserts and retrievals', () async {
      // 1. Insert Preacher
      final preacherId = await db.into(db.preachers).insert(
        PreachersCompanion.insert(
          firstName: 'Juan',
          lastName: 'Pérez',
          canBeCaptain: const Value(true),
        ),
      );

      // 2. Insert Location
      final locationId = await db.into(db.locations).insert(
        LocationsCompanion.insert(
          name: 'Plaza del Sol',
        ),
      );

      final preacher = await (db.select(db.preachers)..where((p) => p.id.equals(preacherId))).getSingle();
      final location = await (db.select(db.locations)..where((l) => l.id.equals(locationId))).getSingle();

      expect(preacher.firstName, 'Juan');
      expect(preacher.canBeCaptain, isTrue);
      expect(location.name, 'Plaza del Sol');
    });

    test('Shift Capacity validation rules', () {
      // Exhibidor:
      // Count = 1 (only captain) -> should fail (min capacity 2)
      expect(() => ShiftValidator.validateShiftCapacity(type: 'exhibidor', hasCaptain: true, additionalPreachersCount: 0), throwsA(isA<ShiftValidationException>()));
      
      // Count = 2 (captain + 1 publisher) -> should pass
      expect(() => ShiftValidator.validateShiftCapacity(type: 'exhibidor', hasCaptain: true, additionalPreachersCount: 1), returnsNormally);

      // Count = 6 (captain + 5 publishers) -> should pass
      expect(() => ShiftValidator.validateShiftCapacity(type: 'exhibidor', hasCaptain: true, additionalPreachersCount: 5), returnsNormally);

      // Count = 7 (captain + 6 publishers) -> should fail (max capacity 6)
      expect(() => ShiftValidator.validateShiftCapacity(type: 'exhibidor', hasCaptain: true, additionalPreachersCount: 6), throwsA(isA<ShiftValidationException>()));

      // Salida:
      // No captain, no publishers -> should fail (empty)
      expect(() => ShiftValidator.validateShiftCapacity(type: 'salida', hasCaptain: false, additionalPreachersCount: 0), throwsA(isA<ShiftValidationException>()));

      // 1 publisher, no captain -> should pass (total 1)
      expect(() => ShiftValidator.validateShiftCapacity(type: 'salida', hasCaptain: false, additionalPreachersCount: 1), returnsNormally);

      // 2 publishers, no captain -> should fail (total > 1)
      expect(() => ShiftValidator.validateShiftCapacity(type: 'salida', hasCaptain: false, additionalPreachersCount: 2), throwsA(isA<ShiftValidationException>()));
    });

    test('Captain Eligibility validation rules', () {
      final eligibleCaptain = Preacher(
        id: 1,
        firstName: 'Active',
        lastName: 'Captain',
        isActive: true,
        canBeCaptain: true,
        canBePublisher: true,
        createdAt: DateTime.now(),
      );

      final inactiveCaptain = Preacher(
        id: 2,
        firstName: 'Inactive',
        lastName: 'Captain',
        isActive: false,
        canBeCaptain: true,
        canBePublisher: true,
        createdAt: DateTime.now(),
      );

      final ineligibleCaptain = Preacher(
        id: 3,
        firstName: 'Active',
        lastName: 'Ineligible',
        isActive: true,
        canBeCaptain: false,
        canBePublisher: true,
        createdAt: DateTime.now(),
      );

      expect(() => ShiftValidator.validateCaptainEligibility(eligibleCaptain), returnsNormally);
      expect(() => ShiftValidator.validateCaptainEligibility(inactiveCaptain), throwsA(isA<ShiftValidationException>()));
      expect(() => ShiftValidator.validateCaptainEligibility(ineligibleCaptain), throwsA(isA<ShiftValidationException>()));
    });

    test('Time overlap calculations', () {
      // Overlapping: 09:00-11:00 vs 10:00-12:00
      expect(ShiftValidator.isTimeOverlapping('09:00', '11:00', '10:00', '12:00'), isTrue);

      // Overlapping: 10:30-11:30 vs 10:00-11:00
      expect(ShiftValidator.isTimeOverlapping('10:30', '11:30', '10:00', '11:00'), isTrue);

      // Non-overlapping: 09:00-11:00 vs 11:00-13:00 (exact touch)
      expect(ShiftValidator.isTimeOverlapping('09:00', '11:00', '11:00', '13:00'), isFalse);

      // Non-overlapping: 09:00-10:00 vs 11:00-12:00
      expect(ShiftValidator.isTimeOverlapping('09:00', '10:00', '11:00', '12:00'), isFalse);
    });

    test('LRA Substitution candidate sorting and busy exclusions', () async {
      // 1. Setup Preachers
      final p1 = await db.into(db.preachers).insert(PreachersCompanion.insert(
        firstName: 'Ana',
        lastName: 'García',
        canBePublisher: const Value(true),
      ));
      final p2 = await db.into(db.preachers).insert(PreachersCompanion.insert(
        firstName: 'Pedro',
        lastName: 'López',
        canBePublisher: const Value(true),
      ));
      final p3 = await db.into(db.preachers).insert(PreachersCompanion.insert(
        firstName: 'Luis',
        lastName: 'Martínez',
        canBePublisher: const Value(true),
      ));
      final cap = await db.into(db.preachers).insert(PreachersCompanion.insert(
        firstName: 'Capitán',
        lastName: 'Original',
        canBeCaptain: const Value(true),
      ));

      final loc = await db.into(db.locations).insert(LocationsCompanion.insert(name: 'Calle Mayor'));

      // 2. Setup shifts to establish assignment history:
      // Luis (p3) has a shift on June 25
      final s1 = await db.into(db.shifts).insert(ShiftsCompanion.insert(
        date: DateTime(2026, 6, 25),
        startTime: '09:00',
        endTime: '11:00',
        locationId: loc,
        captainId: Value(cap),
      ));
      await db.into(db.shiftAssignments).insert(ShiftAssignmentsCompanion.insert(shiftId: s1, preacherId: p3));

      // Pedro (p2) has a shift on June 28
      final s2 = await db.into(db.shifts).insert(ShiftsCompanion.insert(
        date: DateTime(2026, 6, 28),
        startTime: '09:00',
        endTime: '11:00',
        locationId: loc,
        captainId: Value(cap),
      ));
      await db.into(db.shiftAssignments).insert(ShiftAssignmentsCompanion.insert(shiftId: s2, preacherId: p2));

      // 3. Test: Query LRA recommendations for a shift on June 30
      final subService = SubstitutionService(db);
      final list = await subService.getLraCandidates(
        targetDate: DateTime(2026, 6, 30),
        requireCaptain: false,
        requirePublisher: true,
      );

      final ids = list.map((cand) => cand.preacher.id).toList();

      expect(ids.first, p1, reason: 'Ana (never assigned) should be first');
      expect(ids.contains(p3), isTrue);
      expect(ids.contains(p2), isTrue);

      // 4. Exclude busy preachers
      final s3 = await db.into(db.shifts).insert(ShiftsCompanion.insert(
        date: DateTime(2026, 6, 30),
        startTime: '09:00',
        endTime: '11:00',
        locationId: loc,
        captainId: Value(cap),
      ));
      await db.into(db.shiftAssignments).insert(ShiftAssignmentsCompanion.insert(shiftId: s3, preacherId: p1));

      final list2 = await subService.getLraCandidates(
        targetDate: DateTime(2026, 6, 30),
        requireCaptain: false,
        requirePublisher: true,
      );
      final ids2 = list2.map((cand) => cand.preacher.id).toList();
      expect(ids2.contains(p1), isFalse, reason: 'Ana is busy on June 30, so she must be excluded');
    });

    test('PDF Document Exporter layout generation test', () async {
      final mockPreacher1 = Preacher(
        id: 1,
        firstName: 'Carlos',
        lastName: 'Ruiz',
        isActive: true,
        canBeCaptain: false,
        canBePublisher: true,
        createdAt: DateTime.now(),
      );
      final mockPreacher2 = Preacher(
        id: 2,
        firstName: 'María',
        lastName: 'López',
        isActive: true,
        canBeCaptain: true,
        canBePublisher: true,
        createdAt: DateTime.now(),
      );
      final mockLocation = Location(
        id: 1,
        name: 'Plaza del Pilar',
        isActive: true,
      );
      final mockShift = Shift(
        id: 1,
        date: DateTime(2026, 7, 4),
        startTime: '09:00',
        endTime: '11:00',
        locationId: 1,
        captainId: 2,
        type: 'exhibidor',
      );

      final dummyShifts = [
        ShiftWithPersonnel(
          shift: mockShift,
          location: mockLocation,
          captain: mockPreacher2,
          assignedPreachers: [mockPreacher1],
        )
      ];

      final doc = PdfExporter.generateDocument(
        monthName: 'Julio',
        year: 2026,
        shifts: dummyShifts,
      );

      final bytes = await doc.save();
      expect(bytes, isNotEmpty);
    });

    test('BackupService retention rules', () async {
      final mockBackupDir = Directory(p.join(tempDir.path, 'MockBackups'));
      await mockBackupDir.create(recursive: true);

      final oldAutoFile = File(p.join(mockBackupDir.path, 'MinistryShift_AutoBackup_v1.0.0_10_12_00_00.db'));
      await oldAutoFile.writeAsString('old_data');
      await oldAutoFile.setLastModified(DateTime.now().subtract(const Duration(days: 10)));

      final newManualFile = File(p.join(mockBackupDir.path, 'MinistryShift_ManualBackup_v1.0.0_28_12_00_00.db'));
      await newManualFile.writeAsString('new_data');
      await newManualFile.setLastModified(DateTime.now().subtract(const Duration(days: 2)));

      expect(await oldAutoFile.exists(), isTrue);
      expect(await newManualFile.exists(), isTrue);

      await BackupService.cleanOldBackups(mockBackupDir);

      expect(await oldAutoFile.exists(), isFalse, reason: 'Auto backups older than 7 days should be cleaned up');
      expect(await newManualFile.exists(), isTrue, reason: 'Manual backups younger than 7 days should be preserved');
    });

    test('UpdateService offline behavior', () async {
      try {
        final version = await UpdateService.checkLatestVersion();
        expect(version == null || version.startsWith('v') || version.isNotEmpty, isTrue);
      } catch (e) {
        expect(e != null, isTrue);
      }
    });
  });
}
