import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/backup_preview.dart';
import '../routes/app_routes.dart';
import '../services/backup_service.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';
import '../widgets/import_preview_dialog.dart';
import '../widgets/mini_presence_dock.dart';

class BackupStatusScreen extends StatefulWidget {
  const BackupStatusScreen({super.key});

  @override
  State<BackupStatusScreen> createState() => _BackupStatusScreenState();
}

class _BackupStatusScreenState extends State<BackupStatusScreen> {
  late Future<BackupPreview> _previewFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = BackupService.buildLocalPreview();
  }

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    final muted = Colors.white70;
    final user = FirebaseAuth.instance.currentUser;

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      useGradient: false,
      useOverlay: false,
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        foregroundColor: fg,
        title: Text('Backup status', style: TextStyle(color: fg)),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: const BottomNavStrip(
        current: BottomNavTab.chats,
        dock: MiniPresenceDock(mode: PresenceMode.social, compact: true),
      ),
      child: FutureBuilder<BackupPreview>(
        future: _previewFuture,
        builder: (context, snap) {
          final preview = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                title: 'Cloud status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Signed in', user != null ? 'Yes' : 'No'),
                    if (user?.email != null && user!.email!.trim().isNotEmpty)
                      _row('Account', user.email!),
                    const SizedBox(height: 10),
                    Text(
                      'Cloud-synced data',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    _bullet('Showcases and discussions'),
                    _bullet('Showcase media (photos/videos)'),
                    _bullet('Promotes and invites'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                title: 'Device-only data',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet('Contacts'),
                    _bullet('Conversations & messages'),
                    _bullet('Drafts and local attachments'),
                    _bullet('Owner profile & hidden panel settings'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                title: 'Local backup summary',
                child: preview == null
                    ? Text('Loading...', style: TextStyle(color: muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row('Contacts', preview.contactsCount.toString()),
                          _row('Conversations', preview.conversationsCount.toString()),
                          _row('Messages', preview.messagesCount.toString()),
                          _row('Attachments', preview.attachmentsCount.toString()),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _card(
                title: 'Last backup',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Last export', _fmtDate(BackupService.getLastExportAt())),
                    _row('Last import', _fmtDate(BackupService.getLastImportAt())),
                    _row('Last export path', BackupService.getLastExportPath() ?? '—'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                title: 'Backup actions',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _actionButton(
                      label: 'Export full backup',
                      onPressed: _busy ? null : _doExportFull,
                    ),
                    const SizedBox(height: 8),
                    _actionButton(
                      label: 'Export contacts only',
                      onPressed: _busy ? null : _doExportContacts,
                    ),
                    const SizedBox(height: 8),
                    _actionButton(
                      label: 'Import from file',
                      onPressed: _busy ? null : _doImport,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.inbox),
                      child: const Text('Back to inbox'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha((0.10 * 255).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white70)),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }

  Widget _actionButton({required String label, VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    return dt.toLocal().toString();
  }

  Future<void> _doExportFull() async {
    setState(() => _busy = true);
    final ok = await BackupService.exportSaveAs();
    if (mounted) {
      setState(() {
        _busy = false;
        _previewFuture = BackupService.buildLocalPreview();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Backup exported.' : 'Backup failed.')),
      );
    }
  }

  Future<void> _doExportContacts() async {
    setState(() => _busy = true);
    final ok = await BackupService.exportContactsOnlySaveAs();
    if (mounted) {
      setState(() {
        _busy = false;
        _previewFuture = BackupService.buildLocalPreview();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Contacts backup exported.' : 'Export failed.')),
      );
    }
  }

  Future<void> _doImport() async {
    setState(() => _busy = true);
    final picked = await BackupService.pickBackupForImport();
    if (!mounted) return;
    if (picked == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backup selected.')),
      );
      return;
    }
    final mode = await ImportPreviewDialog.show(context, preview: picked.preview);
    if (!mounted) return;
    if (mode == null) {
      setState(() => _busy = false);
      return;
    }
    final ok = await BackupService.applyImportBytes(picked.bytes, mode: mode);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _previewFuture = BackupService.buildLocalPreview();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Import completed.' : 'Import failed.')),
    );
  }
}
