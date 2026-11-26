import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:provider/provider.dart';

/// Free-form notes for features to add later.
///
/// The text is stored in one file, `feature_requests.txt`, in the user's vault
/// folder next to `config.json`. Opening this page reads that file; going back
/// overwrites the same file with any edits.
class FeatureRequestsScreen extends StatefulWidget {
  const FeatureRequestsScreen({super.key});

  @override
  State<FeatureRequestsScreen> createState() => _FeatureRequestsScreenState();
}

class _FeatureRequestsScreenState extends State<FeatureRequestsScreen> {
  final TextEditingController _controller = TextEditingController();
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

  Future<bool> _save() async {
    if (_saving) return false;

    final state = context.read<TrackerState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    try {
      await state.saveFeatureRequests(_controller.text);
      if (!mounted) return true;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save feature requests.\n$error')),
      );
      return false;
    }
  }

  Future<void> _handleBack() async {
    if (_saving) return;

    if (_dirty) {
      final saved = await _save();
      if (!saved) return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Feature Requests')),
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
            'Write down features you want to add. Your edits are saved to the '
            'same feature_requests.txt file in your vault when you go back.',
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
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
              decoration: const InputDecoration(
                hintText:
                    'e.g. Barcode scanner, water tracking, weekly report...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
