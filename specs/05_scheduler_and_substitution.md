# SPEC-05: Scheduler and Substitution Engine

## Metadata
- **Status**: Draft
- **Author**: Spec Author (The Architect)
- **Created Date**: 2026-06-30
- **Last Updated**: 2026-06-30

---

## 1. Objectives & Scope

### 1.1 Summary
This specification outlines the business logic for daily location assignments and the automated substitution engine. The engine suggests candidates to fill vacancies in shifts based on a "Least Recently Assigned" (LRA) algorithm, while providing a manual override interface for coordinators.

### 1.2 Out of Scope
- Automated notification dispatching (SMS/Email) to the substitute (notifications are manual or handled in a future expansion).

---

## 2. Functional Requirements

### 2.1 User Stories & Use Cases
- **Assign Location**: As a coordinator, I want to assign specific preaching groups or carts to specific locations for any given day.
- **Request Substitution**: As a preacher, if I cannot attend an assigned shift, I want the coordinator to find a substitute.
- **Find Recommended Substitute**: As a coordinator, when replacing a preacher, I want the system to suggest candidates who have preached the least recently, so that scheduling remains fair and balanced.
- **Manual Override**: As a coordinator, I want to ignore the system recommendations and assign any eligible active preacher of my choice.

### 2.2 Substitution Algorithm: Least Recently Assigned (LRA)
When a vacancy needs to be filled for a Shift on Date `D` and Role `R` (Captain or regular Publisher):

1. **Filtering Candidates**:
   - Find all Preachers where `isActive = true`.
   - If `R` is **Captain**, filter `canBeCaptain = true`.
   - If `R` is **Publisher**, filter `canBePublisher = true`.
   - Exclude preachers who are already assigned to any shift on Date `D`.

2. **Calculating History**:
   - For each eligible candidate, query the database to find the date of their most recent shift assignment (either as a captain or regular assigned preacher).
   - If a preacher has no assignments in the database, set their "last assigned date" to epoch/minimum value (highest priority).

3. **Sorting**:
   - Sort candidates in ascending order of their last assigned date (oldest dates first).
   - Secondary sorting: sort alphabetically by last name and first name.

4. **Manual Override**:
   - Display the sorted recommendation list in a Spanish UI dialog.
   - The coordinator can select the top recommendation or scroll down to select any candidate.

---

## 3. Data Models & Queries

### 3.1 SQL / Drift Query for LRA
To fetch the last assignment date for all active preachers, we can write a Drift query or raw SQL compiled expression:

```dart
// Drift implementation logic inside a Repository
Future<List<PreacherWithLastDate>> getLraCandidates({
  required DateTime targetDate,
  required bool requireCaptain,
  required bool requirePublisher,
}) async {
  // Query to find last assigned shift date per preacher:
  // SELECT p.*, MAX(s.date) as last_date
  // FROM preachers p
  // LEFT JOIN shifts s ON (s.captain_id = p.id OR p.id IN (SELECT preacher_id FROM shift_assignments WHERE shift_id = s.id))
  // WHERE p.is_active = 1
  //   AND (NOT requireCaptain OR p.can_be_captain = 1)
  //   AND (NOT requirePublisher OR p.can_be_publisher = 1)
  //   AND p.id NOT IN (SELECT id of preachers assigned on targetDate)
  // GROUP BY p.id
  // ORDER BY last_date ASC NULLS FIRST, p.last_name ASC;
}
```

---

## 4. Test / Harness Plan

### 4.1 Test Scenarios
- **Scenario 1 (Fresh Preachers First)**:
  - Preacher A: Assigned 2026-06-28.
  - Preacher B: Assigned 2026-06-25.
  - Preacher C: Never assigned.
  - Query LRA candidates for 2026-06-30 -> Verify sort order is: `[C, B, A]`.
- **Scenario 2 (Exclusions)**:
  - Preacher A: Assigned to a shift on 2026-06-30.
  - Query LRA candidates for 2026-06-30 -> Verify Preacher A is excluded.
- **Scenario 3 (Capability Matching)**:
  - Require Captain -> Verify only candidates with `canBeCaptain = true` are returned.

---

## 5. Security & Performance
- **Indexed Queries**: Add indexes on `shifts(date)` and `shift_assignments(preacher_id)` to ensure fast computation of the `MAX(date)` query as the history grows.
