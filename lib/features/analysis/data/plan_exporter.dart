import 'dart:convert';
import 'dart:io';

import 'package:debt_destroyer/features/analysis/data/schedule_export.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'plan_exporter.g.dart';

enum ExportFormat {
  csv('csv', 'text/csv'),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Hands a file to the platform share sheet.
abstract interface class FileSharer {
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  });
}

class SharePlusFileSharer implements FileSharer {
  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

/// Writes a schedule to a temporary file and shares it. The temporary
/// directory needs no storage permission.
class PlanExporter {
  PlanExporter(this._sharer, this._directory);

  final FileSharer _sharer;
  final Future<Directory> Function() _directory;

  /// Returns the file written (and shared).
  Future<File> export(
    ScheduleTable table,
    ExportFormat format, {
    required String baseName,
    String? subject,
  }) async {
    final dir = await _directory();
    final file = File('${dir.path}/$baseName.${format.extension}');
    final bytes = switch (format) {
      ExportFormat.csv => utf8.encode(scheduleToCsv(table)),
      ExportFormat.xlsx => scheduleToXlsx(table),
    };
    await file.writeAsBytes(bytes, flush: true);
    await _sharer.shareFile(file, mimeType: format.mimeType, subject: subject);
    return file;
  }
}

@Riverpod(keepAlive: true)
FileSharer fileSharer(Ref ref) => SharePlusFileSharer();

@Riverpod(keepAlive: true)
PlanExporter planExporter(Ref ref) =>
    PlanExporter(ref.watch(fileSharerProvider), getTemporaryDirectory);
