import 'package:flutter/foundation.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/services/vault_service.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/features/food/models/weekly_average.dart';
import 'package:junk_food_tracker/features/workout/models/workout_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VaultStatus { initializing, needsVaultSetup, ready, error }

/// Central write-through cache for the whole app.
///
/// `config.json`, `food_presets.json`, and the recent daily logs (read from
/// the monthly food log files) are loaded into memory once. UI code reads
/// these getters only. Mutations update memory and notify immediately, then
/// flush to disk through the queued [VaultService] writes.
class TrackerState extends ChangeNotifier {
  TrackerState({VaultService? vaultService})
    : _vault = vaultService ?? VaultService();

  static const String vaultPathPreferenceKey = 'vault_path';

  /// How many days (including today) are kept ready for the recent list.
  static const int recentDays = 7;

  final VaultService _vault;
  final Map<String, DailyFoodLog> _logs = {};
  final Map<String, Future<DailyFoodLog>> _logLoads = {};
  final Map<String, List<WorkoutEntry>> _workoutsByMonth = {};
  final Set<String> _loadedWorkoutMonths = {};

  VaultStatus _status = VaultStatus.initializing;
  AppConfig _config = AppConfig.defaults();
  List<FoodPreset> _presets = const [];
  String? _vaultPath;
  String? _errorMessage;
  String? _lastWriteError;
  bool _selectionInProgress = false;
  bool _disposed = false;

  VaultStatus get status => _status;

  bool get isReady => _status == VaultStatus.ready;

  bool get needsVaultSetup => _status == VaultStatus.needsVaultSetup;

  bool get isBusy =>
      _selectionInProgress || _status == VaultStatus.initializing;

  String? get vaultPath => _vaultPath;

  String? get errorMessage => _errorMessage;

  /// Non-fatal write failure (the in-memory value is still correct; the next
  /// successful write retries the full document).
  String? get lastWriteError => _lastWriteError;

  AppConfig get config => _config;

  List<String> get foodCategories => _config.foodCategories;

  List<String> get junkFoodCategories => _config.junkFoodCategories;

  List<FoodPreset> get presets => List.unmodifiable(_presets);

  /// Pre-made foods ordered by their latest use, newest first.
  ///
  /// Foods that have not been logged yet follow in their stored order, so the
  /// add-entry sheet can still show quick picks on a fresh install. Callers
  /// that need a shorter list (for example the top five chips) can take a
  /// slice.
  List<FoodPreset> get recentPresets {
    if (_presets.isEmpty) return const <FoodPreset>[];

    final presetIdByName = <String, String>{};
    for (final preset in _presets) {
      presetIdByName.putIfAbsent(preset.name.toLowerCase(), () => preset.id);
    }

    final lastUsed = <String, DateTime>{};
    void mark(String? presetId, DateTime timestamp) {
      if (presetId == null) return;
      final current = lastUsed[presetId];
      if (current == null || timestamp.isAfter(current)) {
        lastUsed[presetId] = timestamp;
      }
    }

    for (final entry in recentEntries) {
      mark(entry.presetId, entry.timestamp);
      for (final item in entry.items) {
        mark(item.presetId, entry.timestamp);
      }
      // Entries saved before preset ids were stored still count as usage.
      mark(presetIdByName[entry.foodName.toLowerCase()], entry.timestamp);
    }

    final used = <FoodPreset>[];
    final unused = <FoodPreset>[];
    for (final preset in _presets) {
      if (lastUsed.containsKey(preset.id)) {
        used.add(preset);
      } else {
        unused.add(preset);
      }
    }
    used.sort((a, b) => lastUsed[b.id]!.compareTo(lastUsed[a.id]!));

    return List.unmodifiable([...used, ...unused]);
  }

  DailyFoodLog? get todayLog => _logs[dateKey(DateTime.now())];

  List<FoodEntry> get todayEntries => todayLog?.entries ?? const <FoodEntry>[];

  int get todayTotalCalories => todayLog?.totalCalories ?? 0;

  /// Extra workouts logged for today, newest first.
  List<WorkoutEntry> get todayWorkouts {
    final now = DateTime.now();
    final entries = _workoutsByMonth[monthKey(now)] ?? const <WorkoutEntry>[];
    return List.unmodifiable(
      entries.where((entry) => isSameDate(entry.timestamp, now)),
    );
  }

  /// Calories burned by today's extra workouts.
  int get todayBurnedCalories =>
      todayWorkouts.fold(0, (total, workout) => total + workout.caloriesBurned);

  /// Food calories minus today's extra workout calories.
  int get todayNetCalories => todayTotalCalories - todayBurnedCalories;

  int get todayJunkCalories =>
      todayLog?.junkCalories(_config.junkFoodCategories.toSet()) ?? 0;

