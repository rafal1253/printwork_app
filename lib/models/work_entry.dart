class WorkEntry {
  final int? id;
  final String employeeId;
  final String employeeName;
  final DateTime? dutyOn;
  final DateTime? dutyOff;
  final int? durationMinutes;
  final String? anomaly;
  final String? sourceFile;

  WorkEntry({
    this.id,
    required this.employeeId,
    required this.employeeName,
    this.dutyOn,
    this.dutyOff,
    this.durationMinutes,
    this.anomaly,
    this.sourceFile,
  });

  Map<String, dynamic> toMap() => {
        'employee_id': employeeId,
        'employee_name': employeeName,
        'duty_on': dutyOn?.toIso8601String(),
        'duty_off': dutyOff?.toIso8601String(),
        'duration_minutes': durationMinutes,
        'anomaly': anomaly,
        'source_file': sourceFile,
      };

  factory WorkEntry.fromMap(Map<String, dynamic> m) => WorkEntry(
        id: m['id'],
        employeeId: m['employee_id'],
        employeeName: m['employee_name'],
        dutyOn: m['duty_on'] != null ? DateTime.parse(m['duty_on']) : null,
        dutyOff: m['duty_off'] != null ? DateTime.parse(m['duty_off']) : null,
        durationMinutes: m['duration_minutes'],
        anomaly: m['anomaly'],
        sourceFile: m['source_file'],
      );

  String get durationFormatted {
    if (durationMinutes == null) return '—';
    final h = durationMinutes! ~/ 60;
    final m = durationMinutes! % 60;
    return '${h}h ${m}m';
  }

  bool get hasAnomaly => anomaly != null;
}

// ── CSV / TXT PARSER ──────────────────────────────────────────

class TimeRegistryParser {
  /// Parses the tab-separated export from the time recorder.
  /// Returns paired WorkEntry list (each entry = one shift).
  static List<WorkEntry> parse(String content, String sourceFile) {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Detect separator (tab or comma)
    final sep = lines.isNotEmpty && lines[0].contains('\t') ? '\t' : ',';

    // Find header row
    int dataStart = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains('enno') ||
          lines[i].toLowerCase().contains('datetime')) {
        dataStart = i + 1;
        break;
      }
    }

    // Parse raw events
    final List<_RawEvent> events = [];
    for (int i = dataStart; i < lines.length; i++) {
      final parts = lines[i].split(sep);
      if (parts.length < 9) continue;
      try {
        final name = parts[3].trim();
        final type = parts[6].trim(); // DutyOn / DutyOff
        final dtStr = parts[8].trim();
        final dt = DateTime.parse(dtStr.replaceAll(' ', 'T'));
        if (name.isEmpty || (type != 'DutyOn' && type != 'DutyOff')) continue;
        events.add(_RawEvent(
          employeeId: parts[2].trim(),
          name: name,
          type: type,
          dateTime: dt,
        ));
      } catch (_) {
        continue;
      }
    }

    return _pairEvents(events, sourceFile);
  }

  static List<WorkEntry> _pairEvents(
      List<_RawEvent> events, String sourceFile) {
    // Group by employee
    final byEmployee = <String, List<_RawEvent>>{};
    for (final e in events) {
      byEmployee.putIfAbsent(e.name, () => []).add(e);
    }

    final shifts = <WorkEntry>[];

    byEmployee.forEach((name, evts) {
      evts.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      _RawEvent? open;

      for (final e in evts) {
        if (e.type == 'DutyOn') {
          if (open != null) {
            // Previous On without Off
            shifts.add(WorkEntry(
              employeeId: open.employeeId,
              employeeName: name,
              dutyOn: open.dateTime,
              dutyOff: null,
              durationMinutes: null,
              anomaly: 'brak wyjścia',
              sourceFile: sourceFile,
            ));
          }
          open = e;
        } else if (e.type == 'DutyOff') {
          if (open == null) {
            shifts.add(WorkEntry(
              employeeId: e.employeeId,
              employeeName: name,
              dutyOn: null,
              dutyOff: e.dateTime,
              durationMinutes: null,
              anomaly: 'brak wejścia',
              sourceFile: sourceFile,
            ));
          } else {
            final mins =
                e.dateTime.difference(open.dateTime).inMinutes;
            String? anomaly;
            if (mins < 60) anomaly = 'bardzo krótka zmiana (<1h)';
            if (mins > 720) anomaly = 'bardzo długa zmiana (>12h)';
            shifts.add(WorkEntry(
              employeeId: open.employeeId,
              employeeName: name,
              dutyOn: open.dateTime,
              dutyOff: e.dateTime,
              durationMinutes: mins,
              anomaly: anomaly,
              sourceFile: sourceFile,
            ));
            open = null;
          }
        }
      }
      if (open != null) {
        shifts.add(WorkEntry(
          employeeId: open.employeeId,
          employeeName: name,
          dutyOn: open.dateTime,
          dutyOff: null,
          durationMinutes: null,
          anomaly: 'brak wyjścia',
          sourceFile: sourceFile,
        ));
      }
    });

    shifts.sort((a, b) =>
        (a.dutyOn ?? a.dutyOff ?? DateTime(0))
            .compareTo(b.dutyOn ?? b.dutyOff ?? DateTime(0)));
    return shifts;
  }
}

class _RawEvent {
  final String employeeId;
  final String name;
  final String type;
  final DateTime dateTime;
  const _RawEvent(
      {required this.employeeId,
      required this.name,
      required this.type,
      required this.dateTime});
}
