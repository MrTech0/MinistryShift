# SPEC-04: Domain Models, Database Schema, and Calendar Views

## Metadata
- **Status**: Draft
- **Author**: Spec Author (The Architect)
- **Created Date**: 2026-06-30
- **Last Updated**: 2026-06-30

---

## 1. Objectives & Scope

### 1.1 Summary
This specification defines the domain models, SQLite database tables (using Drift), relational constraints, and core invariants for MinistryShift. It also details the user requirements for weekly and monthly calendar views.

### 1.2 Out of Scope
- Scheduling shifts across multiple years (the calendar view is focused on the current year).
- Automatic synchronization with external calendars (Google Calendar, iCal).

---

## 2. Functional Requirements

### 2.1 User Stories
- **Preacher Management**: As an coordinator, I want to add, edit, and disable preachers, specifying their availability and roles (Preacher, Publisher, Captain).
- **Location Config**: As a coordinator, I want to define public locations where carts can be placed.
- **Shift Creation**: As a coordinator, I want to create a shift for a specific location, date, and time, assigning a Captain and other preachers.
- **Calendar Visualization**: As a preacher, I want to see my assigned shifts on weekly and monthly calendars.

### 2.2 Domain Constraints & Invariants
- **Roles**:
  - **Preacher (Predicador)**: Standard role. Any active person.
  - **Cart Publisher (Publicador de Carrito)**: Can handle carts.
  - **Cart Captain (Capitán de Carrito)**: Can lead a shift and manage the carts.
- **Shift Staffing Invariants**:
  - Every shift **must** have exactly 1 Captain assigned.
  - Total attendance (including the Captain) must satisfy:
    - **Minimum**: 3 people (representing 1 active cart).
    - **Maximum**: 6 people (representing 2 active carts).
  - Preachers cannot be double-assigned to overlapping shifts on the same day.

### 2.3 Calendar Views (Spanish UI Requirements)
- **Monthly View**: Grid format showing all days of the month. Days with shifts show color-coded indicator dots or brief list items (Location + Time). Clicking a day reveals a detailed list of shifts in a side panel or modal.
- **Weekly View**: Columnar or row view of the 7 days of the week, displaying time blocks and assigned personnel directly.

---

## 3. Data Models & Database Schemas

### 3.1 Table Definitions (Drift / Dart)

```dart
import 'package:drift/drift.dart';

// Preachers Table
class Preachers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get firstName => text().withLength(min: 1, max: 100)();
  TextColumn get lastName => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().nullable().withLength(max: 100)();
  TextColumn get phone => text().nullable().withLength(max: 50)();
  BoolColumn get isActive => Alignment().withDefault(const Constant(true))();
  BoolColumn get canBeCaptain => Alignment().withDefault(const Constant(false))();
  BoolColumn get canBePublisher => Alignment().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Locations Table
class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable().withLength(max: 255)();
  BoolColumn get isActive => Alignment().withDefault(const Constant(true))();
}

// Shifts Table
class Shifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()(); // YYYY-MM-DD
  TextColumn get startTime => text().withLength(min: 5, max: 5)(); // HH:MM
  TextColumn get endTime => text().withLength(min: 5, max: 5)(); // HH:MM
  IntColumn get locationId => integer().references(Locations, #id)();
  IntColumn get captainId => integer().references(Preachers, #id)();
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
```

---

## 4. Test / Harness Plan

### 4.1 Test Scenarios
- **Scenario 1 (Shift Invariants - Captain)**:
  - Attempt to insert a shift without a `captainId` -> Verify SQLite reference constraint/Drift compilation prevents it.
- **Scenario 2 (Shift Invariants - Capacity)**:
  - Create a custom validation method `validateShiftCapacity(int preacherCount)`:
    - Count = 1 (only captain) -> throws validation error.
    - Count = 2 (captain + 1 preacher) -> throws validation error.
    - Count = 3 -> valid.
    - Count = 6 -> valid.
    - Count = 7 -> throws validation error.
- **Scenario 3 (Overlapping assignments)**:
  - Preacher A is assigned to Shift 1 on 2026-07-01 from 09:00 to 11:00.
  - Attempt to assign Preacher A to Shift 2 on 2026-07-01 from 10:00 to 12:00 -> Verify overlapping validator blocks it.

---

## 5. Security & System Constraints
- **Foreign Key Support**: SQLite foreign keys must be enabled on every database opening via:
  ```sql
  PRAGMA foreign_keys = ON;
  ```
  *(This is done in the NativeDatabase setup callback alongside the encryption key)*.
