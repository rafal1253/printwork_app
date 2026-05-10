import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/day_record.dart';
import '../utils/theme.dart';

class AbsencePickerDialog extends StatefulWidget {
  final DateTime date;
  final String employeeName;
  final DayAbsenceType current;
  final String? currentNote;

  const AbsencePickerDialog({
    super.key,
    required this.date,
    required this.employeeName,
    required this.current,
    this.currentNote,
  });

  @override
  State<AbsencePickerDialog> createState() => _AbsencePickerDialogState();
}

class _AbsencePickerDialogState extends State<AbsencePickerDialog> {
  late DayAbsenceType _selected;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _noteCtrl = TextEditingController(text: widget.currentNote ?? '');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, d MMMM yyyy', 'pl_PL');
    return AlertDialog(
      title: const Text('Oznacz dzień'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ...DayAbsenceType.values.map((t) => _Option(
                  type: t,
                  selected: _selected == t,
                  onTap: () => setState(() => _selected = t),
                )),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Notatka (opcjonalnie)',
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'absenceType': _selected,
            'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          }),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final DayAbsenceType type;
  final bool selected;
  final VoidCallback onTap;

  const _Option(
      {required this.type, required this.selected, required this.onTap});

  Color get _color {
    switch (type) {
      case DayAbsenceType.none: return AppTheme.success;
      case DayAbsenceType.vacation: return const Color(0xFF0EA5E9);
      case DayAbsenceType.sickLeave: return const Color(0xFFF59E0B);
      case DayAbsenceType.other: return AppTheme.textSecondary;
    }
  }

  IconData get _icon {
    switch (type) {
      case DayAbsenceType.none: return Icons.work_outline;
      case DayAbsenceType.vacation: return Icons.beach_access_outlined;
      case DayAbsenceType.sickLeave: return Icons.sick_outlined;
      case DayAbsenceType.other: return Icons.event_busy_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _color : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(_icon, size: 18, color: selected ? _color : AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(type.label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? _color : AppTheme.textPrimary)),
          const Spacer(),
          if (selected)
            Icon(Icons.check_circle, size: 18, color: _color),
        ]),
      ),
    );
  }
}
