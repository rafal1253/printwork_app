// lib/services/summary_service.dart

import '../db/database_helper.dart';
import '../models/summary_data.dart';

// Próg dla dnia skróconego: poniżej 7,5h (450 min)
const int _kUndertimeThreshold = 450;

class SummaryService {
  /// Pobiera dane z bazy i buduje [EmployeeSummary] dla danego pracownika i roku.
  static Future<EmployeeSummary> buildYearSummary({
    required String employeeName,
    required int year,
  }) async {
    // 1. Pobierz dane z DB
    final rawEntries = await DatabaseHelper.instance.getYearEntries(
      employeeName: employeeName,
      year: year,
    );
    final rawAbsences = await DatabaseHelper.instance.getYearAbsences(
      employeeName: employeeName,
      year: year,
    );

    // 2. Zindeksuj wpisy pracy według daty (YYYY-MM-DD)
    //    Jeden dzień może mieć wiele wpisów (np. wyjście i wejście po przerwie).
    final Map<String, List<Map<String, dynamic>>> entriesByDay = {};
    for (final e in rawEntries) {
      final dateStr = _dayKey(e['duty_on'] as String? ?? e['duty_off'] as String?);
      if (dateStr == null) continue;
      entriesByDay.putIfAbsent(dateStr, () => []).add(e);
    }

    // 3. Zindeksuj absencje według daty
    final Map<String, Map<String, dynamic>> absenceByDay = {
      for (final a in rawAbsences) a['date'] as String: a,
    };

    // 4. Iteruj po każdym dniu roboczym roku (pon–pt)
    final List<SummaryDay> days = [];
    int totalMinutes = 0;
    int vacationDays = 0;
    int sickLeaveDays = 0;
    int anomalyDays = 0;
    int undertimeDays = 0;

    final firstDay = DateTime(year, 1, 1);
    final lastDay = DateTime(year, 12, 31);

    for (var d = firstDay;
        !d.isAfter(lastDay);
        d = d.add(const Duration(days: 1))) {
      // Pomijamy weekendy
      if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
        days.add(SummaryDay(date: d, type: SummaryDayType.weekend, minutes: 0));
        continue;
      }

      final key = _formatDate(d);

      // 4a. Sprawdź absencję
      final absence = absenceByDay[key];
      if (absence != null) {
        final absType = absence['absence_type'] as String? ?? 'none';
        final note = absence['note'] as String?;

        if (absType == 'vacation') {
          vacationDays++;
          days.add(SummaryDay(
              date: d, type: SummaryDayType.vacation, minutes: 0, note: note));
          continue;
        }
        if (absType == 'sick_leave') {
          sickLeaveDays++;
          days.add(SummaryDay(
              date: d, type: SummaryDayType.sickLeave, minutes: 0, note: note));
          continue;
        }
        // 'none' lub inne — traktujemy jak brak absencji, sprawdzamy wpisy
      }

      // 4b. Sprawdź wpisy pracy
      final entries = entriesByDay[key];
      if (entries == null || entries.isEmpty) {
        // Brak wpisu — nieobecny
        days.add(SummaryDay(date: d, type: SummaryDayType.absent, minutes: 0));
        continue;
      }

      // 4c. Sprawdź anomalie: brak duty_on lub duty_off w którymkolwiek wpisie,
      //     albo ustawiona flaga anomaly
      final hasAnomaly = entries.any((e) =>
          e['duty_on'] == null ||
          e['duty_off'] == null ||
          (e['anomaly'] != null && (e['anomaly'] as String).isNotEmpty));

      if (hasAnomaly) {
        anomalyDays++;
        // Sumuj tyle minut ile mamy (mogą być częściowe)
        final mins = _sumMinutes(entries);
        days.add(SummaryDay(date: d, type: SummaryDayType.anomaly, minutes: mins));
        continue;
      }

      // 4d. Normalny dzień — oblicz czas
      final mins = _sumMinutes(entries);
      totalMinutes += mins;

      if (mins > 0 && mins < _kUndertimeThreshold) {
        undertimeDays++;
        days.add(SummaryDay(date: d, type: SummaryDayType.undertime, minutes: mins));
      } else {
        days.add(SummaryDay(date: d, type: SummaryDayType.ok, minutes: mins));
      }
    }

    return EmployeeSummary(
      employeeName: employeeName,
      year: year,
      totalMinutes: totalMinutes,
      vacationDays: vacationDays,
      sickLeaveDays: sickLeaveDays,
      anomalyDays: anomalyDays,
      undertimeDays: undertimeDays,
      days: days,
    );
  }

  // ── helpers ──────────────────────────────────────────────

  static int _sumMinutes(List<Map<String, dynamic>> entries) {
    int total = 0;
    for (final e in entries) {
      final m = e['duration_minutes'];
      if (m != null) total += m as int;
    }
    return total;
  }

  /// Zwraca 'YYYY-MM-DD' z ISO stringa datetime lub samej daty.
  static String? _dayKey(String? isoStr) {
    if (isoStr == null) return null;
    // duty_on/duty_off może być '2024-03-15 08:00:00' lub '2024-03-15T08:00:00'
    return isoStr.length >= 10 ? isoStr.substring(0, 10) : null;
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
