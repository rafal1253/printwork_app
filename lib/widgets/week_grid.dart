import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/day_record.dart';
import '../utils/theme.dart';

class WeekGrid extends StatelessWidget {
  final Map<String, List<DayRecord>> weekData; // name → 7 days
  final List<DateTime> days;
  final String? selectedEmployee;
  final void Function(String employee, DateTime day, DayRecord record) onCellTap;

  const WeekGrid({
    super.key,
    required this.weekData,
    required this.days,
    this.selectedEmployee,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    final employees = weekData.keys.toList()..sort();
    final dayFmt = DateFormat('E\nd.MM', 'pl_PL');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Header row: empty cell + 7 days
          _HeaderRow(days: days, dayFmt: dayFmt),
          const Divider(height: 1),
          // Employee rows
          ...employees.map((emp) {
            final records = weekData[emp]!;
            final isSelected = selectedEmployee == emp;
            return _EmployeeRow(
              employeeName: emp,
              records: records,
              isSelected: isSelected,
              onCellTap: (day, record) => onCellTap(emp, day, record),
            );
          }),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<DateTime> days;
  final DateFormat dayFmt;
  const _HeaderRow({required this.days, required this.dayFmt});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Employee name column
        const SizedBox(
          width: 100,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text('Pracownik',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
          ),
        ),
        ...days.map((d) {
          final isToday = _isToday(d);
          final isWeekend =
              d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isToday
                    ? AppTheme.primary.withOpacity(0.07)
                    : isWeekend
                        ? AppTheme.surface
                        : null,
              ),
              child: Text(
                dayFmt.format(d),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday
                      ? AppTheme.primary
                      : isWeekend
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _EmployeeRow extends StatelessWidget {
  final String employeeName;
  final List<DayRecord> records; // 7 records
  final bool isSelected;
  final void Function(DateTime day, DayRecord record) onCellTap;

  const _EmployeeRow({
    required this.employeeName,
    required this.records,
    required this.isSelected,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primary.withOpacity(0.04) : null,
        border: Border(
          top: BorderSide(color: AppTheme.border.withOpacity(0.6)),
          left: isSelected
              ? const BorderSide(color: AppTheme.primary, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                employeeName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ...records.map((rec) => Expanded(
                child: _DayCell(
                  record: rec,
                  onTap: () => onCellTap(rec.date, rec),
                ),
              )),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DayRecord record;
  final VoidCallback onTap;

  const _DayCell({required this.record, required this.onTap});

  Color get _bgColor {
    switch (record.status) {
      case DayStatus.ok: return const Color(0xFFDCFCE7); // green light
      case DayStatus.undertime: return const Color(0xFFFEF9C3); // yellow light
      case DayStatus.anomaly: return const Color(0xFFFFE4E6); // red light
      case DayStatus.vacation: return const Color(0xFFE0F2FE); // sky light
      case DayStatus.sickLeave: return const Color(0xFFFEF3C7); // amber light
      case DayStatus.otherAbsence: return const Color(0xFFF1F5F9); // slate
      case DayStatus.weekend: return const Color(0xFFF8FAFC);
      case DayStatus.empty: return const Color(0xFFFAFAFA);
    }
  }

  Color get _textColor {
    switch (record.status) {
      case DayStatus.ok: return const Color(0xFF166534);
      case DayStatus.undertime: return const Color(0xFF854D0E);
      case DayStatus.anomaly: return const Color(0xFF9F1239);
      case DayStatus.vacation: return const Color(0xFF075985);
      case DayStatus.sickLeave: return const Color(0xFF92400E);
      case DayStatus.otherAbsence: return AppTheme.textSecondary;
      case DayStatus.weekend: return AppTheme.textHint;
      case DayStatus.empty: return AppTheme.textHint;
    }
  }

  String get _label {
    switch (record.status) {
      case DayStatus.ok:
      case DayStatus.undertime:
        return record.totalFormatted;
      case DayStatus.anomaly:
        return '⚠ ${record.totalMinutes > 0 ? record.totalFormatted : "błąd"}';
      case DayStatus.vacation: return 'Urlop';
      case DayStatus.sickLeave: return 'L4';
      case DayStatus.otherAbsence: return 'Nieobecny';
      case DayStatus.weekend: return '—';
      case DayStatus.empty: return '—';
    }
  }

  IconData? get _icon {
    switch (record.status) {
      case DayStatus.vacation: return Icons.beach_access_outlined;
      case DayStatus.sickLeave: return Icons.sick_outlined;
      case DayStatus.anomaly: return null;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = !record.isWeekend;
    return InkWell(
      onTap: isInteractive ? onTap : null,
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_icon != null)
              Icon(_icon, size: 12, color: _textColor),
            Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (record.hasAnomalies)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFF9F1239),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── LEGEND ─────────────────────────────────────────────────────

class WeekGridLegend extends StatelessWidget {
  const WeekGridLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (_LegendItem(color: Color(0xFFDCFCE7), textColor: Color(0xFF166534), label: '≥ 7.5h')),
      (_LegendItem(color: Color(0xFFFEF9C3), textColor: Color(0xFF854D0E), label: '< 7.5h')),
      (_LegendItem(color: Color(0xFFFFE4E6), textColor: Color(0xFF9F1239), label: 'Anomalia')),
      (_LegendItem(color: Color(0xFFE0F2FE), textColor: Color(0xFF075985), label: 'Urlop')),
      (_LegendItem(color: Color(0xFFFEF3C7), textColor: Color(0xFF92400E), label: 'L4')),
      (_LegendItem(color: Color(0xFFF1F5F9), textColor: AppTheme.textSecondary, label: 'Nieobecny')),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: items,
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final Color textColor;
  final String label;
  const _LegendItem(
      {required this.color, required this.textColor, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: textColor.withOpacity(0.3)),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}
