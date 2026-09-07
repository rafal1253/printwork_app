import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/day_record.dart';
import '../utils/theme.dart';

/// Dialog do oznaczania wielodniowego zakresu (urlop / L4 / inna nieobecność)
/// dla jednego, wybranego pracownika.
class VacationRangeDialog extends StatefulWidget {
  final List<String> employees;
  final String? initialEmployee;

  const VacationRangeDialog({
    super.key,
    required this.employees,
    this.initialEmployee,
  });

  @override
  State<VacationRangeDialog> createState() => _VacationRangeDialogState();
}

class _VacationRangeDialogState extends State<VacationRangeDialog> {
  late String _employee;
  DateTimeRange? _range;
  DayAbsenceType _type = DayAbsenceType.vacation;
  bool _skipWeekends = true;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _employee = widget.initialEmployee ?? widget.employees.first;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _dayCount {
    if (_range == null) return 0;
    int count = 0;
    for (var d = _range!.start;
        !d.isAfter(_range!.end);
        d = d.add(const Duration(days: 1))) {
      if (_skipWeekends &&
          (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) {
        continue;
      }
      count++;
    }
    return count;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range ??
          DateTimeRange(start: now, end: now.add(const Duration(days: 4))),
      locale: const Locale('pl'),
      helpText: 'Wybierz zakres dni',
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _submit() {
    if (_range == null) return;
    Navigator.pop(context, {
      'employeeName': _employee,
      'absenceType': _type,
      'start': _range!.start,
      'end': _range!.end,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'skipWeekends': _skipWeekends,
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'pl_PL');
    return AlertDialog(
      title: const Text('Dodaj nieobecność (zakres dni)'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: _employee,
                decoration: const InputDecoration(labelText: 'Pracownik'),
                items: widget.employees
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _employee = v!),
              ),
              const SizedBox(height: 14),

              InkWell(
                onTap: _pickRange,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Zakres dni',
                    suffixIcon: Icon(Icons.date_range_outlined, size: 18),
                  ),
                  child: Text(
                    _range != null
                        ? '${fmt.format(_range!.start)} — ${fmt.format(_range!.end)}'
                        : 'Wybierz zakres',
                    style: TextStyle(
                      fontSize: 14,
                      color: _range != null
                          ? AppTheme.textPrimary
                          : AppTheme.textHint,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const Text('Typ nieobecności',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DayAbsenceType.values
                    .where((t) => t != DayAbsenceType.none)
                    .map((t) => ChoiceChip(
                          label: Text(t.label),
                          selected: _type == t,
                          onSelected: (_) => setState(() => _type = t),
                          selectedColor: AppTheme.primary.withOpacity(0.15),
                          labelStyle: TextStyle(
                            color: _type == t
                                ? AppTheme.primary
                                : AppTheme.textPrimary,
                            fontWeight: _type == t
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: _type == t
                                ? AppTheme.primary
                                : AppTheme.border,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Checkbox(
                    value: _skipWeekends,
                    onChanged: (v) =>
                        setState(() => _skipWeekends = v ?? true),
                  ),
                  const Text('Pomiń soboty i niedziele',
                      style: TextStyle(fontSize: 13)),
                ],
              ),

              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notatka (opcjonalnie)',
                  isDense: true,
                ),
                maxLines: 2,
              ),

              if (_range != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Zostanie oznaczonych: $_dayCount dni',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj')),
        ElevatedButton(
          onPressed: _range != null ? _submit : null,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}