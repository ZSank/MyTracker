import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the daily calorie summary notification.
///
/// Flutter's local notifications cannot run app code at fire time, so the
/// service schedules one notification per day for the next week and refreshes
/// them whenever the tracker state changes. The body therefore always reflects
/// the latest total known to the app.
class CalorieReminderService {
  CalorieReminderService._();

  static final CalorieReminderService instance = CalorieReminderService._();

  static const int _firstNotificationId = 7300;

  /// Rebuilds the schedule for this many days, including today.
  static const int _daysAhead = 30;

  /// Clears more ids than we schedule so older builds cannot leave extras.
  static const int _cancelCount = 60;

  static const String _channelId = 'daily_calorie_summary';
  static const String _channelName = 'Daily calorie summary';
  static const String _channelDescription =
      'Shows the calories logged for the day.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _syncing = false;
  bool _resyncRequested = false;
  String? _lastSignature;
  TrackerState? _state;

  /// Prepares the notification plugin, channel, and local timezone.
  ///
  /// Safe to call more than once. No-op on non-Android hosts so widget tests
  /// can pump the app without platform channels.
  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid) return;

    try {
      timezone_data.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));

      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_calorie'),
      );
      await _plugin.initialize(settings: initializationSettings);

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.defaultImportance,
        ),
      );

      _initialized = true;
      _handleStateChanged();
    } catch (error) {
      debugPrint('Could not initialize daily calorie reminders: $error');
    }
  }

  /// Listens to [state] so the schedule follows config and calorie changes.
  void attach(TrackerState state) {
    if (identical(_state, state)) return;
    _state?.removeListener(_handleStateChanged);
    _state = state;
    state.addListener(_handleStateChanged);
    _handleStateChanged();
  }

  /// Asks for the Android 13+ notification permission.
  ///
  /// Returns `true` when notifications can be shown or when running on a host
  /// that does not use the Android permission model.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    if (!_initialized) await initialize();
    if (!_initialized) return false;

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (error) {
      debugPrint('Could not request notification permission: $error');
      return false;
    }
  }

  /// Rewrites the scheduled notifications when the tracker values changed.
  Future<void> syncNow(TrackerState state) async {
    if (!Platform.isAndroid || !_initialized || !state.isReady) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }

    _syncing = true;
    try {
      do {
        _resyncRequested = false;
        await _syncOnce(state);
      } while (_resyncRequested);
    } finally {
      _syncing = false;
    }
  }

  void _handleStateChanged() {
    final state = _state;
    if (state == null || !state.isReady) return;
    unawaited(syncNow(state));
  }

  Future<void> _syncOnce(TrackerState state) async {
    final signature = _signatureFor(state);
    if (signature == _lastSignature) return;

    try {
      await _cancelScheduled();
      if (state.config.dailyReminderEnabled) {
        await _schedule(state);
      }
      _lastSignature = signature;
    } catch (error) {
      debugPrint('Could not update daily calorie reminders: $error');
    }
  }

  String _signatureFor(TrackerState state) {
    final config = state.config;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final signature = StringBuffer()
      ..write(config.dailyReminderEnabled)
      ..write('|')
      ..write(config.dailyReminderHour)
      ..write(':')
      ..write(config.dailyReminderMinute)
      ..write('|')
      ..write(config.dailyCalorieGoal);

    for (var offset = 0; offset < _daysAhead; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);
      signature
        ..write('|')
        ..write(dateKey(day))
        ..write(':')
        ..write(_totalForDate(state, day));
    }
    return signature.toString();
  }

  Future<void> _cancelScheduled() async {
    for (var index = 0; index < _cancelCount; index++) {
      await _plugin.cancel(id: _firstNotificationId + index);
    }
  }

  Future<void> _schedule(TrackerState state) async {
    final config = state.config;
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
      ),
    );

    for (var offset = 0; offset < _daysAhead; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);
      final scheduledDate = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        config.dailyReminderHour,
        config.dailyReminderMinute,
      );
      if (!scheduledDate.isAfter(now)) continue;

      final total = _totalForDate(state, day);
      final goal = config.dailyCalorieGoal;
      final body = goal > 0
          ? '${formatNumber(total)} of ${formatNumber(goal)} kcal logged today.'
          : '${formatNumber(total)} kcal logged today.';

      await _plugin.zonedSchedule(
        id: _firstNotificationId + offset,
        title: "Today's calories",
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: dateKey(day),
      );
    }
  }

  int _totalForDate(TrackerState state, DateTime day) {
    if (dateKey(day) == dateKey(DateTime.now())) {
      return state.todayTotalCalories;
    }
    return state
        .entriesForDate(day)
        .fold<int>(0, (total, entry) => total + entry.calories);
  }
}
