import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// SystemMetadata table for configuration and decryption validation
class SystemMetadata extends Table {
  TextColumn get key => text().withLength(min: 1, max: 50)();
  TextColumn get value => text().withLength(min: 1, max: 255)();

  @override
  Set<Column> get primaryKey => {key};
}

// Preachers Table
class Preachers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get firstName => text().withLength(min: 1, max: 100)();
  TextColumn get lastName => text().withLength(min: 1, max: 100)();
  TextColumn get phone => text().nullable().withLength(max: 50)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get canBeCaptain => boolean().withDefault(const Constant(false))();
  BoolColumn get canBePublisher => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Locations Table
class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable().withLength(max: 255)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

// Shifts Table
class Shifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()(); // YYYY-MM-DD
  TextColumn get startTime => text().withLength(min: 5, max: 5)(); // HH:MM
  TextColumn get endTime => text().withLength(min: 5, max: 5)(); // HH:MM
  IntColumn get locationId => integer().references(Locations, #id)();
  IntColumn get captainId => integer().nullable().references(Preachers, #id)();
  TextColumn get type => text().withDefault(const Constant('exhibidor'))();
}

// ShiftAssignments Table (for preachers other than the Captain)
class ShiftAssignments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shiftId => integer().references(Shifts, #id, onDelete: KeyAction.cascade)();
  IntColumn get preacherId => integer().references(Preachers, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text().withDefault(const Constant('publisher'))(); // 'publisher' or 'preacher'

  @override
  List<Set<Column>> get uniqueKeys => [
    {shiftId, preacherId}
  ];
}

class ShiftWithPersonnel {
  final Shift shift;
  final Location location;
  final Preacher? captain;
  final List<Preacher> assignedPreachers;

  ShiftWithPersonnel({
    required this.shift,
    required this.location,
    this.captain,
    required this.assignedPreachers,
  });

  String get formattedTime => '${shift.startTime} - ${shift.endTime}';
}

@DriftDatabase(tables: [SystemMetadata, Preachers, Locations, Shifts, ShiftAssignments])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
      );

  // --- CRUD Helpers ---

  // System Metadata Settings Helpers
  Future<String?> getMetadataValue(String key) async {
    final row = await (select(systemMetadata)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setMetadataValue(String key, String value) async {
    await into(systemMetadata).insertOnConflictUpdate(
      SystemMetadataCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  // Preachers
  Stream<List<Preacher>> watchActivePreachers() {
    return (select(preachers)..where((p) => p.isActive.equals(true))).watch();
  }

  Future<int> insertPreacher(PreachersCompanion companion) => into(preachers).insert(companion);
  Future<bool> updatePreacher(Preacher entry) => update(preachers).replace(entry);

  // Locations
  Stream<List<Location>> watchActiveLocations() {
    return (select(locations)..where((l) => l.isActive.equals(true))).watch();
  }

  Future<int> insertLocation(LocationsCompanion companion) => into(locations).insert(companion);
  Future<bool> updateLocation(Location entry) => update(locations).replace(entry);

  // Shifts & Assignments
  Future<int> createShift(ShiftsCompanion shiftCompanion, List<int> preacherIds) async {
    return transaction(() async {
      final id = await into(shifts).insert(shiftCompanion);
      for (final preacherId in preacherIds) {
        await into(shiftAssignments).insert(
          ShiftAssignmentsCompanion.insert(
            shiftId: id,
            preacherId: preacherId,
          ),
        );
      }
      return id;
    });
  }

  Future<void> updateShift(Shift shift, List<int> preacherIds) async {
    await transaction(() async {
      await update(shifts).replace(shift);
      await (delete(shiftAssignments)..where((sa) => sa.shiftId.equals(shift.id))).go();
      for (final preacherId in preacherIds) {
        await into(shiftAssignments).insert(
          ShiftAssignmentsCompanion.insert(
            shiftId: shift.id,
            preacherId: preacherId,
          ),
        );
      }
    });
  }

  Future<void> deleteShift(int shiftId) async {
    await (delete(shifts)..where((s) => s.id.equals(shiftId))).go();
  }

  /// Watches all shifts in a month range, resolved with Locations, Captains, and assigned Preachers.
  Stream<List<ShiftWithPersonnel>> watchShiftsForMonth(DateTime monthStart) {
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final monthEnd = nextMonth.subtract(const Duration(days: 1));

    final query = select(shifts).join([
      innerJoin(locations, locations.id.equalsExp(shifts.locationId)),
      leftOuterJoin(preachers, preachers.id.equalsExp(shifts.captainId)),
      leftOuterJoin(shiftAssignments, shiftAssignments.shiftId.equalsExp(shifts.id)),
    ])..where(shifts.date.isBetweenValues(monthStart, monthEnd));

    return query.watch().asyncMap((rows) async {
      final results = <ShiftWithPersonnel>[];
      final seenShiftIds = <int>{};
      
      for (final row in rows) {
        final shift = row.readTable(shifts);
        if (seenShiftIds.contains(shift.id)) continue;
        seenShiftIds.add(shift.id);

        final loc = row.readTable(locations);
        final cap = row.readTableOrNull(preachers);

        final assignmentQuery = select(shiftAssignments).join([
          innerJoin(preachers, preachers.id.equalsExp(shiftAssignments.preacherId)),
        ])..where(shiftAssignments.shiftId.equals(shift.id));

        final assignmentRows = await assignmentQuery.get();
        final assigned = assignmentRows.map((r) => r.readTable(preachers)).toList();

        results.add(ShiftWithPersonnel(
          shift: shift,
          location: loc,
          captain: cap,
          assignedPreachers: assigned,
        ));
      }
      // Sort by date then start time
      results.sort((a, b) {
        final dateComp = a.shift.date.compareTo(b.shift.date);
        if (dateComp != 0) return dateComp;
        return a.shift.startTime.compareTo(b.shift.startTime);
      });
      return results;
    });
  }


  /// Verifies if the encryption token is present and valid.
  /// If decryption failed, this query will throw an exception.
  Future<bool> verifyEncryptionToken() async {
    try {
      final tokenRow = await (select(systemMetadata)
            ..where((t) => t.key.equals('encryption_validation_token')))
          .getSingleOrNull();
      return tokenRow?.value == 'MinistryShiftSecureToken';
    } catch (e) {
      // Typically throws SqliteException with error code 26 (SQLITE_NOTADB) on decryption failure
      return false;
    }
  }

  /// Writes the validation token to mark the database as successfully initialized.
  Future<void> initializeValidationToken() async {
    await into(systemMetadata).insertOnConflictUpdate(
      SystemMetadataCompanion.insert(
        key: 'encryption_validation_token',
        value: 'MinistryShiftSecureToken',
      ),
    );
  }
}

/// Helper function to open connection with a specific file and password.
QueryExecutor openConnection(File file, String password) {
  return LazyDatabase(() async {
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        // Enforce SQLCipher/SQLite3MC encryption
        // Escape single quotes in password to prevent SQL injections in PRAGMA
        final escapedPassword = password.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escapedPassword';");
      },
    );
  });
}
