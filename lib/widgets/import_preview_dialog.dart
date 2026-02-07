import 'package:flutter/material.dart';

import '../models/backup_preview.dart';

class ImportPreviewDialog extends StatefulWidget {
  final BackupPreview preview;
  final ImportMode initialMode;

  const ImportPreviewDialog({
    super.key,
    required this.preview,
    this.initialMode = ImportMode.replace,
  });

  static Future<ImportMode?> show(
    BuildContext context, {
    required BackupPreview preview,
    ImportMode initialMode = ImportMode.replace,
  }) {
    return showDialog<ImportMode>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ImportPreviewDialog(preview: preview, initialMode: initialMode),
    );
  }

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  late ImportMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;

    return AlertDialog(
      title: const Text('Import backup'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.fileName != null && p.fileName!.trim().isNotEmpty) Text('File: ${p.fileName}'),
              if (p.byteLength != null) Text('Size: ${p.byteLength} bytes'),
              Text('Version: ${p.version}'),
              Text('Exported: ${p.exportedAt.toLocal()}'),
              const SizedBox(height: 12),
              Text('Contacts: ${p.contactsCount}'),
              Text('Conversations: ${p.conversationsCount}'),
              Text('Messages: ${p.messagesCount}'),
              Text('Attachments: ${p.attachmentsCount}'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),
              const Text('Import mode', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SegmentedButton<ImportMode>(
                segments: const <ButtonSegment<ImportMode>>[
                  ButtonSegment(value: ImportMode.replace, label: Text('Replace')),
                  ButtonSegment(value: ImportMode.merge, label: Text('Merge')),
                ],
                selected: <ImportMode>{_mode},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _mode = s.first);
                },
              ),
              const SizedBox(height: 10),
              Text(
                _mode == ImportMode.replace
                    ? 'Replace overwrites contacts/conversations/messages found in the backup.'
                    : 'Merge adds missing items and keeps existing data (safer).',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
