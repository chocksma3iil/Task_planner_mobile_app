import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'api_client.dart';

/// One downloaded report before it is handed to the platform saver.
class SavedExport {
  const SavedExport({
    required this.name,
    required this.extension,
    required this.bytes,
  });

  final String name;
  final String extension; // csv | pdf
  final List<int> bytes;
}

/// Project report downloads (E03).
///
/// Saving is injectable so widget tests can observe the bytes without a
/// platform channel; the app uses `file_saver` in production.
class ExportService {
  ExportService(this._client, {Future<void> Function(SavedExport)? onSave})
    : _save = onSave ?? _saveWithFileSaver;

  final ApiClient _client;
  final Future<void> Function(SavedExport export) _save;

  /// Downloads the [format] (`csv` or `pdf`) report of [projectId] and saves
  /// it through the configured saver.
  Future<SavedExport> exportProject({
    required int projectId,
    required String format,
  }) async {
    final bytes = await _client.getBytes(
      '/projects/$projectId/export?format=$format',
    );
    final export = SavedExport(
      name: 'project-$projectId-report',
      extension: format,
      bytes: bytes,
    );
    await _save(export);
    return export;
  }

  static Future<void> _saveWithFileSaver(SavedExport export) async {
    await FileSaver.instance.saveFile(
      name: export.name,
      bytes: Uint8List.fromList(export.bytes),
      fileExtension: export.extension,
      mimeType: export.extension == 'pdf' ? MimeType.pdf : MimeType.csv,
    );
  }
}
