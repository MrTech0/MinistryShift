import 'package:drift/drift.dart';
import 'package:ministry_shift/data/database/app_database.dart';

class PreacherLraRecommendation {
  final Preacher preacher;
  final DateTime? lastAssignedDate;

  PreacherLraRecommendation({
    required this.preacher,
    this.lastAssignedDate,
  });
}

class SubstitutionService {
  final AppDatabase database;
  SubstitutionService(this.database);

  /// Computes the Least Recently Assigned (LRA) list of candidates.
  /// [targetDate] is the date of the shift needing substitution.
  /// [requireCaptain] if true filters only preachers eligible to be Captain.
  /// [requirePublisher] if true filters only preachers eligible to be Publisher.
  Future<List<PreacherLraRecommendation>> getLraCandidates({
    required DateTime targetDate,
    required bool requireCaptain,
    required bool requirePublisher,
  }) async {
    // 1. Fetch all active preachers with appropriate capabilities
    var selectPreachers = database.select(database.preachers)
      ..where((p) => p.isActive.equals(true));
    
    if (requireCaptain) {
      selectPreachers.where((p) => p.canBeCaptain.equals(true));
    }
    if (requirePublisher) {
      selectPreachers.where((p) => p.canBePublisher.equals(true));
    }

    final candidates = await selectPreachers.get();

    // 2. Fetch all shifts on the target date to find busy preachers
    // We compare dates ignoring times (just YYYY-MM-DD)
    final dayStart = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));

    final busyShifts = await (database.select(database.shifts)
          ..where((s) => s.date.isBetweenValues(dayStart, dayEnd)))
        .get();

    final busyPreacherIds = <int>{};
    for (final s in busyShifts) {
      if (s.captainId != null) {
        busyPreacherIds.add(s.captainId!);
      }
      // Fetch assigned publishers for this shift
      final assigned = await (database.select(database.shiftAssignments)
            ..where((sa) => sa.shiftId.equals(s.id)))
          .get();
      busyPreacherIds.addAll(assigned.map((a) => a.preacherId));
    }

    // Filter out busy candidates
    final eligibleCandidates = candidates.where((p) => !busyPreacherIds.contains(p.id)).toList();

    // 3. For each candidate, find their last assigned shift date
    final recommendations = <PreacherLraRecommendation>[];
    for (final p in eligibleCandidates) {
      // Find latest date where they were Captain
      final captainShifts = await (database.select(database.shifts)
            ..where((s) => s.captainId.equals(p.id))
            ..orderBy([(s) => OrderingTerm(expression: s.date, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();

      // Find latest date where they were assigned publisher
      final publisherQuery = database.select(database.shiftAssignments).join([
        innerJoin(database.shifts, database.shifts.id.equalsExp(database.shiftAssignments.shiftId)),
      ])
        ..where(database.shiftAssignments.preacherId.equals(p.id))
        ..orderBy([OrderingTerm(expression: database.shifts.date, mode: OrderingMode.desc)])
        ..limit(1);

      final publisherRow = await publisherQuery.getSingleOrNull();
      final publisherShift = publisherRow != null ? publisherRow.readTable(database.shifts) : null;

      DateTime? lastDate;
      if (captainShifts != null && publisherShift != null) {
        lastDate = captainShifts.date.isAfter(publisherShift.date)
            ? captainShifts.date
            : publisherShift.date;
      } else if (captainShifts != null) {
        lastDate = captainShifts.date;
      } else if (publisherShift != null) {
        lastDate = publisherShift.date;
      }

      recommendations.add(PreacherLraRecommendation(
        preacher: p,
        lastAssignedDate: lastDate,
      ));
    }

    // 4. Sort:
    // - Never assigned (lastAssignedDate is null) first.
    // - Oldest assignment date first.
    // - Alphabetical by last name.
    recommendations.sort((a, b) {
      if (a.lastAssignedDate == null && b.lastAssignedDate != null) return -1;
      if (a.lastAssignedDate != null && b.lastAssignedDate == null) return 1;
      if (a.lastAssignedDate != null && b.lastAssignedDate != null) {
        final dateComp = a.lastAssignedDate!.compareTo(b.lastAssignedDate!);
        if (dateComp != 0) return dateComp;
      }
      final lastNameComp = a.preacher.lastName.compareTo(b.preacher.lastName);
      if (lastNameComp != 0) return lastNameComp;
      return a.preacher.firstName.compareTo(b.preacher.firstName);
    });

    return recommendations;
  }
}
