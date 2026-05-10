import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/day_record.dart';
import '../services/attendance_service.dart';
import '../utils/theme.dart';

/// Dialog do edycji lub dodania zmiany
class ShiftEditDialog extends StatefulWidget {
  final ShiftPair? shift; // null = nowy wpis
  final DateTime date;
  final String employeeName;
  final String employeeId;

  const ShiftEditDialog({
    super.key,
    this.shift,
    required this.date,
    required this.employeeName,
    required this.employeeId,
  });

  @override
  State<ShiftEditDialog> createState() => _ShiftEditDialogState();
}

class _ShiftEditDialogState extends State<ShiftEditDialog> {
  late TimeOfDay? _onTime;
  late TimeOfDay? _offTime;
  String? _validationError;
  bool _noEntry = false;
  bool _noExit = false;

  @override
  void initState() {
    super.initState();
    final s = widget.shift;
    _onTime = s?.dutyOn != null
        ? TimeOfDay.fromDateTime(s!.dutyOn!)
        : null;
    _offTime = s?.dutyOff != null
        ? TimeOfDay.fromDateTime(s!.dutyOff!)
        : null;
    _noEntry = s?.dutyOn == null && s?.dutyOff != null;
    _noExit = s?.dutyOff == null && s?.dutyOn != null;
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  void _validate() {
    final on = (!_noEntry && _onTime != null)
        ? _combine(widget.date, _onTime!)
        : null;
    final off = (!_noExit && _offTime != null)
        ? _combine(widget.date, _offTime!)
        : null;
    setState(() {
      _validationError = AttendanceService.validateShift(on, off);
    });
  }

  void _save() {
    _validate();
    if (_validationError != null) return;

    final on = (!_noEntry && _onTime != null)
        ? _combine(widget.date, _onTime!)
        : null;
    final off = (!_noExit && _offTime != null)
        ? _combine(widget.date, _offTime!)
        : null;

    final anomaly = (on == null || off == null)
        ? (on == null ? 'Brak wejścia' : 'Brak wyjścia')
        : null;

    final mins =
        (on != null && off != null) ? off.difference(on).inMinutes : null;

    final result = ShiftPair(
      id: widget.shift?.id,
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
      dutyOn: on,
      dutyOff: off,
      durationMinutes: mins,
      anomaly: anomaly,
      isManual: true,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.shift == null;
    final fmt = DateFormat('EEEE, d MMMM yyyy', 'pl_PL');

    return AlertDialog(
      title: Text(isNew ? 'Dodaj wpis' : 'Edytuj zmianę'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + employee info
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline,
                    size: 15, color: AppTheme.primary),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.employeeName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                    Text(fmt.format(widget.date),
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Wejście
            _timeRow(
              label: 'Wejście (DutyOn)',
              icon: Icons.login,
              time: _onTime,
              isDisabled: _noEntry,
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _onTime ?? const TimeOfDay(hour: 8, minute: 0),
                  builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!),
                );
                if (t != null) {
                  setState(() { _onTime = t; _noEntry = false; });
                  _validate();
                }
              },
              noValueLabel: 'Brak wejścia',
              onToggleAbsent: (v) =>
                  setState(() { _noEntry = v; _validate(); }),
              isAbsent: _noEntry,
            ),

            const SizedBox(height: 12),

            // Wyjście
            _timeRow(
              label: 'Wyjście (DutyOff)',
              icon: Icons.logout,
              time: _offTime,
              isDisabled: _noExit,
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime:
                      _offTime ?? const TimeOfDay(hour: 16, minute: 0),
                  builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!),
                );
                if (t != null) {
                  setState(() { _offTime = t; _noExit = false; });
                  _validate();
                }
              },
              noValueLabel: 'Brak wyjścia',
              onToggleAbsent: (v) =>
                  setState(() { _noExit = v; _validate(); }),
              isAbsent: _noExit,
            ),

            // Preview czasu
            if (_onTime != null &&
                _offTime != null &&
                !_noEntry &&
                !_noExit) ...[
              const SizedBox(height: 14),
              Builder(builder: (_) {
                final on = _combine(widget.date, _onTime!);
                final off = _combine(widget.date, _offTime!);
                final mins = off.difference(on).inMinutes;
                final ok = mins >= 0 && mins <= 960;
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ok
                        ? AppTheme.success.withOpacity(0.08)
                        : AppTheme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(ok ? Icons.check_circle_outline : Icons.warning_amber,
                        size: 15,
                        color: ok ? AppTheme.success : AppTheme.warning),
                    const SizedBox(width: 6),
                    Text(
                      ok
                          ? 'Czas pracy: ${mins ~/ 60}h ${mins % 60}m'
                          : 'Nieprawidłowy zakres',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              ok ? AppTheme.success : AppTheme.warning),
                    ),
                  ]),
                );
              }),
            ],

            // Błąd walidacji
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.error_outline,
                    size: 15, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_validationError!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.danger)),
                ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj')),
        ElevatedButton(
            onPressed: _save, child: Text(isNew ? 'Dodaj' : 'Zapisz')),
      ],
    );
  }

  Widget _timeRow({
    required String label,
    required IconData icon,
    required TimeOfDay? time,
    required bool isDisabled,
    required VoidCallback onTap,
    required String noValueLabel,
    required ValueChanged<bool> onToggleAbsent,
    required bool isAbsent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: isAbsent ? null : onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: isAbsent
                      ? AppTheme.surface
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAbsent
                        ? AppTheme.border
                        : AppTheme.primary.withOpacity(0.4),
                  ),
                ),
                child: Row(children: [
                  Icon(icon,
                      size: 16,
                      color: isAbsent
                          ? AppTheme.textHint
                          : AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    isAbsent
                        ? noValueLabel
                        : (time != null
                            ? time.format(context)
                            : 'Wybierz godzinę'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isAbsent
                          ? AppTheme.textHint
                          : (time != null
                              ? AppTheme.textPrimary
                              : AppTheme.textHint),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isAbsent ? 'Przywróć' : 'Oznacz jako brak',
            child: IconButton(
              icon: Icon(
                isAbsent
                    ? Icons.undo_outlined
                    : Icons.remove_circle_outline,
                size: 20,
                color:
                    isAbsent ? AppTheme.primary : AppTheme.textSecondary,
              ),
              onPressed: () => onToggleAbsent(!isAbsent),
            ),
          ),
        ]),
      ],
    );
  }
}
