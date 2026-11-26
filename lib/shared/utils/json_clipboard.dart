import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Encodes [value] as indented JSON and copies it to the system clipboard.
///
/// The value is serialized directly from the in-memory model, so callers can
/// pass `toJson()` maps without reading or parsing the vault files again.
Future<void> copyJsonToClipboard(
  BuildContext context,
  Object value, {
  String message = 'JSON copied to clipboard.',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final encoded = const JsonEncoder.withIndent('  ').convert(value);

  try {
    await Clipboard.setData(ClipboardData(text: encoded));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not copy JSON to the clipboard.'),
        duration: Duration(seconds: 1),
      ),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
  );
}
