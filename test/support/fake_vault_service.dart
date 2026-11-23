import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/services/vault_service.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';

/// In-memory [VaultService] used by widget tests.
///
/// Widget tests run inside a fake-async zone where real file I/O futures never
/// complete during a `pump`. This fake resolves immediately while keeping the
/// same read/write-through behaviour as the real service.
class FakeVaultService extends VaultService {
  AppConfig config = AppConfig.defaults();
  List<FoodPreset> presets = const [];
  final Map<String, DailyFoodLog> logs = {};

  /// Simulates an unreadable vault so UI error states can be exercised.
  bool failReads = false;

  /// Simulates a failed disk flush while memory stays up to date.
  bool failWrites = false;

  String? _openedPath;

  @override
  String? get rootPath => _openedPath;

  @override
  Future<void> initialize(String path) async {
    _openedPath = path;
  }

  @override
  Future<AppConfig> loadConfig() async {
    _failIfReading();
    return config;
  }

  @override
  Future<void> writeConfig(AppConfig config) async {
    _failIfWriting();
    this.config = config;
  }

  @override
  Future<List<FoodPreset>> loadPresets() async {
    _failIfReading();
    return List.of(presets);
  }

  @override
  Future<void> writePresets(List<FoodPreset> presets) async {
    _failIfWriting();
    this.presets = List.of(presets);
  }

  @override
  Future<DailyFoodLog> loadDailyLog(DateTime date) async {
    _failIfReading();
    return logs[dateKey(date)] ?? DailyFoodLog.empty(date);
  }

  @override
  Future<void> writeDailyLog(DailyFoodLog log) async {
    _failIfWriting();
    logs[dateKey(log.date)] = log;
  }

  @override
  Future<List<DateTime>> listLoggedDates() async {
    _failIfReading();
    final dates = logs.values.map((log) => dateOnly(log.date)).toList()..sort();
    return dates;
  }

  @override
  Future<List<FoodEntry>> loadEntriesInRange(
    DateTime start,
    DateTime end,
  ) async {
    _failIfReading();
    final first = dateOnly(start);
    final last = dateOnly(end);
    final entries = <FoodEntry>[];

    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final log = logs[dateKey(day)];
      if (log != null) entries.addAll(log.entries);
    }

    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  void _failIfReading() {
    if (failReads) throw StateError('Simulated vault read failure.');
  }

  void _failIfWriting() {
    if (failWrites) throw StateError('Simulated vault write failure.');
  }
}
