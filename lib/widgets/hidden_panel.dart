import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes/app_routes.dart';
import '../data/contact_repository.dart';
import '../data/conversation_store.dart' as convs;
import '../data/message_repository.dart' as msgs;
import '../security/secure_gate.dart';
import '../security/unlock_profile.dart';
import '../security/owner_auth_flow.dart';
import '../security/biometric_auth_service.dart';
import '../security/bubble_unlock_pattern.dart';
import '../services/audit_log_service.dart';
import '../services/backup_service.dart';
import '../services/cover_ai_service.dart';
import '../security/unlock_service.dart';
import '../services/notification_service.dart';
import '../widgets/import_preview_dialog.dart';
import '../models/backup_preview.dart';
import '../models/contact.dart';

class HiddenPanel {
  HiddenPanel._();

  static Future<void> open(BuildContext context) async {
    await show(context);
  }

  static Future<void> show(
    BuildContext context, {
    String? conversationId,
    String? title,
    bool threadUnlocked = false,
    VoidCallback? onLockNow,
    VoidCallback? onClearCache,
    int? messageTtlMinutes,
    Future<void> Function(int? minutes)? onSetMessageTtl,
    bool? conversationHidden,
    VoidCallback? onToggleConversationHidden,
    bool? inboxHiddenView,
    VoidCallback? onToggleInboxView,
    VoidCallback? onManageMembers,
    UnlockProfile? unlockProfile,
    Future<void> Function(UnlockProfile profile)? onSetUnlockProfile,
  }) async {
    if (!context.mounted) return;

    final ok = await _ensureHiddenPanelAccess(context);
    if (!ok || !context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _PanelSheet(
          conversationId: conversationId,
          title: title,
          threadUnlocked: threadUnlocked,
          onLockNow: onLockNow,
          onClearCache: onClearCache,
          messageTtlMinutes: messageTtlMinutes,
          onSetMessageTtl: onSetMessageTtl,
          conversationHidden: conversationHidden,
          onToggleConversationHidden: onToggleConversationHidden,
          inboxHiddenView: inboxHiddenView,
          onToggleInboxView: onToggleInboxView,
          onManageMembers: onManageMembers,
          unlockProfile: unlockProfile,
          onSetUnlockProfile: onSetUnlockProfile,
        );
      },
    );
  }

  static Future<bool> _ensureHiddenPanelAccess(BuildContext context) async {
    final unlock = UnlockService();
    if (await unlock.isGlobalPanicActive()) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access blocked (panic active).')),
      );
      return false;
    }
    if (!context.mounted) return false;

    final hasHidden = await unlock.hasHiddenPanelPin();
    if (!context.mounted) return false;
    if (!hasHidden) {
      final created = await _promptCreateHiddenPin(context);
      return created == true;
    }
    if (!context.mounted) return false;

    final bioSupported = await BiometricAuthService.isSupported();
    if (!context.mounted) return false;
    if (bioSupported) {
      SecureGate.beginOwnerAuth();
      final ok = await BiometricAuthService.authenticateWithRetry(
        reason: 'Unlock hidden panel',
      );
      SecureGate.endOwnerAuth();
      if (ok) return true;
    }
    if (!context.mounted) return false;

    if (!bioSupported) {
      final locked = await unlock.isHiddenPanelLocked();
      if (!context.mounted) return false;
      if (locked) {
        final until = await unlock.hiddenPanelLockedUntil();
        if (!context.mounted) return false;
        final mins = _minutesRemaining(until);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                mins > 0
                    ? 'Hidden Panel locked. Try again in ${mins}m.'
                    : 'Hidden Panel locked. Try again later.',
              ),
            ),
          );
        }
        return false;
      }
    }

    final pin = await _askPin(context, title: 'Hidden Panel PIN');
    if (pin == null || pin.trim().isEmpty) return false;
    final ok = await unlock.verifyHiddenPanelPin(pin.trim());
    if (!context.mounted) return false;
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong Hidden Panel PIN.')),
      );
    }
    if (ok) {
      await unlock.resetHiddenPanelFailures();
    } else if (!bioSupported) {
      if (!context.mounted) return false;
      final messenger = ScaffoldMessenger.of(context);
      await unlock.recordHiddenPanelFailure();
      if (!context.mounted) return false;
      final locked = await unlock.isHiddenPanelLocked();
      if (locked) {
        final until = await unlock.hiddenPanelLockedUntil();
        final mins = _minutesRemaining(until);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              mins > 0
                  ? 'Hidden Panel locked. Try again in ${mins}m.'
                  : 'Hidden Panel locked. Try again later.',
            ),
          ),
        );
      }
    }
    return ok;
  }

  static Future<bool?> _promptCreateHiddenPin(BuildContext context) async {
    final unlock = UnlockService();
    final pin = await _askNewPin(
      context,
      title: 'Set Hidden Panel PIN',
      hint: '4+ digits',
    );
    if (pin == null) return false;
    if (!context.mounted) return false;

    final hasAppPin = await unlock.hasPassphrase();
    if (!context.mounted) return false;
    if (hasAppPin) {
      final sameAsApp = await unlock.verifyPassphrase(pin);
      if (!context.mounted) return false;
      if (sameAsApp) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hidden Panel PIN must differ from app PIN.'),
            ),
          );
        }
        return false;
      }
    }

    await unlock.setHiddenPanelPin(pin);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hidden Panel PIN set.')),
    );
    return true;
  }

  static Future<String?> _askPin(
    BuildContext context, {
    required String title,
  }) async {
    var pinText = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: AlertDialog(
            title: Text(title),
            content: TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              onChanged: (v) => pinText = v,
              onSubmitted: (_) => Navigator.pop(dctx, pinText),
              decoration: const InputDecoration(hintText: 'PIN'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, pinText),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<String?> _askNewPin(
    BuildContext context, {
    required String title,
    required String hint,
  }) async {
    String pin1 = '';
    String pin2 = '';
    String? error;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return MediaQuery.removeViewInsets(
              context: dctx,
              removeBottom: true,
              child: AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(hintText: hint),
                      onChanged: (v) => pin1 = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Repeat PIN'),
                      onChanged: (v) => pin2 = v,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      final p1 = pin1.trim();
                      final p2 = pin2.trim();
                      if (p1.length < 4) {
                        error = 'PIN too short.';
                        setLocal(() {});
                        return;
                      }
                      if (p1 != p2) {
                        error = 'PINs do not match.';
                        setLocal(() {});
                        return;
                      }
                      Navigator.pop(dctx, p1);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static int _minutesRemaining(DateTime? until) {
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return 0;
    final mins = (diff.inSeconds / 60).ceil();
    return mins < 0 ? 0 : mins;
  }
}

class _PanelSheet extends StatefulWidget {
  final String? conversationId;
  final String? title;
  final bool threadUnlocked;
  final VoidCallback? onLockNow;
  final VoidCallback? onClearCache;
  final int? messageTtlMinutes;
  final Future<void> Function(int? minutes)? onSetMessageTtl;
  final bool? conversationHidden;
  final VoidCallback? onToggleConversationHidden;
  final bool? inboxHiddenView;
  final VoidCallback? onToggleInboxView;
  final VoidCallback? onManageMembers;
  final UnlockProfile? unlockProfile;
  final Future<void> Function(UnlockProfile profile)? onSetUnlockProfile;

  const _PanelSheet({
    required this.conversationId,
    required this.title,
    required this.threadUnlocked,
    required this.onLockNow,
    required this.onClearCache,
    required this.messageTtlMinutes,
    required this.onSetMessageTtl,
    required this.conversationHidden,
    required this.onToggleConversationHidden,
    required this.inboxHiddenView,
    required this.onToggleInboxView,
    required this.onManageMembers,
    required this.unlockProfile,
    required this.onSetUnlockProfile,
  });

  @override
  State<_PanelSheet> createState() => _PanelSheetState();
}

class _PanelSheetState extends State<_PanelSheet> {
  final ContactRepository _contactsRepo = ContactRepository();
  final convs.ConversationStore _convs = convs.ConversationStore();
  final msgs.MessageRepository _msgs = msgs.MessageRepository();

  bool _busy = false;
  double _dragToClose = 0;
  UnlockProfile? _profile;
  List<AuditLogEntry> _auditEntries = const [];
  _AuditFilter _auditFilter = _AuditFilter.all;
  CoverAiSettings? _coverSettings;
  bool? _requireAppUnlock;
  BubbleUnlockPattern _bubblePattern = const BubbleUnlockPattern(<int>[]);
  bool _unlockMethodsUnlocked = false;
  bool _hasHiddenPin = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.unlockProfile;
    _loadAuditEntries();
    _loadCoverAiSettings();
    _loadAppUnlockSetting();
    _loadBubblePattern();
    _loadHiddenPinStatus();
  }

  Future<void> _loadAuditEntries() async {
    final rows = await AuditLogService.I.readRecent(limit: 12);
    if (!mounted) return;
    setState(() => _auditEntries = rows);
  }

  Future<void> _loadCoverAiSettings() async {
    final s = await CoverAiService.I.loadSettings();
    if (!mounted) return;
    setState(() => _coverSettings = s);
  }

  Future<void> _loadBubblePattern() async {
    final pattern = await BubbleUnlockPattern.load();
    if (!mounted) return;
    setState(() => _bubblePattern = pattern);
  }

  Future<void> _loadAppUnlockSetting() async {
    final v = await UnlockService().isAppUnlockRequired();
    if (!mounted) return;
    setState(() => _requireAppUnlock = v);
  }

  Future<void> _loadHiddenPinStatus() async {
    final v = await UnlockService().hasHiddenPanelPin();
    if (!mounted) return;
    setState(() => _hasHiddenPin = v);
  }

  Future<void> _doBackup() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final ok = await BackupService.exportSaveAs();
      if (!mounted) return;

      final path = BackupService.lastExportPath;
      final msg = ok
          ? (path == null || path.trim().isEmpty
              ? 'Done.'
              : 'Done. Saved to: $path')
          : 'Could not save.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImport() async {
    if (_busy) return;

    final confirm = await _confirmImport();
    if (!mounted) return;
    if (confirm != true) return;

    setState(() => _busy = true);

    try {
      final picked = await BackupService.pickBackupForImport();
      if (!mounted) return;
      if (picked == null) return;

      final mode = await ImportPreviewDialog.show(
        context,
        preview: picked.preview,
        initialMode: ImportMode.merge,
      );
      if (!mounted) return;
      if (mode == null) return;

      final ok = await BackupService.applyImportBytes(
        picked.bytes,
        mode: mode,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed.')),
        );
        return;
      }

      Navigator.of(context).pop();
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.inbox,
        (route) => false,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Done.')),
        );
      });
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImportFromDownloads() async {
    if (_busy) return;
    if (!Platform.isAndroid) return;

    final files = await BackupService.listDownloadBackups();
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backup files found in Downloads.')),
      );
      return;
    }

    final sorted = files.toList(growable: false)
      ..sort((a, b) {
        final as = a.statSync();
        final bs = b.statSync();
        return bs.modified.compareTo(as.modified);
      });

    final pickedPath = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return AlertDialog(
          title: const Text('Pick from Downloads'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (_, i) {
                final f = sorted[i] as File;
                final stat = f.statSync();
                final name = f.path.split(Platform.pathSeparator).last;
                final subtitle =
                    '${_formatAuditTime(stat.modified)} · ${_formatBytes(stat.size)}';
                return ListTile(
                  title: Text(name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(subtitle),
                  onTap: () => Navigator.pop(dctx, f.path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (pickedPath == null || pickedPath.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final picked = await BackupService.readBackupFromPath(pickedPath);
      if (!mounted) return;
      if (picked == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read backup file.')),
        );
        return;
      }

      final mode = await ImportPreviewDialog.show(
        context,
        preview: picked.preview,
        initialMode: ImportMode.merge,
      );
      if (!mounted) return;
      if (mode == null) return;

      final ok = await BackupService.applyImportBytes(
        picked.bytes,
        mode: mode,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Done.' : 'Import failed.')),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doBackupContacts() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final ok = await BackupService.exportContactsOnlySaveAs();
      if (!mounted) return;

      final path = BackupService.lastExportPath;
      final msg = ok
          ? (path == null || path.trim().isEmpty
              ? 'Done.'
              : 'Done. Saved to: $path')
          : 'Could not save.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doBackupConversation() async {
    if (_busy) return;
    final cid = widget.conversationId?.trim() ?? '';
    if (cid.isEmpty) return;

    setState(() => _busy = true);

    try {
      final ok =
          await BackupService.exportConversationSaveAs(conversationId: cid);
      if (!mounted) return;

      final path = BackupService.lastExportPath;
      final msg = ok
          ? (path == null || path.trim().isEmpty
              ? 'Done.'
              : 'Done. Saved to: $path')
          : 'Could not save.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImportContacts() async {
    if (_busy) return;

    final picked = await BackupService.pickBackupForImport();
    if (!mounted) return;
    if (picked == null) return;

    final mode = await ImportPreviewDialog.show(
      context,
      preview: picked.preview,
      initialMode: ImportMode.merge,
    );
    if (!mounted) return;
    if (mode == null) return;

    final report = await BackupService.previewContactsImport(
      picked.bytes,
      mode: mode,
    );
    if (!mounted) return;

    setState(() => _busy = true);

    try {
      final ok = await BackupService.applyImportContactsBytes(
        picked.bytes,
        mode: mode,
      );
      if (!mounted) return;

      final text = ok
          ? (report == null
              ? 'Done.'
              : (mode == ImportMode.replace
                  ? 'Done. Replaced contacts: ${report.incomingCount}.'
                  : 'Done. New: ${report.newCount}, merged: ${report.mergedCount}.'))
          : 'Import failed.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImportConversation() async {
    if (_busy) return;
    final cid = widget.conversationId?.trim() ?? '';
    if (cid.isEmpty) return;

    final picked = await BackupService.pickBackupForImport();
    if (!mounted) return;
    if (picked == null) return;

    final mode = await ImportPreviewDialog.show(
      context,
      preview: picked.preview,
      initialMode: ImportMode.merge,
    );
    if (!mounted) return;
    if (mode == null) return;

    setState(() => _busy = true);

    try {
      final ok = await BackupService.applyImportConversationsBytes(
        picked.bytes,
        mode: mode,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Done.' : 'Import failed.')),
      );
      await _loadAuditEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAuditLog() async {
    if (_busy) return;
    await AuditLogService.I.clear();
    await _loadAuditEntries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audit log cleared.')),
    );
  }

  Future<void> _exportAuditLog() async {
    if (_busy) return;
    final ok = await AuditLogService.I.exportSaveAs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok ? 'Audit log exported.' : 'Could not export log.')),
    );
  }

  Future<void> _pickTtl() async {
    final chosen = await _chooseTtlMinutes();
    if (!mounted) return;
    if (chosen == null) return;

    final minutes = (chosen <= 0) ? null : chosen;
    await widget.onSetMessageTtl?.call(minutes);
    if (!mounted) return;

    setState(() {});
  }

  Future<int?> _chooseTtlMinutes() async {
    return showDialog<int?>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return SimpleDialog(
          title: const Text('Auto-delete'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 0),
              child: const Text('Off'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 60),
              child: const Text('1 hour'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 1440),
              child: const Text('24 hours'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 10080),
              child: const Text('7 days'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 43200),
              child: const Text('30 days'),
            ),
          ],
        );
      },
    );
  }

  String _ttlLabel(int? minutes) {
    if (minutes == null || minutes <= 0) return 'Off';
    if (minutes == 60) return '1 hour';
    if (minutes == 1440) return '24 hours';
    if (minutes == 10080) return '7 days';
    if (minutes == 43200) return '30 days';
    return '${minutes}m';
  }

  Future<bool?> _confirmImport() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return AlertDialog(
          title: const Text(''),
          content: const Text(
            'Import will replace local data (contacts, conversations, messages).\n\nContinue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasThreadOps =
        (widget.onLockNow != null) || (widget.onClearCache != null);
    final convId = widget.conversationId?.trim() ?? '';
    final hasConv = convId.isNotEmpty;

    final session = SecureGate.isSessionUnlocked;
    final conv = hasConv ? SecureGate.isConversationUnlocked(convId) : false;

    final isHiddenView = widget.inboxHiddenView == true;
    final convHidden = widget.conversationHidden == true;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canEditUnlockProfile =
        widget.onSetUnlockProfile != null && _profile != null;
    final filteredAuditEntries =
        _auditEntries.where(_matchesAuditFilter).toList(
              growable: false,
            );
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withAlpha((0.45 * 255).round())),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.18 * 255).round()),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset, top: 88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) {
                      if (d.delta.dy <= 0) return;
                      _dragToClose = (_dragToClose + d.delta.dy).clamp(0, 120);
                    },
                    onVerticalDragEnd: (_) {
                      if (_dragToClose > 48) {
                        Navigator.of(context).pop();
                      }
                      _dragToClose = 0;
                    },
                    onVerticalDragCancel: () => _dragToClose = 0,
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: muted.withAlpha((0.45 * 255).round()),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
              if (hasConv)
                _sectionCard(
                  title: 'Status',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _pill('Session: ${session ? 'Unlocked' : 'Locked'}',
                          session),
                      _pill('Conversation: ${conv ? 'Unlocked' : 'Locked'}',
                          conv),
                      _pill(
                          'View: ${widget.threadUnlocked ? 'Hidden' : 'Cover'}',
                          widget.threadUnlocked),
                    ],
                  ),
                ),
              _sectionCard(
                title: 'Views',
                child: Column(
                  children: [
                    if (widget.onToggleInboxView != null)
                      _actionTile(
                        icon: Icons.layers_outlined,
                        title: isHiddenView
                            ? 'View main inbox'
                            : 'View hidden inbox',
                        subtitle: isHiddenView
                            ? 'Switch back to main inbox.'
                            : 'Switch to hidden inbox.',
                        onTap: _busy
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                widget.onToggleInboxView?.call();
                              },
                      ),
                    if (hasConv &&
                        widget.onToggleConversationHidden != null) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.visibility_off_outlined,
                        title: convHidden
                            ? 'Move to main inbox'
                            : 'Move to hidden inbox',
                        subtitle: convHidden
                            ? 'Make this conversation visible.'
                            : 'Hide this conversation.',
                        onTap: _busy
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                widget.onToggleConversationHidden?.call();
                              },
                      ),
                    ],
                    if (hasConv && widget.onManageMembers != null) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.group_outlined,
                        title: 'Manage members',
                        subtitle: 'Add or remove members.',
                        onTap: _busy
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                widget.onManageMembers?.call();
                              },
                      ),
                    ],
                    if (hasConv && widget.onSetMessageTtl != null) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.timer_outlined,
                        title: 'Auto-delete',
                        subtitle:
                            'Current: ${_ttlLabel(widget.messageTtlMinutes)}',
                        onTap: _busy ? null : _pickTtl,
                      ),
                    ],
                  ],
                ),
                ),
              _sectionCard(
                title: 'Hidden panel security',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasHiddenPin
                          ? 'Access protected (biometrics or Hidden PIN).'
                          : 'No Hidden Panel PIN set yet.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.lock_outline,
                      title:
                          _hasHiddenPin ? 'Change Hidden Panel PIN' : 'Set Hidden Panel PIN',
                      subtitle: _hasHiddenPin
                          ? 'PIN must be different from app PIN.'
                          : 'Required to protect Hidden Panel access.',
                      onTap: _busy ? null : _changeHiddenPanelPin,
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.security_outlined,
                      title: 'Recover Hidden Panel PIN',
                      subtitle: 'App PIN + biometrics required.',
                      onTap: _busy ? null : _recoverHiddenPanelPin,
                    ),
                  ],
                ),
              ),
              if (canEditUnlockProfile)
                _sectionCard(
                  title: 'Unlock methods',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_unlockMethodsUnlocked)
                        _actionTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Unlock settings',
                          subtitle: 'Require biometrics/PIN to edit.',
                          onTap: _busy ? null : _unlockMethodsGate,
                        )
                      else ...[
                        _sectionTitle('Hidden panel access'),
                        _switchRow(
                          label: 'Pull down to open hidden panel',
                          value: _profile!.pullDownPanel,
                          onChanged: (v) => _setProfile(
                              _profile!.copyWith(pullDownPanel: v)),
                        ),
                        _switchRow(
                          label: 'Double tap on title',
                          value: _profile!.doubleTapTitle,
                          onChanged: (v) => _setProfile(
                              _profile!.copyWith(doubleTapTitle: v)),
                        ),
                      ],
                    ],
                  ),
                ),
              _sectionCard(
                title: 'Bubble unlock signal',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bubblePattern.isSet
                          ? 'Signal saved.'
                          : 'No signal saved yet.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tip: the pad represents a bubble. Top of the pad = top of the bubble.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.gesture_outlined,
                      title: 'Configure signal',
                      subtitle: 'Tap/gesture pattern used to reveal bubbles.',
                      onTap: _busy ? null : _configureBubblePattern,
                    ),
                    if (_bubblePattern.isSet) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.delete_outline,
                        title: 'Clear signal',
                        subtitle: 'Remove the current bubble unlock signal.',
                        onTap: _busy ? null : _clearBubblePattern,
                      ),
                    ],
                  ],
                ),
              ),
              if (_coverSettings != null)
                _sectionCard(
                  title: 'Cover AI (local)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _switchRow(
                        label: 'Generate cover text locally',
                        value: _coverSettings!.enabled,
                        onChanged: (v) => _setCoverSettings(
                          _coverSettings!.copyWith(enabled: v),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _switchRow(
                        label: 'Automatic language',
                        value: _coverSettings!.languageMode == 'auto',
                        onChanged: (v) {
                          final nextMode = v
                              ? 'auto'
                              : (_deviceLang() == 'it' ? 'it' : 'en');
                          _setCoverSettings(
                            _coverSettings!.copyWith(languageMode: nextMode),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Exclusive language',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      IgnorePointer(
                        ignoring: _coverSettings!.languageMode == 'auto',
                        child: Opacity(
                          opacity:
                              _coverSettings!.languageMode == 'auto' ? 0.5 : 1,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _langChip('it', 'Italiano'),
                              _langChip('en', 'English'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Local only: no network requests.',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              _sectionCard(
                title: 'Backup & import',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Backup'),
                    _actionTile(
                      icon: Icons.save_alt,
                      title: 'Backup (full)',
                      subtitle: 'Save everything to a location you choose.',
                      onTap: _busy ? null : _doBackup,
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.save_alt,
                      title: 'Backup contacts only',
                      subtitle: 'Save only contacts.',
                      onTap: _busy ? null : _doBackupContacts,
                    ),
                    if (hasConv) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.save_alt,
                        title: 'Backup this conversation',
                        subtitle: 'Save only this conversation.',
                        onTap: _busy ? null : _doBackupConversation,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _sectionTitle('Import'),
                    _actionTile(
                      icon: Icons.folder_open,
                      title: 'Import (full)',
                      subtitle: 'Load a previously saved full backup.',
                      onTap: _busy ? null : _doImport,
                    ),
                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.download_for_offline_outlined,
                        title: 'Import from Downloads',
                        subtitle: 'Pick a backup saved in Downloads.',
                        onTap: _busy ? null : _doImportFromDownloads,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.folder_open,
                      title: 'Import contacts only',
                      subtitle: 'Load contacts from a backup file.',
                      onTap: _busy ? null : _doImportContacts,
                    ),
                    if (hasConv) ...[
                      const SizedBox(height: 8),
                      _actionTile(
                        icon: Icons.folder_open,
                        title: 'Import into this conversation',
                        subtitle: 'Load a conversation backup.',
                        onTap: _busy ? null : _doImportConversation,
                      ),
                    ],
                  ],
                ),
              ),
              _sectionCard(
                title: 'Notifications',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _actionTile(
                      icon: Icons.notifications_active_outlined,
                      title: 'Test incoming chat',
                      subtitle: 'Pick a contact and deliver a test message.',
                      onTap: _busy ? null : _showTestNotificationPrompt,
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      icon: Icons.key_outlined,
                      title: 'Copy FCM token',
                      subtitle: 'Copy the device token for Firebase tests.',
                      onTap: _busy
                          ? null
                          : () async {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              final token =
                                  NotificationService.I.getCachedToken() ??
                                      await NotificationService.I.refreshToken();
                              if (token == null || token.trim().isEmpty) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                      content: Text('Token not available yet.')),
                                );
                                return;
                              }
                              await Clipboard.setData(
                                  ClipboardData(text: token));
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text('FCM token copied.')),
                              );
                            },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Firebase Console → Cloud Messaging → Send test message → paste token.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (hasThreadOps)
                _sectionCard(
                  title: 'Security',
                  child: Column(
                    children: [
                      if (_requireAppUnlock != null)
                        _switchRow(
                          label: 'Require PIN on app open',
                          value: _requireAppUnlock!,
                          onChanged: (v) => _setRequireAppUnlock(v),
                        ),
                      if (widget.onClearCache != null)
                        _actionTile(
                          icon: Icons.cleaning_services_outlined,
                          title: 'Clear cache',
                          subtitle: 'Forget revealed content.',
                          onTap: _busy
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onClearCache?.call();
                                },
                        ),
                      if (widget.onLockNow != null) ...[
                        const SizedBox(height: 8),
                        _actionTile(
                          icon: Icons.lock_outline,
                          title: 'Lock',
                          subtitle: 'Hide content now.',
                          onTap: _busy
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onLockNow?.call();
                                },
                        ),
                      ],
                    ],
                  ),
                ),
              if (session)
                _sectionCard(
                  title: 'Owner audit log',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _filterChip(_AuditFilter.all, 'All'),
                          _filterChip(_AuditFilter.security, 'Security'),
                          _filterChip(_AuditFilter.backup, 'Backup'),
                          _filterChip(_AuditFilter.errors, 'Errors'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (filteredAuditEntries.isEmpty)
                        Text(
                          'No entries for this filter.',
                          style: TextStyle(color: muted, fontSize: 12),
                        )
                      else
                        ...filteredAuditEntries.map((e) {
                          final status = e.status.trim();
                          final ts = _formatAuditTime(e.timestamp);
                          final convSuffix = e.conversationId.isEmpty
                              ? ''
                              : ' · ${e.conversationId}';
                          final noteSuffix =
                              e.note.isEmpty ? '' : ' · ${e.note}';
                          final subtitle = '$ts$convSuffix$noteSuffix';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: status == 'ok'
                                        ? scheme.primary
                                        : (status.isEmpty
                                            ? muted
                                            : scheme.tertiary),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _eventLabel(e.event),
                                        style: TextStyle(
                                            color: fg, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                            color: muted,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            TextButton.icon(
                              onPressed: _busy ? null : _exportAuditLog,
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Export log'),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : _clearAuditLog,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear log'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withAlpha((0.35 * 255).round()),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 36,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Back', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title?.trim().isNotEmpty == true
                              ? widget.title!.trim()
                              : 'Options',
                          style: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 128,
                      height: 36,
                      child: (widget.onToggleInboxView != null)
                          ? OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      widget.onToggleInboxView?.call();
                                    },
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  (widget.inboxHiddenView == true)
                                      ? 'Inbox'
                                      : 'Hidden Inbox',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final cardBg = scheme.surface;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }

  void _setProfile(UnlockProfile next) {
    setState(() => _profile = next);
    widget.onSetUnlockProfile?.call(next);
  }

  Future<void> _setCoverSettings(CoverAiSettings next) async {
    setState(() => _coverSettings = next);
    await CoverAiService.I.saveSettings(next);
  }

  Future<void> _setRequireAppUnlock(bool v) async {
    setState(() => _requireAppUnlock = v);
    await UnlockService().setAppUnlockRequired(v);
  }

  Future<bool> _ensureOwnerUnlock() async {
    try {
      if (SecureGate.isPanicActive) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unlock blocked (panic active).')),
          );
        }
        return false;
      }
      final ok = await OwnerAuthFlow.ensureOwnerSessionUnlocked(context);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required.')),
        );
      }
      return ok;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication failed.')),
        );
      }
      return false;
    }
  }

  Future<void> _unlockMethodsGate() async {
    final ok = await _ensureOwnerUnlock();
    if (!ok) return;
    if (!mounted) return;
    setState(() => _unlockMethodsUnlocked = true);
  }

  Future<void> _changeHiddenPanelPin() async {
    if (_busy) return;
    final unlock = UnlockService();

    if (_hasHiddenPin) {
      final current = await _askPinDialog('Current Hidden PIN');
      if (current == null || current.trim().isEmpty) return;
      final ok = await unlock.verifyHiddenPanelPin(current.trim());
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong Hidden Panel PIN.')),
        );
        return;
      }
    }

    final newPin = await _askNewPinDialog('New Hidden Panel PIN');
    if (newPin == null) return;

    final hasAppPin = await unlock.hasPassphrase();
    if (hasAppPin) {
      final sameAsApp = await unlock.verifyPassphrase(newPin);
      if (sameAsApp) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hidden Panel PIN must differ from app PIN.'),
          ),
        );
        return;
      }
    }

    await unlock.setHiddenPanelPin(newPin);
    await _loadHiddenPinStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hidden Panel PIN updated.')),
    );
  }

  Future<void> _recoverHiddenPanelPin() async {
    if (_busy) return;
    final unlock = UnlockService();
    final hasAppPin = await unlock.hasPassphrase();
    if (!hasAppPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set an app PIN first.')),
      );
      return;
    }

    final pin = await _askPinDialog('App PIN');
    if (pin == null || pin.trim().isEmpty) return;
    final okPin = await unlock.verifyPassphrase(pin.trim());
    if (!okPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App PIN incorrect.')),
      );
      return;
    }

    final okBio = await BiometricAuthService.authenticateWithRetry(
      reason: 'Recover Hidden Panel PIN',
    );
    if (!okBio) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric authentication failed.')),
      );
      return;
    }

    final newPin = await _askNewPinDialog('New Hidden Panel PIN');
    if (newPin == null) return;

    final sameAsApp = await unlock.verifyPassphrase(newPin);
    if (sameAsApp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hidden Panel PIN must differ from app PIN.'),
        ),
      );
      return;
    }

    await unlock.setHiddenPanelPin(newPin);
    await AuditLogService.I.log('hidden_pin_recover', status: 'ok');
    await _loadHiddenPinStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hidden Panel PIN recovered.')),
    );
  }

  Future<String?> _askPinDialog(String title) async {
    var pinText = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: AlertDialog(
            title: Text(title),
            content: TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              onChanged: (v) => pinText = v,
              onSubmitted: (_) => Navigator.pop(dctx, pinText),
              decoration: const InputDecoration(hintText: 'PIN'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, pinText),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askNewPinDialog(String title) async {
    String pin1 = '';
    String pin2 = '';
    String? error;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return MediaQuery.removeViewInsets(
              context: dctx,
              removeBottom: true,
              child: AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '4+ digits'),
                      onChanged: (v) => pin1 = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Repeat PIN'),
                      onChanged: (v) => pin2 = v,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      final p1 = pin1.trim();
                      final p2 = pin2.trim();
                      if (p1.length < 4) {
                        error = 'PIN too short.';
                        setLocal(() {});
                        return;
                      }
                      if (p1 != p2) {
                        error = 'PINs do not match.';
                        setLocal(() {});
                        return;
                      }
                      Navigator.pop(dctx, p1);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _configureBubblePattern() async {
    if (!mounted) return;

    final path = await _showBubblePatternDialog();
    if (!mounted) return;
    if (path == null || path.length < 6) return;

    final ok = await _ensureOwnerUnlock();
    if (!ok) return;

    await BubbleUnlockPattern.saveGesture(path);
    await _loadBubblePattern();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bubble unlock signal saved.')),
    );
  }

  Future<void> _clearBubblePattern() async {
    final ok = await _ensureOwnerUnlock();
    if (!ok) return;
    if (!mounted) return;
    await BubbleUnlockPattern.clear();
    await _loadBubblePattern();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bubble unlock signal cleared.')),
    );
  }

  Future<List<Offset>?> _showBubblePatternDialog() async {
    List<Offset> first = [];
    List<Offset> current = [];
    String? error;
    int step = 1;
    DateTime? lastAt;

    return showDialog<List<Offset>>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        void addPoint(Offset local, Size size, StateSetter setLocal) {
          final nx = (local.dx / size.width).clamp(0.0, 1.0);
          final ny = (local.dy / size.height).clamp(0.0, 1.0);
          final now = DateTime.now();
          if (current.isNotEmpty) {
            final last = current.last;
            final dx = (nx - last.dx).abs();
            final dy = (ny - last.dy).abs();
            if ((dx + dy) < 0.01 && lastAt != null) {
              final tooSoon = now.difference(lastAt!).inMilliseconds < 60;
              if (tooSoon) return;
            }
          }
          current.add(Offset(nx, ny));
          lastAt = now;
          setLocal(() {});
        }

        void clearCurrent(StateSetter setLocal) {
          current.clear();
          error = null;
          lastAt = null;
          setLocal(() {});
        }

        void advance(StateSetter setLocal) {
          if (current.length < 6) {
            error = 'Signal too short (draw a longer gesture).';
            setLocal(() {});
            return;
          }
          if (step == 1) {
            first = List<Offset>.from(current);
            current.clear();
            step = 2;
            error = null;
            setLocal(() {});
            return;
          }
          if (!_matchGesture(first, current)) {
            error = 'Signals do not match.';
            setLocal(() {});
            return;
          }
          Navigator.pop(dctx, List<Offset>.from(current));
        }

        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: Text(step == 1
                    ? 'Set bubble unlock signal'
                    : 'Repeat the signal'),
                content: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _gesturePad(
                        onInput: (local, size) => addPoint(local, size, setLocal),
                        active: current,
                      ),
                      const SizedBox(height: 8),
                        Text(
                          'Points: ${current.length}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 6),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => clearCurrent(setLocal),
                    child: const Text('Clear'),
                  ),
                  TextButton(
                    onPressed: () => advance(setLocal),
                    child: Text(step == 1 ? 'Next' : 'Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _gesturePad({
    required void Function(Offset local, Size size) onInput,
    required List<Offset> active,
  }) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxWidth);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onInput(d.localPosition, size),
          onPanUpdate: (d) => onInput(d.localPosition, size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
              painter: _GesturePadPainter(
                points: active,
                color: Theme.of(context).colorScheme.primary,
                grid: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withAlpha((0.35 * 255).round()),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _matchGesture(List<Offset> a, List<Offset> b) {
    final aa = _resample(a, 32);
    final bb = _resample(b, 32);
    if (aa.isEmpty || bb.isEmpty) return false;
    double sum = 0;
    for (var i = 0; i < aa.length; i++) {
      final dx = aa[i].dx - bb[i].dx;
      final dy = aa[i].dy - bb[i].dy;
      sum += sqrt(dx * dx + dy * dy);
    }
    final avg = sum / aa.length;
    return avg < 0.12;
  }

  List<Offset> _resample(List<Offset> pts, int count) {
    if (pts.length < 2) return pts;
    final out = <Offset>[];
    final total = _pathLength(pts);
    if (total <= 0) return pts;
    final step = total / (count - 1);
    double dist = 0;
    out.add(pts.first);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final cur = pts[i];
      final seg = (cur - prev).distance;
      if ((dist + seg) >= step) {
        final t = (step - dist) / seg;
        final nx = prev.dx + (cur.dx - prev.dx) * t;
        final ny = prev.dy + (cur.dy - prev.dy) * t;
        final p = Offset(nx, ny);
        out.add(p);
        pts.insert(i, p);
        dist = 0;
      } else {
        dist += seg;
      }
      if (out.length == count) break;
    }
    while (out.length < count) {
      out.add(pts.last);
    }
    return out;
  }

  double _pathLength(List<Offset> pts) {
    double sum = 0;
    for (var i = 1; i < pts.length; i++) {
      sum += (pts[i] - pts[i - 1]).distance;
    }
    return sum;
  }

  Future<void> _showTestNotificationPrompt() async {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    final contacts = await _contactsRepo.getAll();
    if (!mounted) return;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts available.')),
      );
      return;
    }

    _IncomingTest? res;
    Contact? selected = contacts.isNotEmpty ? contacts.first : null;
    String query = '';
    String message = '';
    bool sendToHidden = false;

    final picked = await showDialog<_IncomingTest>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        List<Contact> filterItems() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return contacts;
          return contacts.where((c) {
            final cover = c.coverName.toLowerCase();
            final phone = (c.phone ?? '').toLowerCase();
            return cover.contains(q) || phone.contains(q);
          }).toList(growable: false);
        }

        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final filtered = filterItems();
              if (selected == null && filtered.isNotEmpty) {
                selected = filtered.first;
              }
              return AlertDialog(
                title: const Text('Test incoming chat'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        decoration:
                            const InputDecoration(hintText: 'Search contact'),
                        onChanged: (v) {
                          query = v;
                          setLocal(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx2, i) {
                            final c = filtered[i];
                            final title = c.coverName.isEmpty
                                ? '(no name)'
                                : c.coverName;
                            final isSelected = selected?.id == c.id;
                            return ListTile(
                              title: Text(title),
                              subtitle: (c.phone ?? '').isEmpty
                                  ? null
                                  : Text(c.phone!),
                              leading: Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              onTap: () {
                                selected = c;
                                setLocal(() {});
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration:
                            const InputDecoration(hintText: 'Message text'),
                        onChanged: (v) => message = v,
                        onSubmitted: (_) => Navigator.pop(
                          dctx,
                          _IncomingTest(
                            contact: selected!,
                            text: message.trim(),
                            hidden: sendToHidden,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: sendToHidden,
                        onChanged: (v) {
                          sendToHidden = v == true;
                          setLocal(() {});
                        },
                        title: const Text('Send to Hidden Inbox'),
                        subtitle: const Text('Notification will be generic.'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (selected == null) {
                        Navigator.pop(dctx, null);
                        return;
                      }
                      Navigator.pop(
                        dctx,
                        _IncomingTest(
                          contact: selected!,
                          text: message.trim(),
                          hidden: sendToHidden,
                        ),
                      );
                    },
                    child: const Text('Send'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (picked == null) return;
    res = picked;

    final contact = res.contact;
    final conv = await _convs.getOrCreateForContact(
      contactId: contact.id,
      fallbackTitle: contact.coverName,
    );

    if (res.hidden) {
      await _convs.setHidden(conversationId: conv.id, hidden: true);
    }

    final text = res.text.isEmpty ? 'Hi.' : res.text;
    await _msgs.receiveMessage(
      conversationId: conv.id,
      text: text,
      authorId: 'c_${contact.id}',
      authorName: contact.coverName.isEmpty ? 'Contact' : contact.coverName,
    );
    if (res.hidden) {
      await _convs.setHidden(conversationId: conv.id, hidden: true);
    }
    await NotificationService.I.showTestNotification(
      sender: contact.coverName.isEmpty ? null : contact.coverName,
      hidden: res.hidden,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test message delivered.')),
    );
  }

  Widget _sectionTitle(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 6),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _pill(String label, bool isActive) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isActive
        ? scheme.primary.withAlpha(28)
        : scheme.surfaceContainerHighest;
    final fg = isActive ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(color: scheme.onSurface)),
      value: value,
      onChanged: _busy ? null : onChanged,
    );
  }

  String _formatAuditTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    var idx = 0;
    while (v >= 1024 && idx < units.length - 1) {
      v /= 1024;
      idx += 1;
    }
    final s = (v < 10 && idx > 0) ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
    return '$s ${units[idx]}';
  }

  String _eventLabel(String event) {
    switch (event) {
      case 'owner_auth':
        return 'Owner auth';
      case 'owner_auth_panic':
        return 'Owner auth (panic)';
      case 'conversation_unlock':
        return 'Conversation unlocked';
      case 'conversation_lock':
        return 'Conversation locked';
      case 'panic_activate':
        return 'Panic activated';
      case 'panic_clear':
        return 'Panic cleared';
      case 'backup_export_full':
        return 'Backup exported (full)';
      case 'backup_export_contacts':
        return 'Backup exported (contacts)';
      case 'backup_export_conversation':
        return 'Backup exported (conversation)';
      case 'backup_import_full':
        return 'Backup imported (full)';
      case 'backup_import_contacts':
        return 'Backup imported (contacts)';
      case 'backup_import_conversations':
        return 'Backup imported (conversations)';
      case 'pin_set':
        return 'PIN set';
      case 'panic_pin_set':
        return 'Panic PIN set';
      case 'hidden_pin_set':
        return 'Hidden panel PIN set';
      case 'hidden_pin_recover':
        return 'Hidden panel PIN recovered';
      case 'hidden_pin_lockout':
        return 'Hidden panel lockout';
      case 'security_reset':
        return 'Security reset';
      default:
        return event.trim().isEmpty ? 'Event' : event;
    }
  }

  bool _matchesAuditFilter(AuditLogEntry e) {
    switch (_auditFilter) {
      case _AuditFilter.all:
        return true;
      case _AuditFilter.security:
        return _isSecurityEvent(e.event);
      case _AuditFilter.backup:
        return _isBackupEvent(e.event);
      case _AuditFilter.errors:
        return e.status.trim().toLowerCase() != 'ok';
    }
  }

  bool _isBackupEvent(String event) {
    return event.startsWith('backup_');
  }

  bool _isSecurityEvent(String event) {
    switch (event) {
      case 'owner_auth':
      case 'owner_auth_panic':
      case 'conversation_unlock':
      case 'conversation_lock':
      case 'panic_activate':
      case 'panic_clear':
      case 'pin_set':
      case 'panic_pin_set':
      case 'hidden_pin_set':
      case 'hidden_pin_recover':
      case 'hidden_pin_lockout':
      case 'security_reset':
        return true;
      default:
        return false;
    }
  }

  Widget _filterChip(_AuditFilter filter, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _auditFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _busy
          ? null
          : (_) {
              setState(() => _auditFilter = filter);
            },
      selectedColor: scheme.primary.withAlpha((0.20 * 255).round()),
      labelStyle: TextStyle(
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: scheme.surface,
      side: BorderSide(color: scheme.outlineVariant.withAlpha((0.45 * 255).round())),
    );
  }

  Widget _langChip(String mode, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _coverSettings?.languageMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _busy || _coverSettings == null
          ? null
          : (_) {
              _setCoverSettings(
                _coverSettings!.copyWith(languageMode: mode),
              );
            },
      selectedColor: scheme.primary.withAlpha((0.20 * 255).round()),
      labelStyle: TextStyle(
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: scheme.surface,
      side: BorderSide(color: scheme.outlineVariant.withAlpha((0.45 * 255).round())),
    );
  }

  String _deviceLang() {
    try {
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      return locale.languageCode.toLowerCase() == 'it' ? 'it' : 'en';
    } catch (_) {
      return 'en';
    }
  }
}

class _GesturePadPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final Color grid;

  _GesturePadPainter({
    required this.points,
    required this.color,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = grid.withAlpha((0.18 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final step = size.width / 3;
    for (var i = 1; i < 3; i++) {
      final dx = step * i;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), bg);
      canvas.drawLine(Offset(0, dx), Offset(size.width, dx), bg);
    }

    if (points.length < 2) return;
    final path = Path();
    final first = Offset(
      points.first.dx * size.width,
      points.first.dy * size.height,
    );
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      path.lineTo(p.dx, p.dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GesturePadPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

enum _AuditFilter {
  all,
  security,
  backup,
  errors,
}

class _IncomingTest {
  final Contact contact;
  final String text;
  final bool hidden;

  const _IncomingTest({
    required this.contact,
    required this.text,
    required this.hidden,
  });
}