  /// Protein logged today, or null when no entry has a protein value.
  num? get todayTotalProtein => totalProteinForDate(DateTime.now());

  /// Protein logged on [date], or null when none of its entries have one.
  num? totalProteinForDate(DateTime date) {
    var found = false;
    num total = 0;
    for (final entry in entriesForDate(date)) {
      final value = entry.totalProtein;
      if (value != null) {
        found = true;
        total += value;
      }
    }
    return found ? total : null;
  }

  /// Average intake across the logged days of the current Monday-start week.
  ///
  /// Today is included when it already has entries, so the average updates as
  /// the day is logged. Days without entries are skipped rather than counted
  /// as zero, which keeps a missed log from pulling the average down.
  WeeklyAverage get currentWeekAverage {
    final today = dateOnly(DateTime.now());
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.monday),
    );

    var totalCalories = 0;
    var foundProtein = false;
    num totalProtein = 0;
    var loggedDays = 0;

    for (
      var day = weekStart;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final entries = _logs[dateKey(day)]?.entries;
      if (entries == null || entries.isEmpty) continue;

      loggedDays++;
      for (final entry in entries) {
        totalCalories += entry.calories;
        final protein = entry.totalProtein;
        if (protein != null) {
          foundProtein = true;
          totalProtein += protein;
        }
      }
    }

    if (loggedDays == 0) {
      return const WeeklyAverage(calories: 0, protein: null, loggedDays: 0);
    }

    return WeeklyAverage(
      calories: (totalCalories / loggedDays).round(),
      protein: foundProtein ? totalProtein / loggedDays : null,
      loggedDays: loggedDays,
    );
  }

  bool isJunkCategory(String category) => _config.isJunkCategory(category);

  /// Entries from the last [recentDays] days, newest first.
  ///
  /// The days are loaded when a vault opens, so this getter stays synchronous
  /// for the dashboard's build method.
  List<FoodEntry> get recentEntries {
    final today = dateOnly(DateTime.now());
    final firstDay = DateTime(
      today.year,
      today.month,
      today.day - (recentDays - 1),
    );
    final entries = <FoodEntry>[];

    for (
      var day = firstDay;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final log = _logs[dateKey(day)];
      if (log != null) entries.addAll(log.entries);
    }

    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(entries);
  }

  /// Loads every day in [start]..[end] (inclusive) into the cache.
  ///
  /// The Trends screen calls this once per visible period, so chart builds can
  /// then read synchronously. Days already cached are not re-read.
  Future<void> ensureLogsLoaded(DateTime start, DateTime end) async {
    final first = dateOnly(start);
    final last = dateOnly(end);
    final loads = <Future<DailyFoodLog>>[];

    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      loads.add(_logForDate(day));
    }

    if (loads.isEmpty) return;
    await Future.wait(loads);
    _notify();
  }

  /// Synchronous in-memory read of every cached entry in a date range.
  ///
  /// Call [ensureLogsLoaded] first; missing days are simply skipped.
  List<FoodEntry> entriesInRange(DateTime start, DateTime end) {
    final first = dateOnly(start);
    final last = dateOnly(end);
    final entries = <FoodEntry>[];

    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final log = _logs[dateKey(day)];
      if (log != null) entries.addAll(log.entries);
    }

    return List.unmodifiable(entries);
  }

  /// Synchronous in-memory read. Call [ensureLogLoaded] first for a day that
  /// has not been opened during this session.
  List<FoodEntry> entriesForDate(DateTime date) =>
      _logs[dateKey(date)]?.entries ?? const <FoodEntry>[];

  Future<void> init() async {
    _status = VaultStatus.initializing;
    _errorMessage = null;
    _notify();

    try {
      final preferences = await SharedPreferences.getInstance();
      final savedPath = preferences.getString(vaultPathPreferenceKey)?.trim();

      if (savedPath == null || savedPath.isEmpty) {
        _status = VaultStatus.needsVaultSetup;
        _notify();
        return;
      }

      await _loadVault(savedPath, persistPath: false);
    } catch (error) {
      _status = VaultStatus.error;
      _errorMessage = 'Could not read the saved vault location.\n$error';
      _notify();
    }
  }

  Future<void> chooseVaultFolder() =>
      _selectVault(VaultService.pickVaultDirectory);

  Future<void> useDefaultVault() =>
      _selectVault(() => VaultService.defaultVaultPath());

  Future<void> setVaultPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    await _loadVault(trimmed, persistPath: true);
  }

  Future<void> _selectVault(Future<String?> Function() resolvePath) async {
    if (_selectionInProgress) return;

    _selectionInProgress = true;
    _errorMessage = null;
    _notify();

    try {
      final path = await resolvePath();
      if (path == null || path.trim().isEmpty) return;
      await setVaultPath(path);
    } catch (error) {
      _errorMessage = 'Could not select a vault folder.\n$error';
      _notify();
    } finally {
      _selectionInProgress = false;
      _notify();
    }
  }

  Future<void> _loadVault(String path, {required bool persistPath}) async {
    _status = VaultStatus.initializing;
    _errorMessage = null;
    _notify();

    try {
      await _vault.initialize(path);
      final config = await _vault.loadConfig();
      final presets = await _vault.loadPresets();
      final recentLogs = await _readRecentLogs(DateTime.now());

      _config = config;
      _presets = presets;
      _logs.clear();
      for (final log in recentLogs) {
        _logs[dateKey(log.date)] = log;
      }
      _logLoads.clear();
      _workoutsByMonth.clear();
      _loadedWorkoutMonths.clear();
      await _loadWorkoutMonth(DateTime.now());

      final openedPath = _vault.rootPath!;
      _vaultPath = openedPath;

      if (persistPath) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(vaultPathPreferenceKey, openedPath);
      }

      _status = VaultStatus.ready;
    } catch (error) {
      _status = VaultStatus.error;
      _errorMessage = 'Could not open the vault at:\n$path\n\n$error';
    }

    _notify();
  }

  Future<List<DailyFoodLog>> _readRecentLogs(DateTime now) {
    final today = dateOnly(now);
    final dates = <DateTime>[today];
    for (var offset = 1; offset < recentDays; offset++) {
      dates.add(DateTime(today.year, today.month, today.day - offset));
    }
    return Future.wait(dates.map(_vault.loadDailyLog));
  }

  Future<void> updateConfig(AppConfig next) async {
    _config = next;
    _notify();
    await _persist(() => _vault.writeConfig(next));
  }

  Future<void> setDailyCalorieGoal(int goal) async {
    if (goal <= 0 || goal == _config.dailyCalorieGoal) return;
    await updateConfig(_config.copyWith(dailyCalorieGoal: goal));
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    if (enabled == _config.dailyReminderEnabled) return;
    await updateConfig(_config.copyWith(dailyReminderEnabled: enabled));
  }

  Future<void> setDailyReminderTime(int hour, int minute) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return;
    if (hour == _config.dailyReminderHour &&
        minute == _config.dailyReminderMinute) {
      return;
    }
    await updateConfig(
      _config.copyWith(dailyReminderHour: hour, dailyReminderMinute: minute),
    );
  }

  Future<bool> addFoodCategory(String category) async {
    final value = category.trim();
    final alreadyExists = _config.foodCategories.any(
      (item) => item.toLowerCase() == value.toLowerCase(),
    );
    if (value.isEmpty || alreadyExists) return false;

    await updateConfig(
      _config.copyWith(foodCategories: [..._config.foodCategories, value]),
    );
    return true;
  }

  Future<bool> removeFoodCategory(String category) async {
    if (!_config.foodCategories.contains(category)) return false;
    // Keep at least one category so entries always have a valid selection.
    if (_config.foodCategories.length <= 1) return false;

    await updateConfig(
      _config.copyWith(
        foodCategories: _config.foodCategories
            .where((item) => item != category)
            .toList(),
        junkFoodCategories: _config.junkFoodCategories
            .where((item) => item != category)
            .toList(),
      ),
    );
    return true;
  }

  Future<void> setCategoryCountsAsJunk(
    String category,
    bool countsAsJunk,
  ) async {
    final current = _config.junkFoodCategories.toSet();
    if (countsAsJunk == current.contains(category)) return;

    if (countsAsJunk) {
      current.add(category);
    } else {
      current.remove(category);
    }

    await updateConfig(_config.copyWith(junkFoodCategories: current.toList()));
  }

  Future<void> upsertPreset(FoodPreset preset) async {
    final updated = [..._presets];
    final index = updated.indexWhere((item) => item.id == preset.id);
    if (index == -1) {
      updated.add(preset);
    } else {
      updated[index] = preset;
    }

    _presets = List.unmodifiable(updated);
    _notify();
    await _persist(() => _vault.writePresets(_presets));
  }

  Future<void> deletePreset(String id) async {
    if (!_presets.any((preset) => preset.id == id)) return;

    _presets = List.unmodifiable(_presets.where((preset) => preset.id != id));
    _notify();
    await _persist(() => _vault.writePresets(_presets));
  }

  /// Reads the feature request notes from the vault.
  Future<String> loadFeatureRequests() => _vault.loadFeatureRequests();

  /// Saves the feature request notes to the vault.
  Future<void> saveFeatureRequests(String contents) async {
    await _persist(() => _vault.writeFeatureRequests(contents));
    final error = _lastWriteError;
    if (error != null) throw StateError(error);
  }

  /// Loads a historical day into the in-memory cache. No-op when cached.
  Future<void> ensureLogLoaded(DateTime date) async {
    await _logForDate(date);
    _notify();
  }

  Future<void> addFoodEntry(FoodEntry entry) async {
    final key = dateKey(entry.timestamp);
    await _logForDate(entry.timestamp);
    final log = _logs[key];
    if (log == null) return;

    final updated = DailyFoodLog(
      date: log.date,
      entries: [
        ...log.entries.where((existing) => existing.id != entry.id),
        entry,
      ],
    );

    _logs[key] = updated;
    _notify();
    await _persist(() => _vault.writeDailyLog(updated));
  }

  Future<void> deleteFoodEntry(FoodEntry entry) async {
    final key = dateKey(entry.timestamp);
    await _logForDate(entry.timestamp);
    final log = _logs[key];
    if (log == null) return;

    final remaining = log.entries
        .where((existing) => existing.id != entry.id)
        .toList();
    if (remaining.length == log.entries.length) return;

    final updated = DailyFoodLog(date: log.date, entries: remaining);
    _logs[key] = updated;
    _notify();
    await _persist(() => _vault.writeDailyLog(updated));
  }

  /// Adds a new extra workout or replaces an existing one with the same id.
  Future<void> saveWorkoutEntry(WorkoutEntry entry) async {
    final month = monthOnly(entry.timestamp);
    final key = monthKey(month);
    await _loadWorkoutMonth(month);

    final updated = [
      ...?_workoutsByMonth[key]?.where((existing) => existing.id != entry.id),
      entry,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _workoutsByMonth[key] = List.unmodifiable(updated);
    _notify();
    await _persist(() => _vault.writeWorkoutsForMonth(month, updated));
  }

  Future<void> deleteWorkoutEntry(WorkoutEntry entry) async {
    final month = monthOnly(entry.timestamp);
    final key = monthKey(month);
    await _loadWorkoutMonth(month);

    final current = _workoutsByMonth[key] ?? const <WorkoutEntry>[];
    final remaining = current
        .where((existing) => existing.id != entry.id)
        .toList();
    if (remaining.length == current.length) return;

    _workoutsByMonth[key] = List.unmodifiable(remaining);
    _notify();
    await _persist(() => _vault.writeWorkoutsForMonth(month, remaining));
  }

  Future<List<WorkoutEntry>> _loadWorkoutMonth(DateTime date) async {
    final key = monthKey(date);
    if (_loadedWorkoutMonths.contains(key)) {
      return _workoutsByMonth[key] ?? const <WorkoutEntry>[];
    }

    try {
      final entries = await _vault.loadWorkoutsForMonth(date);
      _workoutsByMonth[key] = List.unmodifiable(entries);
    } on StateError {
      // Lightweight in-memory vault services may not expose workout storage.
      // Treat those as having no workouts instead of failing the whole vault.
      _workoutsByMonth[key] = const <WorkoutEntry>[];
    }

    _loadedWorkoutMonths.add(key);
    return _workoutsByMonth[key]!;
  }

  /// Replaces an entry, moving it to a new day's log when the time changed.
  Future<void> updateFoodEntry(
    FoodEntry updated, {
    required DateTime previousTimestamp,
  }) async {
    final previousKey = dateKey(previousTimestamp);
    final nextKey = dateKey(updated.timestamp);

    if (previousKey == nextKey) {
      await addFoodEntry(updated);
      return;
    }

    await _logForDate(previousTimestamp);
    final previousLog = _logs[previousKey];
    if (previousLog != null &&
        previousLog.entries.any((entry) => entry.id == updated.id)) {
      final remaining = previousLog.entries
          .where((entry) => entry.id != updated.id)
          .toList();
      final updatedPrevious = DailyFoodLog(
        date: previousLog.date,
        entries: remaining,
      );
      _logs[previousKey] = updatedPrevious;
      _notify();
      await _persist(() => _vault.writeDailyLog(updatedPrevious));
    }

    await addFoodEntry(updated);
  }

  void clearLastWriteError() {
    if (_lastWriteError == null) return;
    _lastWriteError = null;
    _notify();
  }

  Future<DailyFoodLog> _logForDate(DateTime date) {
    final key = dateKey(date);
    final cached = _logs[key];
    if (cached != null) return Future.value(cached);

    final pending = _logLoads[key];
    if (pending != null) return pending;

    late final Future<DailyFoodLog> future;
    future = _vault
        .loadDailyLog(date)
        .then((loaded) {
          final existing = _logs[key];
          if (existing != null) return existing;
          _logs[key] = loaded;
          return loaded;
        })
        .whenComplete(() {
          if (identical(_logLoads[key], future)) {
            _logLoads.remove(key);
          }
        });

    _logLoads[key] = future;
    return future;
  }

  Future<void> _persist(Future<void> Function() write) async {
    try {
      await write();
      if (_lastWriteError != null) {
        _lastWriteError = null;
        _notify();
      }
    } catch (error) {
      _lastWriteError = error.toString();
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
