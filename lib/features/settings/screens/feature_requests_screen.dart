import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:provider/provider.dart';

/// Free-form notes for features to add later.
///
/// The text is stored as `feature_requests.txt` in the user's vault folder,
/// next to `config.json`, so it stays with the rest of their local data.
/// Edits are autosaved shortly after typing stops.
class FeatureRequestsScreen extends StatefulWidget {
  const FeatureRequestsScreen({super.key});

  @override
  State<FeatureRequestsScreen> createState() => _FeatureRequestsScreenState();
}

class _FeatureRequestsScreenState extends State<FeatureRequestsScreen> {
  static const Duration _autosaveDelay = Duration(milliseconds: 700);

  final TextEditingController _controller = TextEditingController();
  Timer? _autosaveTimer;
  Completer<void>? _saveDone;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<TrackerState>();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final text = await state.loadFeatureRequests();
      if (!mounted) return;
      _controller.text = text;
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _onChanged(String _) {
    if (!_dirty) setState(() => _dirty = true);
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () {
      if (mounted) _save(showFeedback: false);
    });
  }

  Future<bool> _save({bool showFeedback = true}) async {
    final state = context.read<TrackerState>();
    while (_saving) {
      final pending = _saveDone;
      if (pending == null) break;
      await pending.future;
    }
    if (!_dirty) return true;
    _autosaveTimer?.cancel();
    final text = _controller.text;
    final completer = Completer<void>();
    _saveDone = completer;
    setState(() => _saving = true);

    try {
      await state.saveFeatureRequests(text);
      if (!mounted) return true;
      final stillCurrent = _controller.text == text;
      setState(() => _dirty = !stillCurrent);
      if (!stillCurrent) {
        _autosaveTimer = Timer(_autosaveDelay, () {
          if (mounted) _save(showFeedback: false);
        });
      }
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feature requests saved to your vault.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save feature requests.\n$error')),
      );
      return false;
    } finally {
      if (identical(_saveDone, completer)) _saveDone = null;
      completer.complete();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    _autosaveTimer?.cancel();
    if (_dirty || _saving) {
      final saved = await _save(showFeedback: false);
      if (!saved || _dirty || _saving) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Feature Requests'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _dirty ? 'Saving...' : 'Saved',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(TrackerState state) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: colors.error),
              const SizedBox(height: 10),
              Text(
                'Could not read feature requests.',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final vaultPath = state.vaultPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Write down features you want to add. Changes are autosaved to '
            'feature_requests.txt in your vault folder, not inside the app.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (vaultPath != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              vaultPath,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: const Key('feature-requests-field'),
              controller: _controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Barcode scanner, water tracking, weekly report...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _saving
                ? 'Saving to vault...'
                : _dirty
                ? 'Unsaved changes...'
                : 'All changes saved.',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
