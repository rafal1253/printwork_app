import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../models/work_entry.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';

class TimeTrackingScreen extends StatefulWidget {
  const TimeTrackingScreen({super.key});
  @override
  State<TimeTrackingScreen> createState() => _TimeTrackingScreenState();
}

class _TimeTrackingScreenState extends State<TimeTrackingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<WorkEntry> _entries = [];
  List<Map<String, dynamic>> _stats = [];
  bool _loading = false;
  String? _lastFile;
  String _filterEmp = '';
  String _filterFrom = '';
  String _filterTo = '';
  List<String> _empNames = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance
        .getWorkEntries(
          employeeName: _filterEmp.isEmpty ? null : _filterEmp,
          fromDate: _filterFrom.isEmpty ? null : _filterFrom,
          toDate: _filterTo.isEmpty ? null : _filterTo,
        );
    final stats = await DatabaseHelper.instance.getWorkStats();
    final names = await DatabaseHelper.instance.getEmployeeNames();
    setState(() {
      _entries = entries.map(WorkEntry.fromMap).toList();
      _stats = stats;
      _empNames = names;
      _loading = false;
    });
  }

  Future<void> _importFile() async {
  debugPrint('### IMPORT START ###');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'tsv'],
      dialogTitle: 'Wybierz plik z rejestratora czasu',
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final fileName = result.files.single.name;

    setState(() => _loading = true);
    try {
      debugPrint('=== PIERWSZE 200 ZNAKÓW ===');
debugPrint(content.substring(0, 200.clamp(0, content.length)));
debugPrint('=== LINIE (pierwsze 5) ===');
content.split('\n').take(5).forEach(print);

final parsed = TimeRegistryParser.parse(content, fileName);
      int added = 0;
      for (final e in parsed) {
        await DatabaseHelper.instance.insertWorkEntry(e.toMap());
        added++;
      }
      await _loadData();
      if (mounted) {
        setState(() => _lastFile = fileName);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Zaimportowano $added wpisów z "$fileName"'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Błąd importu: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _clearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Wyczyść dane'),
        content: const Text(
            'Usunięcie wszystkich wpisów czasu pracy. Kontynuować?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wyczyść',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.clearWorkEntries();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Czas pracy'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Pulpit'),
            Tab(text: 'Rejestr'),
            Tab(text: 'Anomalie'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Importuj plik',
            onPressed: _importFile,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Wyczyść dane',
            onPressed: _clearData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildDashboard(),
                _buildRecords(),
                _buildAnomalies(),
              ],
            ),
    );
  }

  Widget _buildDashboard() {
    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.upload_file_outlined,
        title: 'Brak danych',
        subtitle:
            'Zaimportuj plik TXT/CSV z rejestratora klikając ikonę importu powyżej',
        action: ElevatedButton.icon(
          onPressed: _importFile,
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Importuj plik'),
        ),
      );
    }

    final valid = _entries.where((e) => e.durationMinutes != null).toList();
    final totalH = valid.fold<int>(0, (s, e) => s + e.durationMinutes!) ~/ 60;
    final avgM = valid.isEmpty
        ? 0
        : valid.fold<int>(0, (s, e) => s + e.durationMinutes!) ~/ valid.length;
    final anomCount = _entries.where((e) => e.hasAnomaly).length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_lastFile != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 15, color: AppTheme.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Ostatni import: $_lastFile',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.info)),
                ),
              ]),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.8,
            children: [
              MetricCard(
                  label: 'Łączne godziny',
                  value: '${totalH}h',
                  sub: '${valid.length} zmian',
                  icon: Icons.schedule_outlined),
              MetricCard(
                  label: 'Śr. długość zmiany',
                  value: '${avgM ~/ 60}h ${avgM % 60}m',
                  icon: Icons.timer_outlined),
              MetricCard(
                  label: 'Pracownicy',
                  value: '${_empNames.length}',
                  icon: Icons.people_outline),
              MetricCard(
                  label: 'Anomalie',
                  value: '$anomCount',
                  valueColor:
                      anomCount > 0 ? AppTheme.danger : AppTheme.success,
                  icon: Icons.warning_amber_outlined),
            ],
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Statystyki pracowników'),
          const SizedBox(height: 10),
          ..._stats.map((s) => _EmployeeStatRow(stat: s)),
        ],
      ),
    );
  }

  Widget _buildRecords() {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: _entries.isEmpty
              ? const EmptyState(
                  icon: Icons.list_alt_outlined,
                  title: 'Brak wpisów',
                  subtitle: 'Zastosuj inne filtry lub zaimportuj dane')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _EntryRow(entry: _entries[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilters() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filterEmp.isEmpty ? null : _filterEmp,
                decoration: const InputDecoration(
                    labelText: 'Pracownik', isDense: true),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Wszyscy')),
                  ..._empNames.map((n) =>
                      DropdownMenuItem(value: n, child: Text(n))),
                ],
                onChanged: (v) {
                  _filterEmp = v ?? '';
                  _loadData();
                },
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              icon: const Icon(Icons.filter_list_off, size: 16),
              label: const Text('Wyczyść'),
              onPressed: () {
                setState(() {
                  _filterEmp = '';
                  _filterFrom = '';
                  _filterTo = '';
                });
                _loadData();
              },
            ),
          ],
        ),
      );

  Widget _buildAnomalies() {
    final anomalies = _entries.where((e) => e.hasAnomaly).toList();
    if (anomalies.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Brak anomalii',
        subtitle: 'Wszystkie zmiany wyglądają prawidłowo',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: anomalies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _EntryRow(entry: anomalies[i]),
    );
  }
}

class _EmployeeStatRow extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _EmployeeStatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final name = stat['employee_name'] as String;
    final shifts = stat['shift_count'] as int;
    final totalM = (stat['total_minutes'] as num?)?.toInt() ?? 0;
    final avgM = (stat['avg_minutes'] as num?)?.toInt() ?? 0;
    final anomalies = stat['anomaly_count'] as int;
    final totalH = totalM ~/ 60;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(name[0],
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text('$shifts zmian · ${totalH}h łącznie · śr. ${avgM ~/ 60}h ${avgM % 60}m',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          if (anomalies > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('$anomalies anomalii',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final WorkEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    final fmtT = DateFormat('HH:mm');
    final date = entry.dutyOn ?? entry.dutyOff;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.hasAnomaly
              ? AppTheme.danger.withOpacity(0.4)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date != null ? fmt.format(date) : '—',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                Text(entry.employeeName,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                _time(Icons.login, entry.dutyOn != null
                    ? fmtT.format(entry.dutyOn!)
                    : '—'),
                const Icon(Icons.arrow_forward,
                    size: 12, color: AppTheme.textHint),
                _time(Icons.logout, entry.dutyOff != null
                    ? fmtT.format(entry.dutyOff!)
                    : '—'),
                const SizedBox(width: 8),
                Text(entry.durationFormatted,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnomalyBadge(anomaly: entry.anomaly),
        ],
      ),
    );
  }

  Widget _time(IconData icon, String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.textSecondary),
            const SizedBox(width: 3),
            Text(t,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      );
}
