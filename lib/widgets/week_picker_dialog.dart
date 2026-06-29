import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/theme.dart';

/// Zwraca listę wszystkich poniedziałków (początków tygodni) dla danego roku.
List<DateTime> weeksInYear(int year) {
  final weeks = <DateTime>[];
  // Znajdź pierwszy poniedziałek roku (lub ostatni z poprzedniego)
  var day = DateTime(year, 1, 1);
  // Cofnij do poniedziałku
  day = day.subtract(Duration(days: day.weekday - 1));
  // Jeśli ten poniedziałek jest z poprzedniego roku, idź do przodu tydzień
  while (day.year < year) {
    day = day.add(const Duration(days: 7));
  }
  // Zbierz wszystkie poniedziałki, których tydzień zaczyna się w danym roku
  while (day.year == year) {
    weeks.add(day);
    day = day.add(const Duration(days: 7));
  }
  return weeks;
}

/// Numer tygodnia ISO 8601
int isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime(thursday.year, 1, 1)
      .add(Duration(days: (4 - DateTime(thursday.year, 1, 1).weekday + 7) % 7));
  return ((thursday.difference(firstThursday).inDays) ~/ 7) + 1;
}

/// Dialog pozwalający wybrać rok i tydzień.
class WeekPickerDialog extends StatefulWidget {
  /// Aktualnie wybrany poniedziałek tygodnia.
  final DateTime currentWeekStart;

  const WeekPickerDialog({super.key, required this.currentWeekStart});

  @override
  State<WeekPickerDialog> createState() => _WeekPickerDialogState();
}

class _WeekPickerDialogState extends State<WeekPickerDialog> {
  static const int _minYear = 2024;

  late int _selectedYear;
  late DateTime _selectedWeekStart;
  late List<DateTime> _weeks;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _selectedYear = widget.currentWeekStart.year;
    _weeks = weeksInYear(_selectedYear);
    _selectedWeekStart = _normalizeToMonday(widget.currentWeekStart);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DateTime _normalizeToMonday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  int get _currentYear => DateTime.now().year;
  DateTime get _currentMonday => _normalizeToMonday(DateTime.now());

  void _changeYear(int year) {
    setState(() {
      _selectedYear = year;
      _weeks = weeksInYear(year);
      // Spróbuj utrzymać podobny tydzień w nowym roku
      final targetWeek = isoWeekNumber(_selectedWeekStart);
      _selectedWeekStart = _weeks.firstWhere(
        (w) => isoWeekNumber(w) == targetWeek,
        orElse: () => _weeks.last,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _scrollToSelected() {
    final idx = _weeks.indexWhere((w) =>
        w.year == _selectedWeekStart.year &&
        w.month == _selectedWeekStart.month &&
        w.day == _selectedWeekStart.day);
    if (idx < 0 || !_scrollController.hasClients) return;
    const itemH = 52.0;
    final offset = (idx * itemH) - 100;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedYear = _currentMonday.year;
      _weeks = weeksInYear(_selectedYear);
      _selectedWeekStart = _currentMonday;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  bool _isCurrentWeek(DateTime monday) {
    final cur = _currentMonday;
    return monday.year == cur.year &&
        monday.month == cur.month &&
        monday.day == cur.day;
  }

  bool _isSelectedWeek(DateTime monday) =>
      monday.year == _selectedWeekStart.year &&
      monday.month == _selectedWeekStart.month &&
      monday.day == _selectedWeekStart.day;

  @override
  Widget build(BuildContext context) {
    final dayFmt = DateFormat('d MMM', 'pl_PL');
    final years = List.generate(_currentYear - _minYear + 1, (i) => _minYear + i);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Wybierz tydzień',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  // Przycisk "Dziś"
                  TextButton.icon(
                    onPressed: _goToCurrentWeek,
                    icon: const Icon(Icons.today, size: 14, color: Colors.white70),
                    label: const Text('Dziś',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),

            // ── Year selector ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppTheme.primary.withOpacity(0.06),
              child: Row(
                children: [
                  const Text('Rok:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: years.map((y) {
                          final isSel = y == _selectedYear;
                          return GestureDetector(
                            onTap: () => _changeYear(y),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? AppTheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSel
                                      ? AppTheme.primary
                                      : AppTheme.border,
                                ),
                              ),
                              child: Text(
                                '$y',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSel
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Week list ──
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _weeks.length,
                itemExtent: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemBuilder: (context, i) {
                  final monday = _weeks[i];
                  final sunday = monday.add(const Duration(days: 6));
                  final weekNum = isoWeekNumber(monday);
                  final isSel = _isSelectedWeek(monday);
                  final isCur = _isCurrentWeek(monday);

                  return InkWell(
                    onTap: () => setState(() => _selectedWeekStart = monday),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppTheme.primary
                            : isCur
                                ? AppTheme.primary.withOpacity(0.07)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isCur && !isSel
                            ? Border.all(
                                color: AppTheme.primary.withOpacity(0.35),
                                width: 1.5)
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          // Numer tygodnia
                          Container(
                            width: 36,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.white.withOpacity(0.2)
                                  : AppTheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'W$weekNum',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Daty
                          Expanded(
                            child: Text(
                              '${dayFmt.format(monday)} — ${dayFmt.format(sunday)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSel
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSel
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          // Badge "bieżący"
                          if (isCur)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.white.withOpacity(0.25)
                                    : AppTheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'bieżący',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isSel
                                      ? Colors.white
                                      : AppTheme.primary,
                                ),
                              ),
                            ),
                          if (isSel)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.check_circle,
                                  size: 16, color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Actions ──
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // Wybrana data (preview)
                  Expanded(
                    child: Text(
                      _buildPreviewLabel(),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Anuluj'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selectedWeekStart),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Zatwierdź',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildPreviewLabel() {
    final fmt = DateFormat('d MMM yyyy', 'pl_PL');
    final sunday = _selectedWeekStart.add(const Duration(days: 6));
    final w = isoWeekNumber(_selectedWeekStart);
    return 'Tydzień $w: ${fmt.format(_selectedWeekStart)} – ${fmt.format(sunday)}';
  }
}
