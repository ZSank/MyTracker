import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
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
  Future<void> _writeTail = Future<void>.value();

  bool get isInitialized => _rootPath != null;

  String? get rootPath => _rootPath;

  String get _root {
    final root = _rootPath;
    if (root == null) {
      throw StateError('The vault has not been initialized yet.');
    }
    return root;
  }

  File get configFile => File(p.join(_root, configFileName));

  File get presetsFile => File(p.join(_root, presetsFileName));

  Directory get foodLogsDirectory => Directory(p.join(_root, 'logs', 'food'));

  File monthlyLogFile(DateTime date) =>
      File(p.join(foodLogsDirectory.path, '${monthKey(date)}.json'));

  /// Opens the OS directory picker. Returns `null` when the user cancels.
  ///
  /// Android keeps using the legacy path API because the vault layer needs a
  /// real filesystem path, while `pickDirectory` returns a `content://` tree
  /// URI that `dart:io` cannot read. Other platforms use the URI API.
  static Future<String?> pickVaultDirectory() async {
    if (Platform.isAndroid) {
      // ignore: deprecated_member_use
      return FilePicker.getDirectoryPath(
        dialogTitle: 'Choose your Personal Tracker vault',
      );
    }

    final uri = await FilePicker.pickDirectory(
      dialogTitle: 'Choose your Personal Tracker vault',
    );
    return uri?.toFilePath();
  }

  /// The folder offered by the "Use Default Location" action.
  ///
  /// Android gets the app-specific external directory (visible via a file
  /// manager). Other platforms use the user's Documents directory.
  static Future<String> defaultVaultPath() async {
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    return p.join(base.path, vaultFolderName);
  }

  /// Creates the root, `logs/food/`, and any missing default files.
  ///
  /// Existing files are never overwritten, so opening a folder that was synced
  /// from another device keeps all of its data. Vaults written by older
  /// versions (one JSON file per day) are migrated to monthly files here.
  Future<void> initialize(String path) async {
    _rootPath = p.normalize(path);
    await Directory(_root).create(recursive: true);
    await foodLogsDirectory.create(recursive: true);

    if (!await configFile.exists()) {
      await writeConfig(AppConfig.defaults());
    }
    if (!await presetsFile.exists()) {
      await writePresets(const <FoodPreset>[]);
    }

    await _migrateLegacyDailyLogs();
  }

  Future<AppConfig> loadConfig() async {
    final file = configFile;
    if (!await file.exists()) {
      final defaults = AppConfig.defaults();
      await writeConfig(defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('config.json must contain a JSON object.');
      }
      return AppConfig.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      await _quarantine(file);
      final defaults = AppConfig.defaults();
      await writeConfig(defaults);
      return defaults;
    }
  }

  Future<void> writeConfig(AppConfig config) {
    final file = configFile;
    final json = config.toJson();
    return _enqueueWrite(() => _writeJson(file, json));
  }

  Future<List<FoodPreset>> loadPresets() async {
    final file = presetsFile;
    if (!await file.exists()) {
      await writePresets(const <FoodPreset>[]);
      return [];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
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
      await _quarantine(file);
      await writePresets(const <FoodPreset>[]);
      return [];
    }
  }

  Future<void> writePresets(List<FoodPreset> presets) {
    final file = presetsFile;
    final json = presets.map((preset) => preset.toJson()).toList();
    return _enqueueWrite(() => _writeJson(file, json));
  }

  Future<DailyFoodLog> loadDailyLog(DateTime date) async {
    final monthlyLog = await _readMonthlyLog(date);
    return DailyFoodLog(date: date, entries: monthlyLog.entriesForDate(date));
  }

  Future<void> writeDailyLog(DailyFoodLog log) {
    final file = monthlyLogFile(log.date);
    return _enqueueWrite(() async {
      final monthlyLog = await _readMonthlyLogFile(file, log.date);
      final updated = monthlyLog.withEntriesForDate(log.date, log.entries);
      await _writeJson(file, updated.toJson());
    });
  }

  /// Every day that currently has entries, sorted oldest to newest.
  Future<List<DateTime>> listLoggedDates() async {
    final directory = foodLogsDirectory;
    if (!await directory.exists()) return <DateTime>[];

    final dates = <DateTime>{};

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!_monthFilePattern.hasMatch(name)) continue;

      final month = DateTime.tryParse('$name-01');
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

  Future<MonthlyFoodLog> _readMonthlyLog(DateTime date) =>
      _readMonthlyLogFile(monthlyLogFile(date), date);

  Future<MonthlyFoodLog> _readMonthlyLogFile(File file, DateTime date) async {
    if (!await file.exists()) return MonthlyFoodLog.empty(date);

    try {
      final decoded = jsonDecode(await file.readAsString());
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
      await _quarantine(file);
      return MonthlyFoodLog.empty(date);
    }
  }

  /// Moves legacy `YYYY-MM-DD.json` files into their monthly file.
  ///
  /// Each legacy file is only removed after its entries have been written to
  /// the monthly document. Malformed files are quarantined like any other
  /// unreadable JSON file.
  Future<void> _migrateLegacyDailyLogs() async {
    final directory = foodLogsDirectory;
    if (!await directory.exists()) return;

    final legacyFiles = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (_legacyDayFilePattern.hasMatch(name)) legacyFiles.add(entity);
    }
    if (legacyFiles.isEmpty) return;

    final entriesByMonth = <String, List<FoodEntry>>{};
    final migratedFiles = <File>[];

    for (final file in legacyFiles) {
      final name = p.basenameWithoutExtension(file.path);
      final date = DateTime.tryParse(name);
      if (date == null) continue;

      try {
        final decoded = jsonDecode(await file.readAsString());
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
        migratedFiles.add(file);
      } on FormatException {
        await _quarantine(file);
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
        monthlyLogFile(month),
        MonthlyFoodLog(month: month, entries: byId.values.toList()).toJson(),
      );
    }

    for (final file in migratedFiles) {
      try {
        await file.delete();
      } on FileSystemException {
        // The entries are already safe in the monthly file. Leave the legacy
        // copy behind if the file cannot be removed.
      }
    }
  }

  Future<void> _writeJson(File file, Object value) async {
    await file.parent.create(recursive: true);

    final encoded = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(encoded, flush: true);
    await temporaryFile.rename(file.path);
  }

  /// Moves unreadable JSON aside instead of silently overwriting user data.
  Future<void> _quarantine(File file) async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    try {
      await file.rename('${file.path}.corrupt-$timestamp');
    } on FileSystemException {
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
