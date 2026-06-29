// lib/screens/time_tracking/attendance_screen.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../models/day_record.dart';
import '../../services/attendance_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/week_grid.dart';
import '../../widgets/shift_edit_dialog.dart';
import '../../widgets/absence_picker_dialog.dart';
import '../../widgets/week_picker_dialog.dart';
import '../../widgets/summary_tab.dart';


class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  // ── TabController ─────────────────────────────────────────
  late final TabController _tabController;

  // Data
  List<ShiftPair> _allShifts = [];
  List<String> _employees = [];
  Map<String, List<DayRecord>> _weekGrid = {};

  // State
  DateTime _selectedWeekStart = _currentMonday();
  String? _selectedEmployee;
  bool _loading = false;
  bool _hasData = false;

  // Overrides (absence types + notes) — stored in memory, persisted to DB
  final Map<String, DayAbsenceType> _absenceOverrides = {};
  final Map<String, String?> _dayNotes = {};

  static DateTime _currentMonday() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFromDb();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFromDb() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getWorkEntries();
    final names = await DatabaseHelper.instance.getEmployeeNames();
    final absences = await DatabaseHelper.instance.getAbsenceOverrides();

    _allShifts = rows.map(ShiftPair.fromMap).toList();
    _employees = names;
    _absenceOverrides.clear();
    _dayNotes.clear();
    for (final a in absences) {
      final key = '${a['employee_name']}_${a['date']}';
      _absenceOverrides[key] = DayAbsenceType.fromValue(a['absence_type']);
      _dayNotes[key] = a['note'];
    }

    _hasData = _allShifts.isNotEmpty;
    if (_employees.isNotEmpty) _selectedEmployee = _employees.first;

    await _buildGrid();
    setState(() => _loading = false);
  }

  Future<void> _buildGrid() async {
    _weekGrid = await AttendanceService.buildWeekGrid(
      employeeNames: _employees,
      weekStart: _selectedWeekStart,
      allShifts: _allShifts,
      absenceOverrides: _absenceOverrides,
      dayNotes: _dayNotes,
    );
  }

  // ── IMPORT ─────────────────────────────────────────────────

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'tsv'],
      dialogTitle: 'Wybierz plik z rejestratora czasu pracy',
    );
    if (result == null) return;

    setState(() => _loading = true);
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      String content;
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        content = String.fromCharCodes(bytes.sublist(2).buffer.asUint16List());
      } else {
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          content = latin1.decode(bytes);
        }
      }
      final fileName = result.files.single.name;

      // ── DIAGNOSTYKA ──────────────────────────────────────
      debugPrint('=== IMPORT START: $fileName ===');
      debugPrint('Rozmiar pliku: ${bytes.length} bajtów');
      debugPrint('BOM UTF-16: ${bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE}');
      final lines = content.split('\n');
      debugPrint('Liczba linii: ${lines.length}');
      debugPrint('--- Pierwsze 3 linie ---');
      for (int i = 0; i < lines.length && i < 3; i++) {
        debugPrint('  [$i]: ${lines[i]}');
      }
      // ─────────────────────────────────────────────────────

      final events = AttendanceService.parseFile(content);
      debugPrint('Events sparsowane: ${events.length}');
      if (events.isNotEmpty) {
        debugPrint('  Przykład: ${events.first.employeeName} | ${events.first.type} | ${events.first.dateTime}');
      }

      final shifts = AttendanceService.buildShifts(events);
      debugPrint('Shifts zbudowane: ${shifts.length}');
      if (shifts.isNotEmpty) {
        debugPrint('  Przykład: ${shifts.first.employeeName} | on=${shifts.first.dutyOn} | off=${shifts.first.dutyOff}');
      }

      // Deduplikacja per zmiana (nie per dzień) — pozwala doimportować nowe dni
      // z pliku zawierającego również już zapisane zmiany.
      final existing = await DatabaseHelper.instance.getExistingShiftKeys();
      debugPrint('Istniejące klucze w DB: ${existing.length}');
      if (existing.isNotEmpty) {
        debugPrint('  Przykład klucza DB: ${existing.first}');
      }

      int added = 0;
      int skipped = 0;
      for (final s in shifts) {
        if (s.dutyOn == null && s.dutyOff == null) continue;
        // Klucz: pracownik + dokładny czas wejścia;
        // dla anomalii "brak wejścia" używamy czasu wyjścia z prefiksem "off_"
        final shiftKey = s.dutyOn != null
            ? '${s.employeeName}_${s.dutyOn!.toIso8601String()}'
            : '${s.employeeName}_off_${s.dutyOff!.toIso8601String()}';
        if (added == 0 && skipped == 0) {
          debugPrint('  Przykład klucza nowego: $shiftKey');
          debugPrint('  Czy istnieje w DB: ${existing.contains(shiftKey)}');
        }
        if (existing.contains(shiftKey)) { skipped++; continue; }
        await DatabaseHelper.instance.insertWorkEntry(s.toMap());
        added++;
      }
      debugPrint('Dodano: $added, Pominięto: $skipped');

      // Reload all from DB (pracownicy z bazy, nie z pamięci)
      final allRows = await DatabaseHelper.instance.getWorkEntries();
      _allShifts = allRows.map(ShiftPair.fromMap).toList();
      _employees = await DatabaseHelper.instance.getEmployeeNames();
      _selectedEmployee = _employees.isNotEmpty ? _employees.first : null;
      _hasData = _allShifts.isNotEmpty;
      debugPrint('Wszystkich wpisów w DB po imporcie: ${_allShifts.length}');
      debugPrint('Pracownicy: $_employees');
      debugPrint('_hasData: $_hasData');

      // Ustaw tydzień na pierwszy tydzień danych
      if (shifts.isNotEmpty) {
        final firstDate =
            shifts.map((s) => s.dutyOn ?? s.dutyOff!).reduce(
                (a, b) => a.isBefore(b) ? a : b);
        _selectedWeekStart = firstDate
            .subtract(Duration(days: firstDate.weekday - 1));
        debugPrint('Ustawiono tydzień na: $_selectedWeekStart');
      }

      await _buildGrid();
      debugPrint('weekGrid keys: ${_weekGrid.keys.toList()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Dodano: $added nowych zmian, pominięto: $skipped (duplikaty)'),
          backgroundColor: added > 0 ? AppTheme.success : AppTheme.warning,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Błąd importu: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
    setState(() => _loading = false);
  }

  // ── WEEK NAVIGATION ────────────────────────────────────────

  void _prevWeek() async {
    _selectedWeekStart =
        _selectedWeekStart.subtract(const Duration(days: 7));
    setState(() => _loading = true);
    await _buildGrid();
    setState(() => _loading = false);
  }

  void _nextWeek() async {
    _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    setState(() => _loading = true);
    await _buildGrid();
    setState(() => _loading = false);
  }

  // ── CELL TAP → inspect / set absence ──────────────────────

  Future<void> _onCellTap(
      String employee, DateTime day, DayRecord record) async {
    setState(() => _selectedEmployee = employee);

    if (!record.isWeekend &&
        record.shifts.isEmpty &&
        record.rawEvents.isEmpty) {
      await _showAbsenceDialog(employee, day, record);
      return;
    }

    if (record.hasManualAbsence) {
      await _showAbsenceDialog(employee, day, record);
      return;
    }
  }

  Future<void> _showAbsenceDialog(
      String employee, DateTime day, DayRecord record) async {
    final key = '${employee}_${_dateKey(day)}';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AbsencePickerDialog(
        date: day,
        employeeName: employee,
        current: _absenceOverrides[key] ?? DayAbsenceType.none,
        currentNote: _dayNotes[key],
      ),
    );
    if (result == null) return;

    final absence = result['absenceType'] as DayAbsenceType;
    final note = result['note'] as String?;

    _absenceOverrides[key] = absence;
    _dayNotes[key] = note;

    await DatabaseHelper.instance.upsertAbsenceOverride(
      employeeName: employee,
      date: _dateKey(day),
      absenceType: absence.value,
      note: note,
    );

    await _buildGrid();
    setState(() {});
  }

  // ── EDIT SHIFT ─────────────────────────────────────────────

  Future<void> _editShift(ShiftPair shift) async {
    final date = shift.dutyOn ?? shift.dutyOff!;
    final result = await showDialog<ShiftPair>(
      context: context,
      builder: (_) => ShiftEditDialog(
        shift: shift,
        date: DateTime(date.year, date.month, date.day),
        employeeName: shift.employeeName,
        employeeId: shift.employeeId,
      ),
    );
    if (result == null) return;

    await DatabaseHelper.instance.updateWorkEntry(result.toMap());

    final idx = _allShifts.indexWhere((s) => s.id == result.id);
    if (idx >= 0) _allShifts[idx] = result;

    await _buildGrid();
    setState(() {});
  }

  Future<void> _addShift(DateTime day, String employee) async {
    final empId = _allShifts
        .firstWhere((s) => s.employeeName == employee,
            orElse: () => ShiftPair(
                employeeId: employee,
                employeeName: employee))
        .employeeId;

    final result = await showDialog<ShiftPair>(
      context: context,
      builder: (_) => ShiftEditDialog(
        date: day,
        employeeName: employee,
        employeeId: empId,
      ),
    );
    if (result == null) return;

    final id = await DatabaseHelper.instance.insertWorkEntry(result.toMap());
    final saved = ShiftPair(
      id: id,
      employeeId: result.employeeId,
      employeeName: result.employeeName,
      dutyOn: result.dutyOn,
      dutyOff: result.dutyOff,
      durationMinutes: result.durationMinutes,
      anomaly: result.anomaly,
      isManual: true,
    );
    _allShifts.add(saved);

    await _buildGrid();
    setState(() {});
  }

  // ── BUILD ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Czas pracy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Importuj plik CSV/TXT',
            onPressed: _importFile,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Grafik'),
            Tab(text: 'Podsumowanie'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Zakładka 1: Grafik ──
          _buildScheduleTab(),

          // ── Zakładka 2: Podsumowanie ──
          SummaryTab(employees: _employees),
        ],
      ),
    );
  }

  // ── ZAKŁADKA GRAFIK (dawna _buildContent) ─────────────────

  Widget _buildScheduleTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasData) {
      return EmptyState(
        icon: Icons.upload_file_outlined,
        title: 'Brak danych',
        subtitle: 'Zaimportuj plik TXT lub CSV z rejestratora czasu pracy',
        action: ElevatedButton.icon(
          onPressed: _importFile,
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Importuj plik'),
        ),
      );
    }
    return _buildContent();
  }

  Widget _buildContent() {
    final days = AttendanceService.weekDays(_selectedWeekStart);

    return Column(
      children: [
        // ── Week navigator ──
        _WeekNavigator(
          weekStart: _selectedWeekStart,
          onPrev: _prevWeek,
          onNext: _nextWeek,
<<<<<<< HEAD
          onWeekPicked: (newMonday) async {
            setState(() {
              _selectedWeekStart = newMonday;
              _loading = true;
            });
=======
          onPickWeek: (picked) async {
            _selectedWeekStart = picked;
            setState(() => _loading = true);
>>>>>>> New-picker-for-work-time
            await _buildGrid();
            setState(() => _loading = false);
          },
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WeekGridLegend(),
                const SizedBox(height: 8),
                WeekGrid(
                  weekData: _weekGrid,
                  days: days,
                  selectedEmployee: _selectedEmployee,
                  onCellTap: _onCellTap,
                ),

                const SizedBox(height: 20),

                if (_selectedEmployee != null) ...[
                  _buildEmployeeSelector(),
                  const SizedBox(height: 12),
                  _buildWeekDetail(days),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _employees.map((name) {
          final isSelected = name == _selectedEmployee;
          return GestureDetector(
            onTap: () => setState(() => _selectedEmployee = name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : AppTheme.border,
                ),
              ),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeekDetail(List<DateTime> days) {
    final empRecords = _weekGrid[_selectedEmployee] ?? [];
    final totals = AttendanceService.weekTotals(empRecords);
    final totalM = totals['totalMinutes']!;
    final totalH = totalM ~/ 60;
    final totalMin = totalM % 60;
    final anomalyDays = totals['anomalyDays']!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionHeader(title: '$_selectedEmployee — tydzień'),
            const Spacer(),
            _SummaryChip(
                label: 'Razem',
                value: '${totalH}h ${totalMin}m',
                color: AppTheme.primary),
            const SizedBox(width: 8),
            if (anomalyDays > 0)
              _SummaryChip(
                  label: 'Anomalie',
                  value: '$anomalyDays',
                  color: AppTheme.danger),
          ],
        ),
        const SizedBox(height: 10),

        ...empRecords.map((rec) => _DayDetailCard(
              record: rec,
              onEditShift: _editShift,
              onAddShift: () => _addShift(rec.date, _selectedEmployee!),
              onSetAbsence: () =>
                  _showAbsenceDialog(_selectedEmployee!, rec.date, rec),
            )),
      ],
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── WEEK NAVIGATOR ────────────────────────────────────────────

class _WeekNavigator extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
<<<<<<< HEAD
  final Function(DateTime) onWeekPicked;
=======
  final Future<void> Function(DateTime picked) onPickWeek;
>>>>>>> New-picker-for-work-time

  const _WeekNavigator({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
<<<<<<< HEAD
    required this.onWeekPicked,
=======
    required this.onPickWeek,
>>>>>>> New-picker-for-work-time
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final fmt = DateFormat('d MMM', 'pl_PL');
    final yearFmt = DateFormat('yyyy');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: GestureDetector(
<<<<<<< HEAD
              onTap: () => _showWeekPickerModal(context),
              child: Column(
                children: [
                  Text(
                    '${fmt.format(weekStart)} — ${fmt.format(weekEnd)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Text(yearFmt.format(weekStart),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
=======
              onTap: () => _openPicker(context),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${fmt.format(weekStart)} — ${fmt.format(weekEnd)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        yearFmt.format(weekStart),
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more,
                      size: 18, color: AppTheme.textSecondary),
>>>>>>> New-picker-for-work-time
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

<<<<<<< HEAD
  void _showWeekPickerModal(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext ctx) => _WeekPickerModal(
        initialWeekStart: weekStart,
        onWeekSelected: (selected) {
          Navigator.pop(ctx);
          onWeekPicked(selected);
        },
      ),
    );
=======
  Future<void> _openPicker(BuildContext context) async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (_) => WeekPickerDialog(currentWeekStart: weekStart),
    );
    if (result != null) await onPickWeek(result);
>>>>>>> New-picker-for-work-time
  }
}

// ── DAY DETAIL CARD ───────────────────────────────────────────

class _DayDetailCard extends StatelessWidget {
  final DayRecord record;
  final Function(ShiftPair) onEditShift;
  final VoidCallback onAddShift;
  final VoidCallback onSetAbsence;

  const _DayDetailCard({
    required this.record,
    required this.onEditShift,
    required this.onAddShift,
    required this.onSetAbsence,
  });

  Color get _borderColor {
    switch (record.status) {
      case DayStatus.anomaly: return AppTheme.danger;
      case DayStatus.undertime: return AppTheme.warning;
      case DayStatus.vacation: return const Color(0xFF0EA5E9);
      case DayStatus.sickLeave: return const Color(0xFFF59E0B);
      default: return AppTheme.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayFmt = DateFormat('EEEE, d MMMM', 'pl_PL');
    final timeFmt = DateFormat('HH:mm');
    final isWeekend = record.isWeekend;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isWeekend ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Text(
                  dayFmt.format(record.date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isWeekend
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                if (record.hasManualAbsence)
                  _absenceBadge(record.absenceType),
                if (!isWeekend && record.totalMinutes > 0)
                  _timeBadge(record.totalFormatted, record.status),
                if (!isWeekend)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: AppTheme.textSecondary),
                    onSelected: (v) {
                      if (v == 'add') onAddShift();
                      if (v == 'absence') onSetAbsence();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'add',
                          child: Row(children: [
                            Icon(Icons.add, size: 16),
                            SizedBox(width: 8),
                            Text('Dodaj wpis'),
                          ])),
                      const PopupMenuItem(
                          value: 'absence',
                          child: Row(children: [
                            Icon(Icons.event_busy_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('Oznacz dzień'),
                          ])),
                    ],
                  ),
              ],
            ),
          ),

          if (record.shifts.isNotEmpty) ...[
            const Divider(height: 1),
            ...record.shifts.map((shift) => _ShiftRow(
                  shift: shift,
                  timeFmt: timeFmt,
                  onEdit: () => onEditShift(shift),
                )),
          ] else if (!isWeekend && !record.hasManualAbsence)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 13, color: AppTheme.textHint),
                  const SizedBox(width: 6),
                  const Text('Brak wpisów',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textHint)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onAddShift,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Dodaj', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeBadge(String label, DayStatus status) {
    Color c;
    Color bg;
    if (status == DayStatus.ok) {
      c = const Color(0xFF166534);
      bg = const Color(0xFFDCFCE7);
    } else if (status == DayStatus.undertime) {
      c = const Color(0xFF854D0E);
      bg = const Color(0xFFFEF9C3);
    } else {
      c = const Color(0xFF9F1239);
      bg = const Color(0xFFFFE4E6);
    }
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    );
  }

  Widget _absenceBadge(DayAbsenceType type) {
    final (Color c, Color bg) = switch (type) {
      DayAbsenceType.vacation =>
        (const Color(0xFF075985), const Color(0xFFE0F2FE)),
      DayAbsenceType.sickLeave =>
        (const Color(0xFF92400E), const Color(0xFFFEF3C7)),
      _ => (AppTheme.textSecondary, AppTheme.surface),
    };
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(type.label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

// ── SHIFT ROW ──────────────────────────────────────────────────

class _ShiftRow extends StatelessWidget {
  final ShiftPair shift;
  final DateFormat timeFmt;
  final VoidCallback onEdit;

  const _ShiftRow(
      {required this.shift, required this.timeFmt, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            _timeCell(
              Icons.login,
              shift.dutyOn != null ? timeFmt.format(shift.dutyOn!) : null,
              isAnomaly: shift.dutyOn == null,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child:
                  Icon(Icons.arrow_forward, size: 12, color: AppTheme.textHint),
            ),
            _timeCell(
              Icons.logout,
              shift.dutyOff != null ? timeFmt.format(shift.dutyOff!) : null,
              isAnomaly: shift.dutyOff == null,
            ),
            const SizedBox(width: 12),
            Text(
              shift.durationFormatted,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
            const Spacer(),
            if (shift.hasAnomaly)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  shift.anomaly!,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w500),
                ),
              ),
            if (shift.isManual)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Ręcznie edytowany',
                  child: Icon(Icons.edit_outlined,
                      size: 13, color: AppTheme.textHint),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.chevron_right,
                  size: 16, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeCell(IconData icon, String? time, {bool isAnomaly = false}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: isAnomaly ? AppTheme.danger : AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            time ?? 'brak',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isAnomaly ? AppTheme.danger : AppTheme.textPrimary,
            ),
          ),
        ],
      );
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 12, color: color),
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.normal)),
              TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
<<<<<<< HEAD
}

// ── WEEK PICKER MODAL ──────────────────────────────────────────

class _WeekPickerModal extends StatefulWidget {
  final DateTime initialWeekStart;
  final Function(DateTime) onWeekSelected;

  const _WeekPickerModal({
    required this.initialWeekStart,
    required this.onWeekSelected,
  });

  @override
  State<_WeekPickerModal> createState() => _WeekPickerModalState();
}

class _WeekPickerModalState extends State<_WeekPickerModal> {
  late int _selectedYear;
  late int _selectedWeekNumber;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialWeekStart.year;
    _selectedWeekNumber = _getWeekNumber(widget.initialWeekStart);
  }

  int _getWeekNumber(DateTime date) {
    int dayOfYear = int.parse(DateFormat("D").format(date));
    return ((dayOfYear - date.weekday) / 7).ceil() + 1;
  }

  DateTime _getMonday(int year, int weekNumber) {
    DateTime jan4 = DateTime(year, 1, 4);
    DateTime firstMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return firstMonday.add(Duration(days: (weekNumber - 1) * 7));
  }

  int _getMaxWeeks(int year) {
    DateTime dec31 = DateTime(year, 12, 31);
    return _getWeekNumber(dec31);
  }

  @override
  Widget build(BuildContext context) {
    final maxWeeks = _getMaxWeeks(_selectedYear);
    final selectedMonday = _getMonday(_selectedYear, _selectedWeekNumber);
    final selectedSunday = selectedMonday.add(const Duration(days: 6));
    final fmt = DateFormat('d.MM');
    final yearFmt = DateFormat('yyyy');

    return Container(
      height: 320,
      color: Colors.white,
      child: Column(
        children: [
          // Header: wyświetl wybrane daty
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.07),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${fmt.format(selectedMonday)} — ${fmt.format(selectedSunday)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  yearFmt.format(selectedMonday),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Scrollery: Tydzień + Rok
          Expanded(
  child: Row(
    children: [
      // Tydzień
      Expanded(
        flex: 2,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Tydzień',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  )),
            ),
            Expanded(
              child: ListView.builder(
                itemExtent: 40,
                itemCount: maxWeeks,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _selectedWeekNumber = i + 1),
                  child: Container(
                    alignment: Alignment.center,
                    color: _selectedWeekNumber == i + 1 
                        ? AppTheme.primary.withOpacity(0.1) 
                        : null,
                    child: Text('${i + 1}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: _selectedWeekNumber == i + 1 
                              ? FontWeight.w700 
                              : FontWeight.normal,
                        )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Container(width: 1, color: AppTheme.border),
      // Rok
      Expanded(
        flex: 1,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Rok',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  )),
            ),
            Expanded(
              child: ListView.builder(
                itemExtent: 40,
                itemCount: 80,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _selectedYear = 2020 + i),
                  child: Container(
                    alignment: Alignment.center,
                    color: _selectedYear == 2020 + i 
                        ? AppTheme.primary.withOpacity(0.1) 
                        : null,
                    child: Text('${2020 + i}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: _selectedYear == 2020 + i 
                              ? FontWeight.w700 
                              : FontWeight.normal,
                        )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
),
          // Buttons
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Anuluj'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final monday = _getMonday(_selectedYear, _selectedWeekNumber);
                      widget.onWeekSelected(monday);
                    },
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
=======
>>>>>>> New-picker-for-work-time
}