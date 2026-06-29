// lib/models/summary_data.dart

enum SummaryDayType {
  ok,
  undertime,
  anomaly,
  vacation,
  sickLeave,
  absent,
  weekend,
}

extension SummaryDayTypeLabel on SummaryDayType {
  String get label => switch (this) {
        SummaryDayType.ok => 'Obecny',
        SummaryDayType.undertime => 'Skrócony dzień',
        SummaryDayType.anomaly => 'Anomalia',
        SummaryDayType.vacation => 'Urlop',
        SummaryDayType.sickLeave => 'L4',
        SummaryDayType.absent => 'Nieobecny',
        SummaryDayType.weekend => 'Weekend',
      };
}

class SummaryDay {
  final DateTime date;
  final SummaryDayType type;

  /// Przepracowane minuty (0 jeśli absencja / brak wpisu).
  final int minutes;

  /// Opcjonalna notatka z day_absences.
  final String? note;

  const SummaryDay({
    required this.date,
    required this.type,
    required this.minutes,
    this.note,
  });

  String get formattedMinutes {
    if (minutes <= 0) return '—';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

class EmployeeSummary {
  final String employeeName;
  final int year;

  /// Suma minut przepracowanych (wyłącznie dni z wpisem, bez absencji).
  final int totalMinutes;

  /// Liczba dni urlopu.
  final int vacationDays;

  /// Liczba dni L4.
  final int sickLeaveDays;

  /// Liczba dni z anomalią (brak duty_on lub duty_off, lub flaga anomaly != null).
  final int anomalyDays;

  /// Liczba dni poniżej 7,5 h (> 0 min, < 450 min) bez anomalii i absencji.
  final int undertimeDays;

  /// Wszystkie dni robocze roku (pon–pt) z pełnym opisem.
  final List<SummaryDay> days;

  const EmployeeSummary({
    required this.employeeName,
    required this.year,
    required this.totalMinutes,
    required this.vacationDays,
    required this.sickLeaveDays,
    required this.anomalyDays,
    required this.undertimeDays,
    required this.days,
  });

  String get totalFormatted {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  /// Dni pasujące do danego filtra (do wyświetlenia na liście).
  List<SummaryDay> filtered(SummaryDayType type) =>
      days.where((d) => d.type == type).toList();
}
