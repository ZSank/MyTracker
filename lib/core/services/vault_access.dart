import 'package:path/path.dart' as p;
import 'package:saf/saf.dart';

import 'package:junk_food_tracker/core/services/saf_vault_store.dart';
import 'package:junk_food_tracker/core/services/vault_store.dart';

/// Opens the Android vault location with the permissions the OS requires.
class VaultAccess {
  VaultAccess._();

  /// Opens the Android directory picker and returns the persisted tree URI.
  static Future<String?> pickVaultDirectory() async {
    final selected = await Saf().pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    return selected?.uri;
  }

  /// Creates a [VaultStore] for [root].
  static Future<VaultStore> openStore(String root) async {
    final trimmed = root.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Vault root path must not be empty.');
    }

    if (VaultStore.isContentUri(trimmed)) {
      return SafVaultStore(trimmed);
    }

    final store = IoVaultStore(p.normalize(trimmed));
    await store.assertWritable();
    return store;
  }
}
