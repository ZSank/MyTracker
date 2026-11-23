import 'package:material_ui/material_ui.dart';

/// Small colour-coded category label.
///
/// Junk categories use the error palette, "Healthy" uses the primary palette,
/// and every other category stays neutral.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, required this.isJunk});

  final String category;
  final bool isJunk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Color background;
    final Color foreground;
    if (isJunk) {
      background = colors.errorContainer;
      foreground = colors.onErrorContainer;
    } else if (category.toLowerCase() == 'healthy') {
      background = colors.primaryContainer;
      foreground = colors.onPrimaryContainer;
    } else {
      background = colors.secondaryContainer;
      foreground = colors.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
