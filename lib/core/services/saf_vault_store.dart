import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:saf/saf.dart';

import 'package:junk_food_tracker/core/services/vault_store.dart';

/// Android Storage Access Framework vault rooted at a `content://` tree URI.
class SafVaultStore implements VaultStore {
  SafVaultStore(this.rootUri) : _saf = Saf();

  final String rootUri;
  final Saf _saf;

  @override
  String get displayRoot => rootUri;

  Future<String> _directoryUri(List<String> segments) async {
    if (segments.isEmpty) return rootUri;
    final created = await _saf.mkdirp(rootUri, segments);
    return created.uri;
  }

  Future<SafDocumentFile?> _child(List<String> segments) {
    if (segments.isEmpty) {
      return _saf.stat(rootUri);
    }
    return _saf.child(rootUri, segments);
  }

  @override
  Future<void> ensureDirectory(List<String> segments) async {
    await _directoryUri(segments);
  }

  @override
  Future<bool> fileExists(List<String> segments) async {
    final doc = await _child(segments);
    return doc != null && !doc.isDir;
  }

  @override
  Future<String?> readText(List<String> segments) async {
    final doc = await _child(segments);
    if (doc == null || doc.isDir) return null;
    final bytes = await _saf.readFileBytes(doc.uri);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeTextAtomic(List<String> segments, String contents) async {
    if (segments.isEmpty) {
      throw ArgumentError('Cannot write the vault root as a file.');
    }

    final parentSegments = segments.sublist(0, segments.length - 1);
    final fileName = segments.last;
    final parentUri = await _directoryUri(parentSegments);
    final bytes = utf8Bytes(contents);

    await _saf.writeFileBytes(
      parentUri,
      fileName,
      'application/json',
      bytes,
      overwrite: true,
    );
  }

  @override
  Future<void> renameFile(List<String> from, List<String> to) async {
    final source = await _child(from);
    if (source == null || source.isDir) {
      throw StateError('Missing vault file: ${p.joinAll(from)}');
    }

    if (from.length == to.length &&
        from.sublist(0, from.length - 1).join('/') ==
            to.sublist(0, to.length - 1).join('/')) {
      await _saf.rename(source.uri, to.last);
      return;
    }

    final text = await readText(from);
    if (text == null) {
      throw StateError('Missing vault file: ${p.joinAll(from)}');
    }
    await writeTextAtomic(to, text);
    await _saf.delete(source.uri);
  }

  @override
  Future<void> deleteFile(List<String> segments) async {
    final doc = await _child(segments);
    if (doc == null || doc.isDir) return;
    await _saf.delete(doc.uri);
  }

  @override
  Future<List<String>> listFileNames(List<String> segments) async {
    final directoryUri = segments.isEmpty
        ? rootUri
        : (await _child(segments))?.uri;
    if (directoryUri == null) return const [];

    final children = await _saf.list(directoryUri);
    return children
        .where((child) => !child.isDir)
        .map((child) => child.name)
        .toList(growable: false);
  }
}
