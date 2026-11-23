import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart' as p;
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:junk_food_tracker/core/services/saf_vault_store.dart';
import 'package:junk_food_tracker/core/services/vault_store.dart';

/// Opens a user-chosen vault location with the permissions each OS requires.
class VaultAccess {
  VaultAccess._();

  static const String bookmarkPreferenceKey = 'vault_bookmark';
  static const String _macBookmarkAccessId = 'stride_tracker_vault';

  /// Opens the OS directory picker and returns a root the vault layer can use.
  ///
  /// Android returns a persisted `content://` tree URI. Other platforms return
  /// a filesystem path; macOS also stores a security-scoped bookmark so the
  /// sandbox grant survives relaunches.
  static Future<String?> pickVaultDirectory() async {
    if (Platform.isAndroid) {
      final selected = await Saf().pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      return selected?.uri;
    }

    final uri = await FilePicker.pickDirectory(
      dialogTitle: 'Choose your StrideTracker vault',
    );
    final path = uri?.toFilePath();
    if (path == null || path.trim().isEmpty) return null;

    final normalized = p.normalize(path);
    if (Platform.isMacOS) {
      await persistMacosBookmark(normalized);
    }
    return normalized;
  }

  /// Creates a [VaultStore] for [root], restoring macOS sandbox access when
  /// a bookmark was saved for that path.
  static Future<VaultStore> openStore(String root) async {
    final trimmed = root.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Vault root path must not be empty.');
    }

    if (VaultStore.isContentUri(trimmed)) {
      if (!Platform.isAndroid) {
        throw StateError(
          'Content URI vaults are only supported on Android:\n$trimmed',
        );
      }
      return SafVaultStore(trimmed);
    }

    var resolvedPath = p.normalize(trimmed);
    if (Platform.isMacOS) {
      // Prefer the bookmark-resolved path when a grant was saved for a
      // user-picked folder; otherwise keep the stored filesystem path.
      resolvedPath = await restoreMacosAccess(resolvedPath);
    }

    final store = IoVaultStore(resolvedPath);
    await store.assertWritable();
    return store;
  }

  static Future<void> persistMacosBookmark(String path) async {
    if (!Platform.isMacOS) return;

    final bookmarks = SecureBookmarks();
    final mint = await bookmarks.mint(Directory(path));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      bookmarkPreferenceKey,
      base64Encode(mint.bookmark),
    );
    // Keep the grant active for the rest of this process.
    await bookmarks.resolve(
      id: _macBookmarkAccessId,
      bookmarkBytes: mint.bookmark,
    );
  }

  static Future<String> restoreMacosAccess(String fallbackPath) async {
    if (!Platform.isMacOS) return fallbackPath;

    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(bookmarkPreferenceKey);
    if (encoded == null || encoded.isEmpty) {
      // Fresh default-location vaults live inside the app container and do not
      // need a bookmark. User-picked folders should be re-selected once.
      return fallbackPath;
    }

    final bookmarks = SecureBookmarks();
    try {
      final resolution = await bookmarks.resolve(
        id: _macBookmarkAccessId,
        bookmarkBytes: base64Decode(encoded),
      );
      if (resolution.stale && resolution.refreshedBookmark != null) {
        await preferences.setString(
          bookmarkPreferenceKey,
          base64Encode(resolution.refreshedBookmark!),
        );
      }
      return p.normalize(resolution.path);
    } on UnresolvableBookmark {
      await preferences.remove(bookmarkPreferenceKey);
      rethrow;
    }
  }

  static Future<void> clearPersistedAccess() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(bookmarkPreferenceKey);
    if (Platform.isMacOS) {
      try {
        await SecureBookmarks().release(_macBookmarkAccessId);
      } catch (_) {
        // No active scope is fine.
      }
    }
  }
}
