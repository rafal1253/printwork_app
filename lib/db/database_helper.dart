import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'PrintWork', 'printwork.db');
    await Directory(dirname(dbPath)).create(recursive: true);
    return await openDatabase(dbPath, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE day_absences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_name TEXT NOT NULL,
        date TEXT NOT NULL,
        absence_type TEXT NOT NULL DEFAULT 'none',
        note TEXT,
        UNIQUE(employee_name, date)
      )
    ''');

    await db.execute('''
      CREATE TABLE employees (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE work_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL,
        employee_name TEXT NOT NULL,
        duty_on TEXT,
        duty_off TEXT,
        duration_minutes INTEGER,
        anomaly TEXT,
        source_file TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL UNIQUE,
        client_id TEXT NOT NULL,
        client_name TEXT NOT NULL,
        client_phone TEXT,
        client_email TEXT,
        product_description TEXT NOT NULL,
        format TEXT,
        quantity INTEGER,
        deadline TEXT,
        status TEXT NOT NULL DEFAULT 'new',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (client_id) REFERENCES clients(id)
      )
    ''');
  }

  // ── WORK ENTRIES ──────────────────────────────────────────

  Future<int> insertWorkEntry(Map<String, dynamic> entry) async {
    final db = await database;
    return db.insert('work_entries', entry,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getWorkEntries({
    String? employeeName,
    String? fromDate,
    String? toDate,
  }) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (employeeName != null && employeeName.isNotEmpty) {
      where += ' AND employee_name = ?';
      args.add(employeeName);
    }
    if (fromDate != null) {
      where += ' AND duty_on >= ?';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND (duty_on <= ? OR duty_on IS NULL)';
      args.add(toDate);
    }
    return db.query('work_entries',
        where: where, whereArgs: args, orderBy: 'duty_on DESC');
  }

  Future<List<Map<String, dynamic>>> getWorkStats() async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        employee_name,
        COUNT(*) as shift_count,
        SUM(duration_minutes) as total_minutes,
        AVG(duration_minutes) as avg_minutes,
        COUNT(CASE WHEN anomaly IS NOT NULL THEN 1 END) as anomaly_count
      FROM work_entries
      WHERE duration_minutes IS NOT NULL
      GROUP BY employee_name
      ORDER BY employee_name
    ''');
  }

  Future<List<Map<String, dynamic>>> getWeeklyHours() async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        employee_name,
        strftime('%Y-%W', duty_on) as week,
        SUM(duration_minutes) / 60.0 as hours
      FROM work_entries
      WHERE duration_minutes IS NOT NULL AND duty_on IS NOT NULL
      GROUP BY employee_name, week
      ORDER BY week, employee_name
    ''');
  }

  Future<List<String>> getEmployeeNames() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT DISTINCT employee_name FROM work_entries ORDER BY employee_name');
    return result.map((r) => r['employee_name'] as String).toList();
  }

  Future<void> clearWorkEntries() async {
    final db = await database;
    await db.delete('work_entries');
  }

  // ── ORDERS ────────────────────────────────────────────────

  Future<String> insertOrder(Map<String, dynamic> order) async {
    final db = await database;
    await db.insert('orders', order);
    return order['id'] as String;
  }

  Future<int> updateOrder(Map<String, dynamic> order) async {
    final db = await database;
    return db.update('orders', order,
        where: 'id = ?', whereArgs: [order['id']]);
  }

  Future<int> deleteOrder(String id) async {
    final db = await database;
    return db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getOrders({String? status}) async {
    final db = await database;
    if (status != null && status.isNotEmpty) {
      return db.query('orders',
          where: 'status = ?', whereArgs: [status], orderBy: 'deadline ASC');
    }
    return db.query('orders', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getOrder(String id) async {
    final db = await database;
    final result =
        await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> getNextOrderNumber() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM orders');
    return (result.first['cnt'] as int) + 1;
  }

  Future<List<Map<String, dynamic>>> getOrderStats() async {
    final db = await database;
    return db.rawQuery('''
      SELECT status, COUNT(*) as count FROM orders GROUP BY status
    ''');
  }

  // ── ABSENCE OVERRIDES ─────────────────────────────────────

  Future<void> upsertAbsenceOverride({
    required String employeeName,
    required String date,
    required String absenceType,
    String? note,
  }) async {
    final db = await database;
    await db.insert(
      'day_absences',
      {
        'employee_name': employeeName,
        'date': date,
        'absence_type': absenceType,
        'note': note,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAbsenceOverrides() async {
    final db = await database;
    return db.query('day_absences');
  }

  Future<int> updateWorkEntry(Map<String, dynamic> entry) async {
    final db = await database;
    final id = entry['id'];
    if (id == null) return 0;
    return db.update('work_entries', entry,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── CLIENTS ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;
    return db.query('clients', orderBy: 'name ASC');
  }

  Future<void> upsertClient(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert('clients', client,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<String>> getExistingDayKeys() async {
    final db = await database;
    final result = await db.rawQuery("""
      SELECT DISTINCT employee_name,
        strftime('%Y-%m-%d', duty_on) as day
      FROM work_entries
      WHERE duty_on IS NOT NULL
    """);
    return result
        .map((r) => '${r['employee_name']}_${r['day']}')
        .toSet();
  }

  // ── YEAR QUERIES (Etap 1) ─────────────────────────────────

  /// Zwraca wszystkie wpisy pracy dla pracownika w danym roku.
  /// Uwzględnia wpisy gdzie duty_on jest w danym roku LUB
  /// (duty_on IS NULL i duty_off jest w danym roku) — obsługa anomalii.
  Future<List<Map<String, dynamic>>> getYearEntries({
    required String employeeName,
    required int year,
  }) async {
    final db = await database;
    final yearStr = year.toString();
    return db.rawQuery('''
      SELECT *
      FROM work_entries
      WHERE employee_name = ?
        AND (
          strftime('%Y', duty_on) = ?
          OR (duty_on IS NULL AND strftime('%Y', duty_off) = ?)
        )
      ORDER BY COALESCE(duty_on, duty_off) ASC
    ''', [employeeName, yearStr, yearStr]);
  }

  /// Zwraca wszystkie absencje (urlopy, L4, inne) dla pracownika w danym roku.
  Future<List<Map<String, dynamic>>> getYearAbsences({
    required String employeeName,
    required int year,
  }) async {
    final db = await database;
    final fromDate = '$year-01-01';
    final toDate = '$year-12-31';
    return db.query(
      'day_absences',
      where: 'employee_name = ? AND date >= ? AND date <= ?',
      whereArgs: [employeeName, fromDate, toDate],
      orderBy: 'date ASC',
    );
  }
}