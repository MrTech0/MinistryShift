import 'package:ministry_shift/data/database/app_database.dart';

class ShiftValidationException implements Exception {
  final String messageKey;
  ShiftValidationException(this.messageKey);

  @override
  String toString() => 'ShiftValidationException: $messageKey';
}

class ShiftValidator {
  /// Validates shift capacity based on type and presence of Captain.
  /// [type] is either 'exhibidor' or 'salida'.
  /// [hasCaptain] indicates if a captain is assigned.
  /// [additionalPreachersCount] is the number of publishers assigned besides the Captain.
  static void validateShiftCapacity({
    required String type,
    required bool hasCaptain,
    required int additionalPreachersCount,
  }) {
    final totalPersonnel = additionalPreachersCount + (hasCaptain ? 1 : 0);
    
    if (type == 'exhibidor') {
      if (!hasCaptain) {
        throw ShiftValidationException('shift_error_captain_required');
      }
      if (totalPersonnel < 2) {
        throw ShiftValidationException('shift_error_capacity_min');
      }
      if (totalPersonnel > 6) {
        throw ShiftValidationException('shift_error_capacity_max');
      }
    } else {
      // For 'salida', we need exactly 1 person in total
      if (totalPersonnel < 1) {
        throw ShiftValidationException('shift_error_salida_empty');
      }
      if (totalPersonnel > 1) {
        throw ShiftValidationException('shift_error_salida_max');
      }
    }
  }

  /// Validates that a preacher designated as Captain is active and eligible.
  static void validateCaptainEligibility(Preacher captain) {
    if (!captain.isActive) {
      throw ShiftValidationException('shift_error_captain_inactive');
    }
    if (!captain.canBeCaptain) {
      throw ShiftValidationException('shift_error_captain_ineligible');
    }
  }

  /// Helper to check if two shifts overlap.
  /// Formats: HH:MM for times.
  static bool isTimeOverlapping(
    String start1,
    String end1,
    String start2,
    String end2,
  ) {
    final s1 = _timeToMinutes(start1);
    final e1 = _timeToMinutes(end1);
    final s2 = _timeToMinutes(start2);
    final e2 = _timeToMinutes(end2);

    return s1 < e2 && s2 < e1;
  }

  static int _timeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours * 60 + minutes;
  }
}
