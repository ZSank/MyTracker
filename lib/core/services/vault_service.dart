import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
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
///         └── YYYY-MM-DD.json
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

  File dailyLogFile(DateTime date) =>
      File(p.join(foodLogsDirectory.path, '${dateKey(date)}.json'));

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
  /// from another device keeps all of its data.
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
    final file = dailyLogFile(date);
    if (!await file.exists()) return DailyFoodLog.empty(date);

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('A daily log must contain a JSON object.');
      }
      return DailyFoodLog.fromJson(
        Map<String, dynamic>.from(decoded),
        date: date,
      );
    } on FormatException {
      await _quarantine(file);
      return DailyFoodLog.empty(date);
    }
  }

  Future<void> writeDailyLog(DailyFoodLog log) {
    final file = dailyLogFile(log.date);
    final json = log.toJson();
    return _enqueueWrite(() => _writeJson(file, json));
  }

  /// Every day that currently has a log file, sorted oldest to newest.
  ///
  /// Useful for the Trends screen without loading any file contents.
  Future<List<DateTime>> listLoggedDates() async {
    final directory = foodLogsDirectory;
    if (!await directory.exists()) return <DateTime>[];

    final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final dates = <DateTime>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!datePattern.hasMatch(name)) continue;
      final parsed = DateTime.tryParse(name);
      if (parsed != null) dates.add(dateOnly(parsed));
    }

    dates.sort();
    return dates;
  }

  /// Loads and merges all entries between [start] and [end] (inclusive).
  Future<List<FoodEntry>> loadEntriesInRange(
    DateTime start,
    DateTime end,
  ) async {
    final first = dateOnly(start);
    final last = dateOnly(end);
    final entries = <FoodEntry>[];

    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final log = await loadDailyLog(day);
      entries.addAll(log.entries);
    }

    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
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
