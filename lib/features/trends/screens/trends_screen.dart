import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/trends/models/trend_report.dart';
import 'package:junk_food_tracker/features/trends/widgets/trend_bar_chart.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:junk_food_tracker/shared/utils/json_clipboard.dart';
import 'package:junk_food_tracker/shared/widgets/category_chip.dart';
import 'package:provider/provider.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  static final DateFormat _dayTitleFormat = DateFormat('EEE, MMM d, y');
  static final DateFormat _shortDateFormat = DateFormat('MMM d');
  static final DateFormat _monthTitleFormat = DateFormat.yMMMM();
  static final DateFormat _hourFormat = DateFormat('h a');
  static final DateFormat _shortDayFormat = DateFormat('MMM d');

  TrendRange _range = TrendRange.week;
  DateTime _anchor = DateTime.now();
  TrendReport? _report;
  List<FoodEntry> _entries = const <FoodEntry>[];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;

  TrendPeriod get _period => TrendPeriod.containing(_range, _anchor);

  bool get _canGoForward {
    final today = dateOnly(DateTime.now());
    return !_period.shift(1).start.isAfter(today);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final period = _period;
    final state = context.read<TrackerState>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await state.ensureLogsLoaded(period.start, period.end);
      final entries = [...state.entriesInRange(period.start, period.end)]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final report = TrendReport.fromEntries(
        period: period,
        entries: entries,
        isJunkCategory: state.isJunkCategory,
      );

      if (!mounted || token != _loadToken) return;
      setState(() {
        _report = report;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = 'Could not load the food logs in this vault.\n$error';
        _loading = false;
      });
    }
  }

  void _selectRange(TrendRange range) {
    if (range == _range) return;

    final today = DateTime.now();
    final anchor = _period.contains(today) ? today : _anchor;
    setState(() {
      _range = range;
      _anchor = anchor;
      _report = null;
      _entries = const <FoodEntry>[];
      _error = null;
      _loading = true;
    });
    _load();
  }

  void _shift(int steps) {
    if (steps > 0 && !_canGoForward) return;
    setState(() {
      _anchor = _period.shift(steps).start;
      _report = null;
      _entries = const <FoodEntry>[];
      _error = null;
      _loading = true;
    });
    _load();
  }

  void _copyReport() {
    final report = _report;
    if (report == null) return;

    copyJsonToClipboard(context, {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      ...report.toJson(entries: _entries),
    }, message: 'Copied $_periodTitle trends as JSON.');
  }

  String get _periodTitle {
    final period = _period;
    final today = dateOnly(DateTime.now());

    switch (_range) {
      case TrendRange.day:
        if (isSameDate(period.start, today)) {
          return 'Today · ${_shortDateFormat.format(period.start)}';
        }
        return _dayTitleFormat.format(period.start);
      case TrendRange.week:
        final start = period.start;
        final end = period.end;
        if (start.year != end.year) {
          return '${DateFormat('MMM d, y').format(start)} – '
              '${DateFormat('MMM d, y').format(end)}';
        }
        return '${_shortDateFormat.format(start)} – '
            '${DateFormat('MMM d, y').format(end)}';
      case TrendRange.month:
        return _monthTitleFormat.format(period.start);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trends & Analytics'),
        actions: [
          IconButton(
            key: const Key('export-trends-json'),
            tooltip: 'Export JSON',
            onPressed: _report == null ? null : _copyReport,
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<TrendRange>(
            key: const Key('trends-range-selector'),
            segments: const [
              ButtonSegment(
                value: TrendRange.day,
                label: Text('Day'),
                icon: Icon(Icons.today_rounded, size: 18),
              ),
              ButtonSegment(
                value: TrendRange.week,
                label: Text('Week'),
                icon: Icon(Icons.date_range_rounded, size: 18),
              ),
              ButtonSegment(
                value: TrendRange.month,
                label: Text('Month'),
                icon: Icon(Icons.calendar_month_rounded, size: 18),
              ),
            ],
            selected: {_range},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (selection) => _selectRange(selection.first),
          ),
          const SizedBox(height: 12),
          _PeriodNavigator(
            title: _periodTitle,
            canGoForward: _canGoForward,
            onPrevious: () => _shift(-1),
            onNext: () => _shift(1),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            range: _range,
            report: _report,
            loading: _loading,
            error: _error,
            onRetry: _load,
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MetricCard(
                    key: const Key('trends-metric-primary'),
                    metric: metrics[0],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    key: const Key('trends-metric-junk'),
                    metric: metrics[1],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    key: const Key('trends-metric-peak'),
                    metric: metrics[2],
                  ),
                ),
              ],
            ),
          ),
          if (_report != null) ...[
            const SizedBox(height: 20),
            _MealsCard(
              entries: _entries,
              range: _range,
              isJunkCategory: context.read<TrackerState>().isJunkCategory,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Charts are built from the JSON logs in your vault. '
            'Tap a bar to see its exact totals.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<_Metric> _metrics(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = _report;
    final primaryLabel = _range == TrendRange.day ? 'Day total' : 'Avg / day';
    final peakLabel = _range == TrendRange.day ? 'Peak hour' : 'Top day';

    if (report == null) {
      final caption = _loading ? 'Loading logs' : 'No data';
      return [
        _Metric(label: primaryLabel, value: '—', caption: caption),
        const _Metric(label: 'Junk total', value: '—'),
        _Metric(label: peakLabel, value: '—'),
      ];
    }

    final peak = _range == TrendRange.day ? report.peakBucket : report.peakDay;
    final entryLabel = report.entryCount == 1
        ? '1 entry'
        : '${report.entryCount} entries';

    final primary = _Metric(
      label: primaryLabel,
      value: formatNumber(
        _range == TrendRange.day
            ? report.totalCalories
            : report.dailyAverageCalories,
      ),
      unit: 'kcal',
      protein: formatProtein(
        _range == TrendRange.day
            ? report.totalProtein
            : report.dailyAverageProtein,
      ),
      caption: _range == TrendRange.day
          ? entryLabel
          : report.elapsedDayCount == 1
          ? 'over 1 day'
          : 'over ${report.elapsedDayCount} days',
    );

    final junk = _Metric(
      label: 'Junk total',
      value: formatNumber(report.totalJunkCalories),
      unit: 'kcal',
      protein: formatProtein(report.totalJunkProtein),
      valueColor: colors.error,
      caption: report.totalCalories == 0
          ? 'No calories logged'
          : '${report.junkPercentage}% of total',
    );

    final peakMetric = _Metric(
      label: peakLabel,
      value: peak == null ? '—' : formatNumber(peak.totalCalories),
      unit: peak == null ? '' : 'kcal',
      protein: peak == null ? null : formatProtein(peak.totalProtein),
      caption: peak == null
          ? 'No entries'
          : _range == TrendRange.day
          ? 'at ${_hourFormat.format(peak.date)}'
          : _shortDayFormat.format(peak.date),
    );

    return [primary, junk, peakMetric];
  }
}

class _MealsCard extends StatelessWidget {
  const _MealsCard({
    required this.entries,
    required this.range,
    required this.isJunkCategory,
  });

  final List<FoodEntry> entries;
  final TrendRange range;
  final bool Function(String category) isJunkCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final grouped = <DateTime, List<FoodEntry>>{};
    for (final entry in entries) {
      final day = dateOnly(entry.timestamp);
      (grouped[day] ??= <FoodEntry>[]).add(entry);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Meals',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  entries.length == 1 ? '1 entry' : '${entries.length} entries',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No meals logged in this period.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var index = 0; index < days.length; index++) ...[
                if (index > 0) const Divider(height: 24),
                if (range != TrendRange.day)
                  _MealDayHeader(
                    day: days[index],
                    entries: grouped[days[index]]!,
                  ),
                for (final entry in grouped[days[index]]!)
                  _MealTile(
                    entry: entry,
                    isJunk: isJunkCategory(entry.category),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _MealDayHeader extends StatelessWidget {
  const _MealDayHeader({required this.day, required this.entries});

  final DateTime day;
  final List<FoodEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    var calories = 0;
    var foundProtein = false;
    num protein = 0;
    for (final entry in entries) {
      calories += entry.calories;
      final value = entry.totalProtein;
      if (value != null) {
        foundProtein = true;
        protein += value;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatDayHeader(day),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatCaloriesWithProtein(calories, foundProtein ? protein : null),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.entry, required this.isJunk});

  static final DateFormat _timeFormat = DateFormat.jm();

  final FoodEntry entry;
  final bool isJunk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasQuantity =
        entry.quantity != 1 || (entry.unit?.trim().isNotEmpty ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isJunk ? colors.errorContainer : colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isJunk ? Icons.fastfood_rounded : Icons.restaurant_rounded,
              size: 18,
              color: isJunk
                  ? colors.onErrorContainer
                  : colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.foodName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatCaloriesWithProtein(
                        entry.calories,
                        entry.totalProtein,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CategoryChip(category: entry.category, isJunk: isJunk),
                    Text(
                      _timeFormat.format(entry.timestamp.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (hasQuantity)
                      Text(
                        formatEntryQuantity(entry),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (entry.items.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.items
                        .map(
                          (item) =>
                              '${item.name} '
                              '${formatQuantityWithUnit(item.quantity, item.unit)}',
                        )
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.title,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('trends-previous-period'),
            tooltip: 'Previous period',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              title,
              key: const Key('trends-period-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const Key('trends-next-period'),
            tooltip: 'Next period',
            onPressed: canGoForward ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.range,
    required this.report,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final TrendRange range;
  final TrendReport? report;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        range == TrendRange.day
                            ? 'Calories by hour'
                            : 'Calories by day',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Legend(color: colors.primary, label: 'Total'),
                    const SizedBox(height: 4),
                    _Legend(color: colors.error, label: 'Junk'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildContent(theme),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    if (loading && report == null) return 'Reading local JSON logs';
    final current = report;
    if (current == null) return 'No data';
    if (current.entryCount == 0) return 'Nothing logged in this period';
    final entries = current.entryCount == 1
        ? '1 entry'
        : '${current.entryCount} entries';
    if (range == TrendRange.day) return entries;
    final days = current.loggedDayCount == 1
        ? '1 day'
        : '${current.loggedDayCount} days';
    return '$entries across $days';
  }

  Widget _buildContent(ThemeData theme) {
    final colors = theme.colorScheme;

    if (error != null) {
      return SizedBox(
        height: 250,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 36),
            const SizedBox(height: 8),
            Text(
              'Could not load logs',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('trends-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final current = report;
    if (current == null) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (current.entryCount == 0) {
      return SizedBox(
        height: 250,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No food logged in this period',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add an entry from the dashboard and it will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return TrendBarChart(report: current);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric({
    required this.label,
    required this.value,
    this.unit = '',
    this.protein,
    this.caption = '',
    this.valueColor,
  });

  final String label;
  final String value;
  final String unit;

  /// Optional compact protein label, e.g. "30p".
  final String? protein;

  final String caption;
  final Color? valueColor;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({super.key, required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: metric.value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: metric.valueColor,
                      ),
                    ),
                    if (metric.unit.isNotEmpty)
                      TextSpan(
                        text: ' ${metric.unit}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    if (metric.protein != null)
                      TextSpan(
                        text: ' · ${metric.protein}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
