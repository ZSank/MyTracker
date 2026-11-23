import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Relative-path filesystem used by [VaultService].
///
/// Android user-picked folders arrive as `content://` tree URIs that `dart:io`
/// cannot open. Those vaults use a SAF-backed store; everything else uses the
/// local filesystem.
abstract class VaultStore {
  String get displayRoot;

  Future<void> ensureDirectory(List<String> segments);

  Future<bool> fileExists(List<String> segments);

  Future<String?> readText(List<String> segments);

  Future<void> writeTextAtomic(List<String> segments, String contents);

  Future<void> renameFile(List<String> from, List<String> to);

  Future<void> deleteFile(List<String> segments);

  /// Basenames of files (not directories) directly under [segments].
  Future<List<String>> listFileNames(List<String> segments);

  static bool isContentUri(String root) =>
      root.startsWith('content:') || root.startsWith('content://');
}

/// Standard `dart:io` vault rooted at a real filesystem path.
class IoVaultStore implements VaultStore {
  IoVaultStore(String rootPath) : rootPath = p.normalize(rootPath);

  final String rootPath;

  @override
  String get displayRoot => rootPath;

  Directory get _root => Directory(rootPath);

  File _file(List<String> segments) => File(p.joinAll([rootPath, ...segments]));

  Directory _directory(List<String> segments) =>
      Directory(p.joinAll([rootPath, ...segments]));

  @override
  Future<void> ensureDirectory(List<String> segments) async {
    await _directory(segments).create(recursive: true);
  }

  @override
  Future<bool> fileExists(List<String> segments) => _file(segments).exists();

  @override
  Future<String?> readText(List<String> segments) async {
    final file = _file(segments);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeTextAtomic(List<String> segments, String contents) async {
    final file = _file(segments);
    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(contents, flush: true);
    await temporaryFile.rename(file.path);
  }

  @override
  Future<void> renameFile(List<String> from, List<String> to) async {
    final source = _file(from);
    final target = _file(to);
    await target.parent.create(recursive: true);
    await source.rename(target.path);
  }

  @override
  Future<void> deleteFile(List<String> segments) async {
    final file = _file(segments);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<List<String>> listFileNames(List<String> segments) async {
    final directory = _directory(segments);
    if (!await directory.exists()) return const [];

    final names = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        names.add(p.basename(entity.path));
      }
    }
    return names;
  }

  /// Probes whether the process can create and read files under this root.
  Future<void> assertWritable() async {
    await _root.create(recursive: true);
    final probe = File(p.join(rootPath, '.stride_tracker_write_probe'));
    try {
      await probe.writeAsString('ok', flush: true);
      await probe.readAsString();
      await probe.delete();
    } on PathAccessException catch (error) {
      throw StateError(
        'Permission denied for "$rootPath". '
        'Pick the folder again so the app receives storage permission.\n\n'
        '$error',
      );
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 13) {
        throw StateError(
          'Permission denied for "$rootPath". '
          'Re-select the vault folder so the app can access it.\n\n$error',
        );
      }
      rethrow;
    }
  }
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));
