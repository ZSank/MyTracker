import 'dart:convert';
import 'dart:io';

import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/services/vault_access.dart';
import 'package:junk_food_tracker/core/services/vault_store.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/features/food/models/monthly_food_log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns every file operation for the local-first vault.
///
/// The vault layout is:
/// ```
/// PersonalTrackerVault/
/// ├── config.json
/// ├── food_presets.json
/// └── logs/
///     └── food/
///         └── YYYY-MM.json
/// ```
///
/// Callers only touch memory during normal navigation. Reads happen through
/// this service on startup (or when a historical day is first needed) and
/// writes are queued so rapid edits cannot interleave partial JSON.
class VaultService {
  VaultService({String? rootPath})
    : _rootPath = rootPath == null ? null : p.normalize(rootPath);

  static const String vaultFolderName = 'PersonalTrackerVault';
  static const String configFileName = 'config.json';
  static const String presetsFileName = 'food_presets.json';

  static final RegExp _legacyDayFilePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _monthFilePattern = RegExp(r'^\d{4}-\d{2}$');

  String? _rootPath;
  VaultStore? _store;
  Future<void> _writeTail = Future<void>.value();

  bool get isInitialized => _rootPath != null && _store != null;

  String? get rootPath => _rootPath;

  VaultStore get _vaultStore {
    final store = _store;
    if (store == null) {
      throw StateError('The vault has not been initialized yet.');
    }
    return store;
  }

  String get _root {
    final root = _rootPath;
    if (root == null) {
      throw StateError('The vault has not been initialized yet.');
    }
    return root;
  }

  bool get _isFilesystemRoot => !VaultStore.isContentUri(_root);

  /// Local file handle for tests and filesystem-backed vaults.
  File get configFile {
    _ensureFilesystemRoot();
    return File(p.join(_root, configFileName));
  }

  File get presetsFile {
    _ensureFilesystemRoot();
    return File(p.join(_root, presetsFileName));
  }

  Directory get foodLogsDirectory {
    _ensureFilesystemRoot();
    return Directory(p.join(_root, 'logs', 'food'));
  }

  File monthlyLogFile(DateTime date) {
    _ensureFilesystemRoot();
    return File(p.join(foodLogsDirectory.path, '${monthKey(date)}.json'));
  }

  void _ensureFilesystemRoot() {
    if (!_isFilesystemRoot) {
      throw StateError(
        'File handles are unavailable for content URI vaults.',
      );
    }
  }

  /// Opens the OS directory picker. Returns `null` when the user cancels.
  static Future<String?> pickVaultDirectory() =>
      VaultAccess.pickVaultDirectory();

