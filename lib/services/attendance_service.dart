import '../models/day_record.dart';
import '../db/database_helper.dart';

/// Parsuje surowy plik CSV/TXT z rejestratora i buduje strukturę tygodniową
class AttendanceService {
  static const double dailyNormHours = 8.0;
  static const double undertimeThresholdHours = 7.5;

  // ── PARSING ────────────────────────────────────────────────

  static List<RawEvent> parseFile(String content) {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final sep = (lines.isNotEmpty && lines[0].contains('\t')) ? '\t' : ',';

    int dataStart = 0;
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (lower.contains('enno') || lower.contains('datetime')) {
        dataStart = i + 1;
        break;
      }
    }

    // Wykryj indeksy kolumn z nagłówka (odporne na różne wersje eksportu)
    int colEmpId = 2, colName = 3, colType = 6, colDateTime = -1;
    if (dataStart > 0) {
      final headerParts = lines[dataStart - 1].split(sep);
      for (int c = 0; c < headerParts.length; c++) {
        final h = headerParts[c].trim().toLowerCase();
        if (h == 'enno') colEmpId = c;
        if (h == 'name') colName = c;
        if (h == 'in/out') colType = c;
        if (h == 'datetime') colDateTime = c;
      }
    }

    final events = <RawEvent>[];
    for (int i = dataStart; i < lines.length; i++) {
      final parts = lines[i].split(sep);
      // Potrzebujemy przynajmniej tyle kolumn ile wynosi max używany indeks
      final maxCol = colDateTime >= 0 ? colDateTime : 9;
      if (parts.length <= maxCol) continue;
      try {
        final empId = parts[colEmpId].trim();
        final name = parts[colName].trim();
        final type = parts[colType].trim();
        // DateTime: użyj wykrytego indeksu, fallback na ostatnią kolumnę
        final dtStr = colDateTime >= 0
            ? parts[colDateTime].trim()
            : parts[parts.length - 1].trim();
        if (name.isEmpty || (type != 'DutyOn' && type != 'DutyOff')) continue;
        final dt = DateTime.parse(dtStr.replaceAll(' ', 'T'));
        events.add(RawEvent(
            employeeId: empId, employeeName: name, type: type, dateTime: dt));
      } catch (_) {
        continue;
      }
    }
    return events;
  }

  /// Paruje raw eventy w pary zmian per pracownik per dzień
  static List<ShiftPair> buildShifts(List<RawEvent> events) {
    final byEmployee = <String, List<RawEvent>>{};
    for (final e in events) {
      byEmployee.putIfAbsent(e.employeeName, () => []).add(e);
    }

    final shifts = <ShiftPair>[];
    byEmployee.forEach((name, evts) {
      evts.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      RawEvent? open;

      for (final e in evts) {
        if (e.type == 'DutyOn') {
          if (open != null) {
            shifts.add(ShiftPair(
              employeeId: open.employeeId,
              employeeName: name,
              dutyOn: open.dateTime,
              dutyOff: null,
              durationMinutes: null,
              anomaly: 'Brak wyjścia',
            ));
          }
          open = e;
        } else {
          if (open == null) {
            shifts.add(ShiftPair(
              employeeId: e.employeeId,
              employeeName: name,
              dutyOn: null,
              dutyOff: e.dateTime,
              durationMinutes: null,
              anomaly: 'Brak wejścia',
            ));
          } else {
            final mins = e.dateTime.difference(open.dateTime).inMinutes;
            String? anomaly;
            if (mins < 0) anomaly = 'Wyjście przed wejściem';
            else if (mins < 15) anomaly = 'Bardzo krótka zmiana (<15 min)';
            else if (mins > 960) anomaly = 'Bardzo długa zmiana (>16h)';
            shifts.add(ShiftPair(
              employeeId: open.employeeId,
              employeeName: name,
              dutyOn: open.dateTime,
              dutyOff: e.dateTime,
              durationMinutes: mins.clamp(0, 99999),
              anomaly: anomaly,
            ));
            open = null;
          }
        }
      }
      if (open != null) {
        shifts.add(ShiftPair(
          employeeId: open.employeeId,
          employeeName: name,
          dutyOn: open.dateTime,
          dutyOff: null,
          durationMinutes: null,
          anomaly: 'Brak wyjścia',
        ));
      }
    });

    return shifts;
  }

  // ── WEEK GRID BUILDER ──────────────────────────────────────

  /// Zwraca listę 7 dat dla tygodnia (pon–ndz) zawierającego [anyDay]
  static List<DateTime> weekDays(DateTime anyDay) {
    final monday =
        anyDay.subtract(Duration(days: anyDay.weekday - 1));
    return List.generate(
        7, (i) => DateTime(monday.year, monday.month, monday.day + i));
  }

  /// Buduje mapę: employeeName → List<DayRecord> dla danego tygodnia
  static Future<Map<String, List<DayRecord>>> buildWeekGrid({
    required List<String> employeeNames,
    required DateTime weekStart,
    required List<ShiftPair> allShifts,
    required Map<String, DayAbsenceType> absenceOverrides,
    required Map<String, String?> dayNotes,
  }) async {
    final days = weekDays(weekStart);
    final result = <String, List<DayRecord>>{};

    for (final name in employeeNames) {
      final dayRecords = <DayRecord>[];
      for (final day in days) {
        final dayStr = _dateKey(day);

        // Znajdź zmiany tego pracownika w tym dniu
        final dayShifts = allShifts.where((s) {
          final d = s.dutyOn ?? s.dutyOff;
          if (d == null) return false;
          return s.employeeName == name && _dateKey(d) == dayStr;
        }).toList();

        // Znajdź raw eventy (wszystkie DutyOn/DutyOff) — z bazy lub pamięci
        // Tutaj upraszczamy: raw events = wyjęte z shift par
        final rawEvts = <RawEvent>[];
        for (final s in dayShifts) {
          if (s.dutyOn != null)
            rawEvts.add(RawEvent(
                employeeId: s.employeeId,
                employeeName: name,
                type: 'DutyOn',
                dateTime: s.dutyOn!));
          if (s.dutyOff != null)
            rawEvts.add(RawEvent(
                employeeId: s.employeeId,
                employeeName: name,
                type: 'DutyOff',
                dateTime: s.dutyOff!));
        }

        final overrideKey = '${name}_$dayStr';
        final absence =
            absenceOverrides[overrideKey] ?? DayAbsenceType.none;
        final note = dayNotes[overrideKey];

        dayRecords.add(DayRecord(
          employeeId: dayShifts.isNotEmpty
              ? dayShifts.first.employeeId
              : name,
          employeeName: name,
          date: day,
          rawEvents: rawEvts,
          shifts: dayShifts,
          absenceType: absence,
          note: note,
        ));
      }
      result[name] = dayRecords;
    }
    return result;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── VALIDATION ─────────────────────────────────────────────

  static String? validateShift(DateTime? dutyOn, DateTime? dutyOff) {
    if (dutyOn == null && dutyOff == null) {
      return 'Podaj co najmniej jedną godzinę';
    }
    if (dutyOn != null && dutyOff != null) {
      if (dutyOff.isBefore(dutyOn)) {
        return 'Godzina wyjścia musi być po godzinie wejścia';
      }
      final mins = dutyOff.difference(dutyOn).inMinutes;
      if (mins > 960) {
        return 'Zmiana przekracza 16 godzin — sprawdź dane';
      }
      if (mins < 0) {
        return 'Nieprawidłowy zakres czasu';
      }
    }
    return null;
  }

  // ── WEEK SUMMARY ───────────────────────────────────────────

  static Map<String, int> weekTotals(List<DayRecord> days) {
    int totalMins = 0;
    int workedDays = 0;
    int anomalyDays = 0;

    for (final d in days) {
      if (!d.isWeekend && !d.hasManualAbsence) {
        totalMins += d.totalMinutes;
        if (d.totalMinutes > 0) workedDays++;
        if (d.hasAnomalies) anomalyDays++;
      }
    }
    return {
      'totalMinutes': totalMins,
      'workedDays': workedDays,
      'anomalyDays': anomalyDays,
    };
  }
}