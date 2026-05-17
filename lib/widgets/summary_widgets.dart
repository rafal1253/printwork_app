// lib/widgets/summary_widgets.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/summary_data.dart';
import '../utils/theme.dart';

// ── PALETA KOLORÓW DLA TYPÓW DNI ─────────────────────────────

extension SummaryDayTypeColors on SummaryDayType {
  Color get color => switch (this) {
        SummaryDayType.ok => const Color(0xFF16A34A),
        SummaryDayType.undertime => const Color(0xFFD97706),
        SummaryDayType.anomaly => AppTheme.danger,
        SummaryDayType.vacation => const Color(0xFF0284C7),
        SummaryDayType.sickLeave => const Color(0xFFF59E0B),
        SummaryDayType.absent => const Color(0xFF6B7280),
        SummaryDayType.weekend => AppTheme.textHint,
      };

  Color get backgroundColor => switch (this) {
        SummaryDayType.ok => const Color(0xFFDCFCE7),
        SummaryDayType.undertime => const Color(0xFFFEF3C7),
        SummaryDayType.anomaly => const Color(0xFFFFE4E6),
        SummaryDayType.vacation => const Color(0xFFE0F2FE),
        SummaryDayType.sickLeave => const Color(0xFFFEF9C3),
        SummaryDayType.absent => const Color(0xFFF3F4F6),
        SummaryDayType.weekend => AppTheme.surface,
      };

  IconData get icon => switch (this) {
        SummaryDayType.ok => Icons.check_circle_outline,
        SummaryDayType.undertime => Icons.timelapse_outlined,
        SummaryDayType.anomaly => Icons.warning_amber_outlined,
        SummaryDayType.vacation => Icons.beach_access_outlined,
        SummaryDayType.sickLeave => Icons.medical_services_outlined,
        SummaryDayType.absent => Icons.person_off_outlined,
        SummaryDayType.weekend => Icons.weekend_outlined,
      };
}

// ── KARTA GODZIN (pełna szerokość, nieklikalna) ───────────────

class SummaryHoursCard extends StatelessWidget {
  final String totalFormatted;

  const SummaryHoursCard({super.key, required this.totalFormatted});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.access_time_outlined,
                size: 20, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Łączny czas pracy w roku',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                totalFormatted,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── KARTA KPI (klikalna) ──────────────────────────────────────

class SummaryKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const SummaryKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? color : Colors.white;
    final fg = isActive ? Colors.white : color;
    final borderColor = isActive ? color : AppTheme.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
          boxShadow: isActive
              ? [BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2))]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white70 : AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── RZĄD 4 KART KPI + baner godzin powyżej ───────────────────

class SummaryKpiRow extends StatelessWidget {
  final EmployeeSummary summary;
  final SummaryDayType? activeFilter;
  final ValueChanged<SummaryDayType?> onFilterChanged;

  const SummaryKpiRow({
    super.key,
    required this.summary,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  void _toggle(SummaryDayType type) {
    onFilterChanged(activeFilter == type ? null : type);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Baner godzin — pełna szerokość, nieklikalne
        SummaryHoursCard(totalFormatted: summary.totalFormatted),
        const SizedBox(height: 8),

        // 4 klikalne karty
        Row(
          children: [
            Expanded(
              child: SummaryKpiCard(
                label: 'Urlop',
                value: '${summary.vacationDays}',
                color: SummaryDayType.vacation.color,
                icon: SummaryDayType.vacation.icon,
                isActive: activeFilter == SummaryDayType.vacation,
                onTap: () => _toggle(SummaryDayType.vacation),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SummaryKpiCard(
                label: 'L4',
                value: '${summary.sickLeaveDays}',
                color: SummaryDayType.sickLeave.color,
                icon: SummaryDayType.sickLeave.icon,
                isActive: activeFilter == SummaryDayType.sickLeave,
                onTap: () => _toggle(SummaryDayType.sickLeave),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SummaryKpiCard(
                label: 'Anomalie',
                value: '${summary.anomalyDays}',
                color: SummaryDayType.anomaly.color,
                icon: SummaryDayType.anomaly.icon,
                isActive: activeFilter == SummaryDayType.anomaly,
                onTap: () => _toggle(SummaryDayType.anomaly),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SummaryKpiCard(
                label: 'Skrócone',
                value: '${summary.undertimeDays}',
                color: SummaryDayType.undertime.color,
                icon: SummaryDayType.undertime.icon,
                isActive: activeFilter == SummaryDayType.undertime,
                onTap: () => _toggle(SummaryDayType.undertime),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── WIERSZ DNIA ───────────────────────────────────────────────

class SummaryDayTile extends StatelessWidget {
  final SummaryDay day;

  const SummaryDayTile({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, d MMMM yyyy', 'pl_PL');
    final color = day.type.color;
    final bg = day.type.backgroundColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(day.type.icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmt.format(day.date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (day.note != null && day.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      day.note!,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
            child: Text(
              day.minutes > 0 ? day.formattedMinutes : day.type.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PUSTY STAN LISTY ──────────────────────────────────────────

class SummaryEmptyList extends StatelessWidget {
  final SummaryDayType type;

  const SummaryEmptyList({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(type.icon, size: 36, color: AppTheme.textHint),
            const SizedBox(height: 8),
            Text(
              'Brak dni: ${type.label.toLowerCase()}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}