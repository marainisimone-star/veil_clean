import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../data/conversation_store.dart';
import '../data/local_storage.dart';
import '../data/message_repository.dart' as msgs;
import '../models/conversation.dart';
import '../routes/app_routes.dart';
import '../services/attachment_store.dart';

enum BottomNavTab {
  profile,
  calls,
  chats,
  contacts,
  calendar,
  camera,
}

class BottomNavStrip extends StatefulWidget {
  const BottomNavStrip({
    super.key,
    required this.current,
  });

  final BottomNavTab current;

  @override
  State<BottomNavStrip> createState() => _BottomNavStripState();
}

class _BottomNavStripState extends State<BottomNavStrip> {
  final ImagePicker _imagePicker = ImagePicker();
  final ConversationStore _convs = ConversationStore();
  final msgs.MessageRepository _repo = msgs.MessageRepository();
  final JitsiMeet _jitsi = JitsiMeet();

  String? _ownerName;
  String? _ownerPhotoB64;

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
  }

  void _loadOwnerProfile() {
    final name = LocalStorage.getString('veil_owner_name_v1');
    final photo = LocalStorage.getString('veil_owner_photo_b64_v1');
    setState(() {
      _ownerName = (name == null || name.trim().isEmpty) ? null : name.trim();
      _ownerPhotoB64 = (photo == null || photo.trim().isEmpty) ? null : photo.trim();
    });
  }

  ImageProvider? _ownerAvatarImage() {
    final raw = _ownerPhotoB64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  String _ownerInitials() {
    final name = (_ownerName ?? 'Owner').trim();
    if (name.isEmpty) return 'O';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return name[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _goTo(String route) {
    Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
  }

  Future<XFile?> _pickImage(ImageSource source) async {
    try {
      return await _imagePicker.pickImage(source: source);
    } catch (_) {
      return null;
    }
  }

  String _photoFileName(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'photo_$y$m${d}_$hh$mm.jpg';
  }

  Future<void> _cameraFlow() async {
    bool supported = Platform.isAndroid || Platform.isIOS;
    try {
      supported = supported && _imagePicker.supportsImageSource(ImageSource.camera);
    } catch (_) {}

    XFile? xf;
    if (supported) {
      xf = await _pickImage(ImageSource.camera);
    } else {
      _toast('Camera not supported on desktop. Using gallery.');
      xf = await _pickImage(ImageSource.gallery);
    }
    if (xf == null) return;
    if (!mounted) return;

    final action = await showModalBottomSheet<_CameraAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Send in Veil'),
                onTap: () => Navigator.pop(ctx, _CameraAction.sendVeil),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () => Navigator.pop(ctx, _CameraAction.share),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    switch (action) {
      case _CameraAction.sendVeil:
        await _sendPhotoToVeil(xf);
        break;
      case _CameraAction.share:
        await _sharePhoto(xf);
        break;
    }
  }

  Future<void> _callFlow() async {
    final convs = await _convs.getAllSorted();
    if (!mounted) return;
    if (convs.isEmpty) {
      _toast('No conversations yet.');
      return;
    }
    final picked = await _pickConversation(convs);
    if (picked == null) return;
    if (!mounted) return;

    final action = await showModalBottomSheet<_CallAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Audio call'),
                onTap: () => Navigator.pop(ctx, _CallAction.audio),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video call'),
                onTap: () => Navigator.pop(ctx, _CallAction.video),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    await _startJitsiCall(
      conversationId: picked.id,
      title: picked.title,
      video: action == _CallAction.video,
    );
  }

  Future<void> _startJitsiCall({
    required String conversationId,
    required String title,
    required bool video,
  }) async {
    final room = 'veil_$conversationId';
    final displayName = (_ownerName ?? '').trim().isEmpty ? 'Veil User' : _ownerName!.trim();
    final url = 'https://meet.jit.si/$room';

    if (!(Platform.isAndroid || Platform.isIOS)) {
      await _openExternalUrl(url);
      return;
    }

    final options = JitsiMeetConferenceOptions(
      room: room,
      serverURL: 'https://meet.jit.si',
      userInfo: JitsiMeetUserInfo(displayName: displayName),
      configOverrides: {
        'startWithVideoMuted': !video,
        'startWithAudioMuted': false,
        'subject': title.trim().isEmpty ? 'Veil Call' : title.trim(),
      },
      featureFlags: {
        'welcomepage.enabled': false,
        'prejoinpage.enabled': true,
      },
    );

    try {
      await _jitsi.join(options);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not start call.');
    }
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      _toast('Opening call in browser...');
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
      }
    } catch (_) {
      if (!mounted) return;
      _toast('Could not open browser.');
    }
  }

  Future<void> _scheduleCallFlow() async {
    final convs = await _convs.getAllSorted();
    if (!mounted) return;
    if (convs.isEmpty) {
      _toast('No conversations yet.');
      return;
    }

    final picked = await _pickConversation(convs);
    if (picked == null) return;

    if (!mounted) return;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30))),
    );
    if (time == null) return;

    if (!mounted) return;
    final title = await _promptTextInput(title: 'Call title', hint: 'Title');
    if (title == null || title.trim().isEmpty) return;

    if (!mounted) return;
    final external = await _promptTextInput(
      title: 'External invite (optional)',
      hint: 'Email or name',
    );

    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final end = start.add(const Duration(hours: 1));
    final room = 'veil_${picked.id}';
    final joinUrl = 'https://meet.jit.si/$room';

    final ics = _buildIcsEvent(
      title: title.trim(),
      start: start,
      end: end,
      location: joinUrl,
      notes: 'Join: $joinUrl',
      externalInvitee: (external ?? '').trim(),
    );

    final fileName = _safeFileName(
      'veil_call_${_timestampSlug(start)}.ics',
      fallback: 'veil_call.ics',
    );

    if (!mounted) return;
    final action = await showModalBottomSheet<_ScheduleAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Send in Veil'),
                onTap: () => Navigator.pop(ctx, _ScheduleAction.sendVeil),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share invite'),
                onTap: () => Navigator.pop(ctx, _ScheduleAction.share),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Save invite (.ics)'),
                onTap: () => Navigator.pop(ctx, _ScheduleAction.save),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    final joinText = 'Join Veil call: $joinUrl';

    if (action == _ScheduleAction.sendVeil) {
      final att = await AttachmentStore.importFromBytes(
        conversationId: picked.id,
        bytes: utf8.encode(ics),
        fileName: fileName,
        mimeType: 'text/calendar',
      );
      if (!mounted) return;
      if (att == null) {
        _toast('Could not attach invite.');
        return;
      }
      await _repo.sendMessage(
        conversationId: picked.id,
        text: joinText,
        isMe: true,
        attachmentRef: att,
      );
      if (!mounted) return;
      _toast('Invite sent.');
      return;
    }

    if (action == _ScheduleAction.save) {
      final dir = await Directory.systemTemp.createTemp('veil_invite_');
      final path = '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(ics), flush: true);
      await OpenFilex.open(path);
      // Best-effort cleanup
      try {
        if (await file.exists()) {
          await file.delete();
        }
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
      return;
    }

    final dir = await Directory.systemTemp.createTemp('veil_invite_');
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    await file.writeAsBytes(utf8.encode(ics), flush: true);

    await Share.shareXFiles(
      [XFile(path, mimeType: 'text/calendar', name: fileName)],
      text: '${title.trim()}\n$joinText',
    );

    try {
      if (await file.exists()) {
        await file.delete();
      }
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<String?> _promptTextInput({
    required String title,
    required String hint,
  }) async {
    var value = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            decoration: InputDecoration(hintText: hint),
            onChanged: (v) => value = v,
            onSubmitted: (_) => Navigator.pop(dctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, value),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _timestampSlug(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm';
  }

  String _safeFileName(String input, {String fallback = 'file'}) {
    final base = input.trim();
    if (base.isEmpty) return fallback;
    final sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _buildIcsEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? location,
    String? notes,
    String? externalInvitee,
  }) {
    final uid = 'veil_${DateTime.now().millisecondsSinceEpoch}@veil';
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Veil//EN',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:${_formatIcsDate(DateTime.now())}',
      'DTSTART:${_formatIcsDate(start)}',
      'DTEND:${_formatIcsDate(end)}',
      'SUMMARY:${_icsEscape(title)}',
    ];
    final loc = (location ?? '').trim();
    if (loc.isNotEmpty) {
      lines.add('LOCATION:${_icsEscape(loc)}');
    }
    final desc = (notes ?? '').trim();
    if (desc.isNotEmpty) {
      lines.add('DESCRIPTION:${_icsEscape(desc)}');
    }
    final invitee = (externalInvitee ?? '').trim();
    if (invitee.isNotEmpty) {
      lines.add('ATTENDEE;CN=${_icsEscape(invitee)}:MAILTO:$invitee');
    }
    lines.add('END:VEVENT');
    lines.add('END:VCALENDAR');
    return lines.join('\n');
  }

  String _formatIcsDate(DateTime dt) {
    final u = dt.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    final mm = u.minute.toString().padLeft(2, '0');
    final ss = u.second.toString().padLeft(2, '0');
    return '$y$m${d}T$hh$mm${ss}Z';
  }

  String _icsEscape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }

  Future<void> _sendPhotoToVeil(XFile xf) async {
    final convs = await _convs.getAllSorted();
    if (!mounted) return;
    if (convs.isEmpty) {
      _toast('No conversations yet.');
      return;
    }

    final picked = await _pickConversation(convs);
    if (picked == null) return;

    final bytes = await xf.readAsBytes();
    if (bytes.isEmpty) {
      _toast('Empty photo.');
      return;
    }

    final fileName = _photoFileName(DateTime.now());
    final att = await AttachmentStore.importFromBytes(
      conversationId: picked.id,
      bytes: bytes,
      fileName: fileName,
      mimeType: 'image/jpeg',
    );
    if (!mounted) return;
    if (att == null) {
      _toast('Could not attach photo.');
      return;
    }

    await _repo.sendMessage(
      conversationId: picked.id,
      text: '',
      isMe: true,
      attachmentRef: att,
    );

    if (!mounted) return;
    _toast('Photo sent.');
  }

  Future<void> _sharePhoto(XFile xf) async {
    final bytes = await xf.readAsBytes();
    if (bytes.isEmpty) {
      _toast('Empty photo.');
      return;
    }
    final fileName = _photoFileName(DateTime.now());
    final dir = await Directory.systemTemp.createTemp('veil_share_');
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(path, mimeType: 'image/jpeg', name: fileName)],
      text: 'Photo',
    );

    try {
      if (await file.exists()) {
        await file.delete();
      }
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<Conversation?> _pickConversation(List<Conversation> convs) async {
    return showDialog<Conversation>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Send to'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: ListView.builder(
              itemCount: convs.length,
              itemBuilder: (_, i) {
                final c = convs[i];
                final title = c.title.trim().isEmpty ? 'Conversation' : c.title.trim();
                return ListTile(
                  title: Text(title, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, c),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());

    Widget bubble({
      required Widget child,
      required VoidCallback onTap,
      String? tooltip,
      bool selected = false,
    }) {
      return Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withAlpha((0.12 * 255).round())
                  : scheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? scheme.primary : border,
              ),
            ),
            child: Center(child: child),
          ),
        ),
      );
    }

    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primary.withAlpha((0.12 * 255).round()),
      backgroundImage: _ownerAvatarImage(),
      child: _ownerAvatarImage() == null
          ? Text(_ownerInitials(), style: TextStyle(color: fg, fontSize: 12))
          : null,
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: border),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            bubble(
              child: avatar,
              tooltip: 'Profile',
              selected: widget.current == BottomNavTab.profile,
              onTap: () => _goTo(AppRoutes.onboarding),
            ),
            bubble(
              child: Icon(Icons.call_outlined, color: muted),
              tooltip: 'Call',
              selected: widget.current == BottomNavTab.calls,
              onTap: _callFlow,
            ),
            bubble(
              child: Icon(Icons.chat_bubble_outline, color: muted),
              tooltip: 'Chats',
              selected: widget.current == BottomNavTab.chats,
              onTap: () => _goTo(AppRoutes.inbox),
            ),
            bubble(
              child: Icon(Icons.people_outline, color: muted),
              tooltip: 'Contacts',
              selected: widget.current == BottomNavTab.contacts,
              onTap: () => _goTo(AppRoutes.contacts),
            ),
            bubble(
              child: Icon(Icons.calendar_today_outlined, color: muted),
              tooltip: 'Schedule call',
              selected: widget.current == BottomNavTab.calendar,
              onTap: _scheduleCallFlow,
            ),
            bubble(
              child: Icon(Icons.photo_camera_outlined, color: muted),
              tooltip: 'Camera',
              selected: widget.current == BottomNavTab.camera,
              onTap: _cameraFlow,
            ),
          ],
        ),
      ),
    );
  }
}

enum _CameraAction {
  sendVeil,
  share,
}

enum _ScheduleAction {
  sendVeil,
  share,
  save,
}

enum _CallAction {
  audio,
  video,
}