  /// The folder offered by the "Use Default Location" action.
  ///
  /// Uses the app-specific external directory (visible via a file manager)
  /// and falls back to the app documents directory if it is unavailable.
  static Future<String> defaultVaultPath() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return p.join(base.path, vaultFolderName);
  }

  /// Creates the root, `logs/food/`, and any missing default files.
  ///
  /// Existing files are never overwritten, so opening a folder that was synced
  /// from another device keeps all of its data. Vaults written by older
  /// versions (one JSON file per day) are migrated to monthly files here.
  Future<void> initialize(String path) async {
    final store = await VaultAccess.openStore(path);
    _store = store;
    _rootPath = store.displayRoot;

    await store.ensureDirectory(const []);
    await store.ensureDirectory(const ['logs', 'food']);

    if (!await store.fileExists(const [configFileName])) {
      await writeConfig(AppConfig.defaults());
    }
    if (!await store.fileExists(const [presetsFileName])) {
      await writePresets(const <FoodPreset>[]);
    }

    await _migrateLegacyDailyLogs();
  }

  Future<AppConfig> loadConfig() async {
    final raw = await _vaultStore.readText(const [configFileName]);
    if (raw == null) {
      final defaults = AppConfig.defaults();
      await writeConfig(defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('config.json must contain a JSON object.');
      }
      return AppConfig.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      await _quarantine(const [configFileName]);
      final defaults = AppConfig.defaults();
      await writeConfig(defaults);
      return defaults;
    }
  }

  Future<void> writeConfig(AppConfig config) {
    final json = config.toJson();
    return _enqueueWrite(
      () => _writeJson(const [configFileName], json),
    );
  }

  Future<List<FoodPreset>> loadPresets() async {
    final raw = await _vaultStore.readText(const [presetsFileName]);
    if (raw == null) {
      await writePresets(const <FoodPreset>[]);
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException(
          'food_presets.json must contain a JSON array.',
        );
      }

      final presets = <FoodPreset>[];
      for (final rawPreset in decoded) {
        if (rawPreset is! Map) continue;
        try {
          presets.add(
            FoodPreset.fromJson(Map<String, dynamic>.from(rawPreset)),
          );
        } on FormatException {
          // Keep the rest of the file usable if a single preset is bad.
        }
      }
      return presets;
    } on FormatException {
      await _quarantine(const [presetsFileName]);
      await writePresets(const <FoodPreset>[]);
      return [];
    }
  }

  Future<void> writePresets(List<FoodPreset> presets) {
    final json = presets.map((preset) => preset.toJson()).toList();
    return _enqueueWrite(
      () => _writeJson(const [presetsFileName], json),
    );
  }

  Future<DailyFoodLog> loadDailyLog(DateTime date) async {
    final monthlyLog = await _readMonthlyLog(date);
    return DailyFoodLog(date: date, entries: monthlyLog.entriesForDate(date));
  }

  Future<void> writeDailyLog(DailyFoodLog log) {
    return _enqueueWrite(() async {
      final monthlyLog = await _readMonthlyLog(log.date);
      final updated = monthlyLog.withEntriesForDate(log.date, log.entries);
      await _writeJson(
        ['logs', 'food', '${monthKey(log.date)}.json'],
        updated.toJson(),
      );
    });
  }

  /// Every day that currently has entries, sorted oldest to newest.
  Future<List<DateTime>> listLoggedDates() async {
    final names = await _vaultStore.listFileNames(const ['logs', 'food']);
    final dates = <DateTime>{};

    for (final name in names) {
      final monthName = p.basenameWithoutExtension(name);
      if (!_monthFilePattern.hasMatch(monthName)) continue;

      final month = DateTime.tryParse('$monthName-01');
      if (month == null) continue;

      final monthlyLog = await _readMonthlyLog(month);
      for (final entry in monthlyLog.entries) {
        dates.add(dateOnly(entry.timestamp));
      }
    }

    final sorted = dates.toList()..sort();
    return sorted;
  }

  /// Loads and merges all entries between [start] and [end] (inclusive).
  Future<List<FoodEntry>> loadEntriesInRange(
    DateTime start,
    DateTime end,
  ) async {
    final first = dateOnly(start);
    final last = dateOnly(end);
    if (last.isBefore(first)) return <FoodEntry>[];

    final entries = <FoodEntry>[];
    var month = monthOnly(first);
    final lastMonth = monthOnly(last);

    while (!month.isAfter(lastMonth)) {
      final monthlyLog = await _readMonthlyLog(month);
      for (final entry in monthlyLog.entries) {
        final day = dateOnly(entry.timestamp);
        if (!day.isBefore(first) && !day.isAfter(last)) {
          entries.add(entry);
        }
      }
      month = DateTime(month.year, month.month + 1);
    }

    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<MonthlyFoodLog> _readMonthlyLog(DateTime date) async {
    final segments = ['logs', 'food', '${monthKey(date)}.json'];
    final raw = await _vaultStore.readText(segments);
    if (raw == null) return MonthlyFoodLog.empty(date);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException(
          'A monthly food log must contain a JSON object.',
        );
      }
      return MonthlyFoodLog.fromJson(
        Map<String, dynamic>.from(decoded),
        month: date,
      );
    } on FormatException {
      await _quarantine(segments);
      return MonthlyFoodLog.empty(date);
    }
  }

  /// Moves legacy `YYYY-MM-DD.json` files into their monthly file.
  ///
  /// Each legacy file is only removed after its entries have been written to
  /// the monthly document. Malformed files are quarantined like any other
  /// unreadable JSON file.
  Future<void> _migrateLegacyDailyLogs() async {
    final names = await _vaultStore.listFileNames(const ['logs', 'food']);
    final legacyNames = names.where((name) {
      final base = p.basenameWithoutExtension(name);
      return _legacyDayFilePattern.hasMatch(base) && name.endsWith('.json');
    }).toList();
    if (legacyNames.isEmpty) return;

    final entriesByMonth = <String, List<FoodEntry>>{};
    final migrated = <List<String>>[];

    for (final name in legacyNames) {
      final base = p.basenameWithoutExtension(name);
      final date = DateTime.tryParse(base);
      if (date == null) continue;

      final segments = ['logs', 'food', name];
      final raw = await _vaultStore.readText(segments);
      if (raw == null) continue;

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException(
            'A daily food log must contain a JSON object.',
          );
        }
        final log = DailyFoodLog.fromJson(
          Map<String, dynamic>.from(decoded),
          date: date,
        );
        entriesByMonth
            .putIfAbsent(monthKey(date), () => <FoodEntry>[])
            .addAll(log.entries);
        migrated.add(segments);
      } on FormatException {
        await _quarantine(segments);
      }
    }

    for (final group in entriesByMonth.entries) {
      final month = DateTime.tryParse('${group.key}-01');
      if (month == null) continue;

      final existing = await _readMonthlyLog(month);
      final byId = <String, FoodEntry>{
        for (final entry in existing.entries) entry.id: entry,
      };
      for (final entry in group.value) {
        byId[entry.id] = entry;
      }

      await _writeJson(
        ['logs', 'food', '${monthKey(month)}.json'],
        MonthlyFoodLog(month: month, entries: byId.values.toList()).toJson(),
      );
    }

    for (final segments in migrated) {
      try {
        await _vaultStore.deleteFile(segments);
      } catch (_) {
        // The entries are already safe in the monthly file. Leave the legacy
        // copy behind if the file cannot be removed.
      }
    }
  }

  Future<void> _writeJson(List<String> segments, Object value) async {
    final encoded = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
    await _vaultStore.writeTextAtomic(segments, encoded);
  }

  /// Moves unreadable JSON aside instead of silently overwriting user data.
  Future<void> _quarantine(List<String> segments) async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final fileName = '${segments.last}.corrupt-$timestamp';
    final target = [...segments.sublist(0, segments.length - 1), fileName];
    try {
      await _vaultStore.renameFile(segments, target);
    } catch (_) {
      return;
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
