/// Typ nieobecności w danym dniu
enum DayAbsenceType {
  none('none', 'Obecny'),
  vacation('vacation', 'Urlop'),
  sickLeave('sick_leave', 'L4 / Zwolnienie'),
  other('other', 'Inna nieobecność');

  final String value;
  final String label;
  const DayAbsenceType(this.value, this.label);

  static DayAbsenceType fromValue(String? v) =>
      DayAbsenceType.values.firstWhere((e) => e.value == v,
          orElse: () => DayAbsenceType.none);
}

/// Stan dnia dla konkretnego pracownika
enum DayStatus {
  /// Przepracował ≥ 7.5h — ok
  ok,
  /// Przepracował > 0h ale < 7.5h — niedobór
  undertime,
  /// Anomalia (brak wejścia/wyjścia, duplikat)
  anomaly,
  /// Urlop oznaczony ręcznie
  vacation,
  /// L4 oznaczony ręcznie
  sickLeave,
  /// Inna nieobecność oznaczona ręcznie
  otherAbsence,
  /// Weekend / dzień wolny (sobota, niedziela)
  weekend,
  /// Brak jakiegokolwiek wpisu (dzień roboczy)
  empty,
}

class DayRecord {
  final String employeeId;
  final String employeeName;
  final DateTime date;

  /// Wszystkie surowe eventy z tego dnia (DutyOn/DutyOff)
  final List<RawEvent> rawEvents;

  /// Sparowane zmiany (po parsowaniu)
  final List<ShiftPair> shifts;

  /// Nieobecność przypisana ręcznie
  final DayAbsenceType absenceType;

  /// Notatka do dnia
  final String? note;

  const DayRecord({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.rawEvents,
    required this.shifts,
    this.absenceType = DayAbsenceType.none,
    this.note,
  });

  /// Suma minut przepracowanych w tym dniu
  int get totalMinutes =>
      shifts.fold(0, (s, sh) => s + (sh.durationMinutes ?? 0));

  String get totalFormatted {
    final m = totalMinutes;
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  bool get isWeekend =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  bool get hasAnomalies => shifts.any((s) => s.anomaly != null);

  bool get hasManualAbsence => absenceType != DayAbsenceType.none;

  DayStatus get status {
    if (isWeekend) return DayStatus.weekend;
    if (absenceType == DayAbsenceType.vacation) return DayStatus.vacation;
    if (absenceType == DayAbsenceType.sickLeave) return DayStatus.sickLeave;
    if (absenceType == DayAbsenceType.other) return DayStatus.otherAbsence;
    if (shifts.isEmpty && rawEvents.isEmpty) return DayStatus.empty;
    if (hasAnomalies) return DayStatus.anomaly;
    if (totalMinutes >= 450) return DayStatus.ok; // ≥ 7.5h
    return DayStatus.undertime;
  }
}

class ShiftPair {
  final int? id;
  final String employeeId;
  final String employeeName;
  final DateTime? dutyOn;
  final DateTime? dutyOff;
  final int? durationMinutes;
  final String? anomaly;
  /// true = ręcznie dodany / edytowany
  final bool isManual;

  const ShiftPair({
    this.id,
    required this.employeeId,
    required this.employeeName,
    this.dutyOn,
    this.dutyOff,
    this.durationMinutes,
    this.anomaly,
    this.isManual = false,
  });

  String get durationFormatted {
    if (durationMinutes == null) return '—';
    final h = durationMinutes! ~/ 60;
    final m = durationMinutes! % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  bool get hasAnomaly => anomaly != null;

  ShiftPair copyWith({
    DateTime? dutyOn,
    DateTime? dutyOff,
    int? durationMinutes,
    String? anomaly,
    bool clearAnomaly = false,
  }) {
    final newOn = dutyOn ?? this.dutyOn;
    final newOff = dutyOff ?? this.dutyOff;
    final newMins = (newOn != null && newOff != null)
        ? newOff.difference(newOn).inMinutes
        : durationMinutes ?? this.durationMinutes;
    return ShiftPair(
      id: id,
      employeeId: employeeId,
      employeeName: employeeName,
      dutyOn: newOn,
      dutyOff: newOff,
      durationMinutes: newMins,
      anomaly: clearAnomaly ? null : (anomaly ?? this.anomaly),
      isManual: true,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'duty_on': dutyOn?.toIso8601String(),
        'duty_off': dutyOff?.toIso8601String(),
        'duration_minutes': durationMinutes,
        'anomaly': anomaly,
        'source_file': isManual ? 'manual' : null,
      };

  factory ShiftPair.fromMap(Map<String, dynamic> m) => ShiftPair(
        id: m['id'],
        employeeId: m['employee_id'],
        employeeName: m['employee_name'],
        dutyOn: m['duty_on'] != null ? DateTime.parse(m['duty_on']) : null,
        dutyOff: m['duty_off'] != null ? DateTime.parse(m['duty_off']) : null,
        durationMinutes: m['duration_minutes'],
        anomaly: m['anomaly'],
        isManual: m['source_file'] == 'manual',
      );
}

class RawEvent {
  final String employeeId;
  final String employeeName;
  final String type; // DutyOn / DutyOff
  final DateTime dateTime;

  const RawEvent({
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.dateTime,
  });
}
