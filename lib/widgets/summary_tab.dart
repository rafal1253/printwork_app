// lib/widgets/summary_tab.dart

import 'package:flutter/material.dart';
import '../models/summary_data.dart';
import '../services/summary_service.dart';
import '../utils/theme.dart';
import 'summary_widgets.dart';

class SummaryTab extends StatefulWidget {
  /// Lista pracowników pobrana z bazy przez AttendanceScreen.
  final List<String> employees;

  const SummaryTab({super.key, required this.employees});

  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  late String? _selectedEmployee;
  late int _selectedYear;

  EmployeeSummary? _summary;
  bool _loading = false;
  String? _error;

  // Domyślnie aktywna karta: urlop
  SummaryDayType? _activeFilter = SummaryDayType.vacation;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _selectedEmployee =
        widget.employees.isNotEmpty ? widget.employees.first : null;
    _load();
  }

  @override
  void didUpdateWidget(SummaryTab old) {
    super.didUpdateWidget(old);
    // Jeśli lista pracowników się zmieniła (np. po imporcie)
    if (widget.employees != old.employees) {
      if (_selectedEmployee == null && widget.employees.isNotEmpty) {
        _selectedEmployee = widget.employees.first;
        _load();
      }
    }
  }

  Future<void> _load() async {
    if (_selectedEmployee == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await SummaryService.buildYearSummary(
        employeeName: _selectedEmployee!,
        year: _selectedYear,
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<int> get _availableYears {
    final now = DateTime.now().year;
    return [now, now - 1, now - 2, now - 3];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.employees.isEmpty) {
      return const Center(
        child: Text(
          'Brak pracowników — zaimportuj dane z rejestratora.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        _buildTopBar(),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : _summary == null
                      ? const SizedBox.shrink()
                      : _buildContent(),
        ),
      ],
    );
  }

  // ── TOP BAR: selektor pracownika + rok ────────────────────

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Selektor pracownika (chips)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.employees.map((name) {
                  final isSelected = name == _selectedEmployee;
                  return GestureDetector(
                    onTap: () {
                      if (_selectedEmployee == name) return;
                      setState(() => _selectedEmployee = name);
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isSelected
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
          const SizedBox(width: 12),

          // Selektor roku
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                isDense: true,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                items: _availableYears
                    .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text('$y'),
                        ))
                    .toList(),
                onChanged: (y) {
                  if (y == null || y == _selectedYear) return;
                  setState(() => _selectedYear = y);
                  _load();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GŁÓWNA ZAWARTOŚĆ ──────────────────────────────────────

  Widget _buildContent() {
    final summary = _summary!;
    final filteredDays = _activeFilter != null
        ? summary.filtered(_activeFilter!)
        : <SummaryDay>[];

    return CustomScrollView(
      slivers: [
        // Karty KPI
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: SummaryKpiRow(
              summary: summary,
              activeFilter: _activeFilter,
              onFilterChanged: (type) => setState(() => _activeFilter = type),
            ),
          ),
        ),

        // Nagłówek listy
        if (_activeFilter != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(_activeFilter!.icon,
                      size: 15, color: _activeFilter!.color),
                  const SizedBox(width: 6),
                  Text(
                    _activeFilter!.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _activeFilter!.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${filteredDays.length})',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),

        // Lista dni lub pusty stan
        if (_activeFilter != null)
          filteredDays.isEmpty
              ? SliverToBoxAdapter(
                  child: SummaryEmptyList(type: _activeFilter!))
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          SummaryDayTile(day: filteredDays[index]),
                      childCount: filteredDays.length,
                    ),
                  ),
                ),

        // Komunikat gdy brak aktywnego filtra
        if (_activeFilter == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Wybierz kartę, aby zobaczyć listę dni.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 36, color: AppTheme.danger),
            const SizedBox(height: 8),
            Text(
              'Błąd ładowania danych:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Spróbuj ponownie')),
          ],
        ),
      ),
    );
  }
}
