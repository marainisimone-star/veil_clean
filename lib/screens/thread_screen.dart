import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/conversation_store.dart' as convs;
import '../data/contact_repository.dart';
import '../data/local_storage.dart';
import '../data/message_events.dart';
import '../data/message_repository.dart' as msgs;
import '../models/attachment_ref.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/group_member.dart';
import '../models/message.dart';
import '../security/secure_gate.dart';
import '../security/bubble_unlock_pattern.dart';
import '../security/unlock_profile.dart';
import '../security/unlock_service.dart';
import '../services/attachment_store.dart';
import '../services/draft_store.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/hidden_panel.dart';
import '../widgets/bottom_nav_strip.dart';
import '../services/firebase_backend.dart';
import '../services/remote_backend.dart';

class ThreadScreen extends StatefulWidget {
  final Conversation conversation;

  const ThreadScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with WidgetsBindingObserver {
  final msgs.MessageRepository _repo = msgs.MessageRepository();
  final _unlock = UnlockService();
  final convs.ConversationStore _convs = convs.ConversationStore();
  final ContactRepository _contactsRepo = ContactRepository();
  final JitsiMeet _jitsi = JitsiMeet();

  final _composerCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Message> _messages = const [];
  bool _loading = true;

  StreamSubscription<MessageEvent>? _sub;
  StreamSubscription<RemoteMessage>? _remoteSub;

  DateTime? _threadUnlockedUntil;
  final Map<String, String> _realCacheByMsgId = {}; // msgId -> real text

  int? _messageTtlMinutes;
  bool _conversationHidden = false;
  bool _isGroup = false;
  UnlockProfile _unlockProfile = UnlockProfile.defaults();
  BubbleUnlockPattern _bubbleUnlockPattern = const BubbleUnlockPattern(<int>[]);
  final List<int> _bubblePatternInput = [];
  Timer? _bubblePatternTimer;
  int? _lastPatternCell;
  DateTime? _lastPatternAt;
  final List<Offset> _bubbleGestureInput = [];

  Timer? _draftTimer;
  Timer? _holdTimer;
  Offset? _holdStartPos;
  bool _holdTriggered = false;

  bool _ignoreDraftChanges = false;

  final bool _authUiOpen = false;
  bool _hiddenPanelOpen = false;

  double _pullDistance = 0;
  bool _pullTriggered = false;
  Timer? _pullWheelReset;

  AttachmentRef? _pendingAttachment;
  bool _sendHiddenNext = false;

  Timer? _scrollDebounce;
  String? _ownerName;
  String? _ownerPhotoB64;
  Contact? _threadContact;
  final Map<String, Contact> _memberContacts = {};

  bool get _threadUnlocked {
    final until = _threadUnlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _composerCtrl.addListener(_onDraftChanged);

    _loadInitial();
    _loadDraft();
    _loadConversationMeta();
    _loadUnlockProfile();
    _loadBubbleUnlockPattern();
    _loadOwnerProfile();
    _loadThreadContact();
    _subscribeLive();
    _subscribeRemote();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _saveDraftNow();

    _sub?.cancel();
    _remoteSub?.cancel();
    _draftTimer?.cancel();
    _composerCtrl.dispose();
    _scrollController.dispose();

    _holdTimer?.cancel();
    _bubblePatternTimer?.cancel();
    _scrollDebounce?.cancel();
    _pullWheelReset?.cancel();

    super.dispose();
  }

  Future<void> _loadConversationMeta() async {
    final c = await _convs.getById(widget.conversation.id);
    if (!mounted) return;
    setState(() {
      _messageTtlMinutes = c?.messageTtlMinutes;
      _conversationHidden = c?.isHidden ?? false;
      _isGroup = c?.isGroup == true;
    });
    if (c?.isGroup == true) {
      await _loadMemberContacts(c?.groupMembers ?? const []);
    }
  }

  Future<void> _loadThreadContact() async {
    try {
      final cid = widget.conversation.contactId;
      if (cid == null || cid.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _threadContact = null);
        return;
      }
      final c = await _contactsRepo.getById(cid);
      if (!mounted) return;
      setState(() => _threadContact = c);
    } catch (_) {}
  }

  Future<void> _loadMemberContacts(List<GroupMember> members) async {
    final ids = members
        .map((m) => m.id)
        .where((id) => id.startsWith('c_'))
        .map((id) => id.substring(2))
        .toSet();

    final Map<String, Contact> next = {};
    for (final id in ids) {
      try {
        final c = await _contactsRepo.getById(id);
        if (c != null) {
          next[id] = c;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _memberContacts
        ..clear()
        ..addAll(next);
    });
  }
  Future<void> _loadUnlockProfile() async {
    final profile = await UnlockProfile.load();
    if (!mounted) return;
    setState(() => _unlockProfile = profile);
  }

  Future<void> _loadBubbleUnlockPattern() async {
    final pattern = await BubbleUnlockPattern.load();
    if (!mounted) return;
    setState(() => _bubbleUnlockPattern = pattern);
  }

  Future<void> _loadOwnerProfile() async {
    final name = LocalStorage.getString('veil_owner_name_v1');
    final photo = LocalStorage.getString('veil_owner_photo_b64_v1');
    if (!mounted) return;
    setState(() {
      _ownerName = (name == null || name.trim().isEmpty) ? null : name.trim();
      _ownerPhotoB64 = (photo == null || photo.trim().isEmpty) ? null : photo.trim();
    });
  }

  Future<void> _loadDraft() async {
    final draft = await DraftStore.I.loadDraft(conversationId: widget.conversation.id);
    if (!mounted) return;
    if (draft == null || draft.trim().isEmpty) return;

    _ignoreDraftChanges = true;
    _composerCtrl.text = draft;
    _composerCtrl.selection = TextSelection.collapsed(offset: draft.length);
    _ignoreDraftChanges = false;
  }

  void _saveDraftNow() {
    if (_ignoreDraftChanges) return;
    final text = _composerCtrl.text;
    if (text.trim().isEmpty) {
      DraftStore.I.clearDraft(conversationId: widget.conversation.id);
    } else {
      DraftStore.I.saveDraft(
        conversationId: widget.conversation.id,
        text: text,
      );
    }
  }

  void _onDraftChanged() {
    if (_ignoreDraftChanges) return;

    _draftTimer?.cancel();
    final text = _composerCtrl.text;

    if (text.trim().isEmpty) {
      _draftTimer = Timer(const Duration(milliseconds: 250), () {
        DraftStore.I.clearDraft(conversationId: widget.conversation.id);
      });
      return;
    }

    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      DraftStore.I.saveDraft(
        conversationId: widget.conversation.id,
        text: text,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (SecureGate.isAuthInProgress || _authUiOpen) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveDraftNow();
      _lockWholeThreadNow();
      if (_hiddenPanelOpen && mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _loadInitial() async {
    final msgsList = await _repo.getMessages(widget.conversation.id);
    if (!mounted) return;

    setState(() {
      _messages = List<Message>.from(msgsList);
      _loading = false;
    });

    _scheduleScrollToBottom();

    // If remote messages marked hidden, keep conversation hidden state in sync.
    try {
      final c = await _convs.getById(widget.conversation.id);
      if (!mounted) return;
      if (c?.isHidden == true) {
        setState(() => _conversationHidden = true);
      }
    } catch (_) {}
  }

  Future<void> _reload() async {
    final msgsList = await _repo.getMessages(widget.conversation.id);
    if (!mounted) return;

    setState(() => _messages = List<Message>.from(msgsList));
    _scheduleScrollToBottom();
  }

  void _subscribeLive() {
    _sub = _repo.events.listen((event) async {
      if (!mounted) return;
      if (event.message.conversationId != widget.conversation.id) return;

      setState(() {
        if (event.type == MessageEventType.added) {
          _messages = [..._messages, event.message];
        } else {
          _messages = _messages
              .map((m) => (m.id == event.message.id) ? event.message : m)
              .toList(growable: false);
        }
      });

      if (_threadUnlocked && event.type == MessageEventType.added) {
        await _prefetchRealForMessage(event.message);
        if (mounted) setState(() {});
      }

      _scheduleScrollToBottom();
    });
  }

  Future<void> _subscribeRemote() async {
    final firebaseSupported = Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows;
    if (!firebaseSupported) return;

    await FirebaseBackend.I.init();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _remoteSub = FirebaseBackend.I
        .messagesStream(conversationId: widget.conversation.id)
        .listen((rm) async {
      if (!mounted) return;
      if (rm.senderId == uid) return;

      final added = await _repo.ingestRemoteMessage(rm);
      if (!added) return;
      if (!mounted) return;
      await _reload();
    });
  }

  Future<void> _pickAttachment() async {
    if (Platform.isAndroid) {
      final source = await showDialog<_AttachmentPickSource>(
        context: context,
        barrierDismissible: true,
        builder: (dctx) {
          return AlertDialog(
            title: const Text('Attach file'),
            content: const Text(
              'Pick a file from Downloads or open the system picker.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(dctx, _AttachmentPickSource.downloads),
                child: const Text('Downloads'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(dctx, _AttachmentPickSource.systemPicker),
                child: const Text('System picker'),
              ),
            ],
          );
        },
      );
      if (source == null) return;
      if (source == _AttachmentPickSource.downloads) {
        await _pickAttachmentFromDownloads();
        return;
      }
    }

    final att = await AttachmentStore.importFromPicker(conversationId: widget.conversation.id);
    if (!mounted) return;
    if (att == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file selected.')),
      );
      return;
    }

    setState(() => _pendingAttachment = att);
  }

  Future<void> _openAttachmentMenu() async {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    final selection = await showModalBottomSheet<_AttachAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Photo'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.photo),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Camera Roll'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.cameraRoll),
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Location'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.location),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Contact'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.contact),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share Contact'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.shareContact),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: const Text('Document'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.document),
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Calendar Event'),
                  onTap: () => Navigator.pop(ctx, _AttachAction.calendarEvent),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Attachments are encrypted before sending.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selection == null) return;
    switch (selection) {
      case _AttachAction.photo:
        await _pickPhotoFromCamera();
        break;
      case _AttachAction.cameraRoll:
        await _pickPhotoFromGallery();
        break;
      case _AttachAction.location:
        await _pickLocation();
        break;
      case _AttachAction.contact:
        await _pickContact();
        break;
      case _AttachAction.shareContact:
        await _shareContactExternally();
        break;
      case _AttachAction.document:
        await _pickAttachment();
        break;
      case _AttachAction.calendarEvent:
        await _pickCalendarEvent();
        break;
    }
  }

  Future<void> _pickAttachmentFromDownloads() async {
    final files = await AttachmentStore.listDownloadFiles();
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files found in Downloads.')),
      );
      return;
    }

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
              itemCount: files.length,
              itemBuilder: (_, i) {
                final f = files[i];
                final stat = f.statSync();
                final name = f.path.split(Platform.pathSeparator).last;
                final subtitle =
                    '${_formatDate(stat.modified)} ${_formatTime(stat.modified)} · ${_formatBytes(stat.size)}';
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

    final att = await AttachmentStore.importFromPath(
      conversationId: widget.conversation.id,
      path: pickedPath,
    );
    if (!mounted) return;
    if (att == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load file.')),
      );
      return;
    }

    setState(() => _pendingAttachment = att);
  }

  Future<void> _attachBytes({
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    if (bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empty attachment.')),
      );
      return;
    }

    final att = await AttachmentStore.importFromBytes(
      conversationId: widget.conversation.id,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    if (!mounted) return;
    if (att == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach file.')),
      );
      return;
    }

    setState(() => _pendingAttachment = att);
  }

  String _xFileName(XFile xf, {String fallback = 'file'}) {
    final name = xf.name.trim();
    if (name.isNotEmpty) return name;
    final path = xf.path.trim();
    if (path.isNotEmpty) {
      final parts = path.split(Platform.pathSeparator);
      if (parts.isNotEmpty) return parts.last;
    }
    return fallback;
  }

  Future<void> _pickPhotoFromGallery() async {
    try {
      final xf = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (xf == null) return;
      final bytes = await xf.readAsBytes();
      final name = _xFileName(xf, fallback: 'photo.jpg');
      await _attachBytes(bytes: bytes, fileName: name, mimeType: 'image/jpeg');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick photo.')),
      );
    }
  }

  Future<void> _pickPhotoFromCamera() async {
    try {
      bool supported = Platform.isAndroid || Platform.isIOS;
      try {
        supported = supported && _imagePicker.supportsImageSource(ImageSource.camera);
      } catch (_) {}

      if (!supported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not supported here. Picking from gallery instead.')),
        );
        await _pickPhotoFromGallery();
        return;
      }

      final xf = await _imagePicker.pickImage(source: ImageSource.camera);
      if (xf == null) return;
      final bytes = await xf.readAsBytes();
      final name = _xFileName(xf, fallback: 'photo.jpg');
      await _attachBytes(bytes: bytes, fileName: name, mimeType: 'image/jpeg');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not use camera.')),
      );
    }
  }

  Future<void> _pickLocation() async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location is not supported on desktop.')),
        );
        return;
      }

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final ts = DateTime.now();
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      final mapUrl = 'https://maps.google.com/?q=$lat,$lng';
      final body = [
        'Location: $lat, $lng',
        'Time: ${ts.toIso8601String()}',
        'Map: $mapUrl',
      ].join('\n');

      final fileName = _safeFileName('location_${_timestampSlug(ts)}.txt');
      await _attachBytes(
        bytes: utf8.encode(body),
        fileName: fileName,
        mimeType: 'text/plain',
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location timeout. Try again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get location.')),
      );
    }
  }

  Future<void> _pickContact() async {
    try {
      final contacts = await _contactsRepo.getAll();
      if (!mounted) return;
      if (contacts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app contacts found.')),
        );
        return;
      }

      if (!mounted) return;
      final picked = await _showAppContactPicker(contacts);
      if (picked == null) return;

      final vcard = _buildVCardFromAppContact(picked);
      final displayName = _displayNameForAppContact(picked);
      final fileName = _safeFileName(
        'contact_${displayName.isEmpty ? 'contact' : displayName}.vcf',
        fallback: 'contact.vcf',
      );
      await _attachBytes(
        bytes: utf8.encode(vcard),
        fileName: fileName,
        mimeType: 'text/x-vcard',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load app contacts.')),
      );
    }
  }

  Future<void> _shareContactExternally() async {
    try {
      final contacts = await _contactsRepo.getAll();
      if (!mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app contacts found.')),
        );
        return;
      }

      final picked = await _showAppContactPicker(contacts);
      if (picked == null) return;

      final vcard = _buildVCardFromAppContact(picked);
      final displayName = _displayNameForAppContact(picked);
      final fileName = _safeFileName(
        'contact_${displayName.isEmpty ? 'contact' : displayName}.vcf',
        fallback: 'contact.vcf',
      );

      final dir = await Directory.systemTemp.createTemp('veil_share_');
      final path = '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(vcard), flush: true);

      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/x-vcard', name: fileName)],
        text: displayName.isEmpty ? 'Contact' : displayName,
      );

      // Best-effort cleanup
      try {
        if (await file.exists()) {
          await file.delete();
        }
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share contact.')),
      );
    }
  }

  Future<Contact?> _showAppContactPicker(List<Contact> contacts) async {
    final sorted = List<Contact>.from(contacts)
      ..sort((a, b) {
        final ad = _displayNameForAppContact(a).toLowerCase();
        final bd = _displayNameForAppContact(b).toLowerCase();
        return ad.compareTo(bd);
      });

    return showDialog<Contact>(
      context: context,
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = filter.trim().isEmpty
                ? sorted
                : sorted
                    .where((c) =>
                        _displayNameForAppContact(c).toLowerCase().contains(filter.toLowerCase()))
                    .toList(growable: false);
            return AlertDialog(
              title: const Text('Pick a contact'),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search',
                      ),
                      onChanged: (v) => setLocal(() => filter = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final displayName = _displayNameForAppContact(c);
                          return ListTile(
                            title: Text(displayName.isNotEmpty ? displayName : '(No name)'),
                            onTap: () => Navigator.pop(ctx, c),
                          );
                        },
                      ),
                    ),
                  ],
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
      },
    );
  }

  String _displayNameForAppContact(Contact c) {
    final real = (c.realName ?? '').trim();
    if (real.isNotEmpty) return real;
    final first = (c.firstName ?? '').trim();
    final last = (c.lastName ?? '').trim();
    final combined = [first, last].where((s) => s.isNotEmpty).join(' ').trim();
    if (combined.isNotEmpty) return combined;
    return c.coverName.trim();
  }

  String _buildVCardFromAppContact(Contact c) {
    final fullName = _displayNameForAppContact(c);
    final first = (c.firstName ?? '').trim();
    final last = (c.lastName ?? '').trim();
    final phones = <String>[
      if ((c.phone ?? '').trim().isNotEmpty) c.phone!.trim(),
    ];
    final emails = <String>[
      if ((c.email ?? '').trim().isNotEmpty) c.email!.trim(),
    ];

    return _buildVCardFromFields(
      fullName: fullName.isNotEmpty ? fullName : 'Contact',
      firstName: first,
      lastName: last,
      phones: phones,
      emails: emails,
    );
  }

  String _buildVCardFromFields({
    required String fullName,
    required String firstName,
    required String lastName,
    required List<String> phones,
    required List<String> emails,
  }) {
    final safeFull = _vCardEscape(fullName);
    final safeFirst = _vCardEscape(firstName);
    final safeLast = _vCardEscape(lastName);

    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'FN:$safeFull',
      'N:$safeLast;$safeFirst;;;',
    ];

    for (final p in phones) {
      lines.add('TEL;TYPE=CELL:${_vCardEscape(p)}');
    }
    for (final e in emails) {
      lines.add('EMAIL;TYPE=HOME:${_vCardEscape(e)}');
    }

    lines.add('END:VCARD');
    return lines.join('\n');
  }

  String _vCardEscape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }

  Future<void> _pickCalendarEvent() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
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
    final title = await _promptTextInput(title: 'Event title', hint: 'Title');
    if (title == null || title.trim().isEmpty) return;

    if (!mounted) return;
    final location = await _promptTextInput(title: 'Location (optional)', hint: 'Location');
    if (!mounted) return;
    final notes = await _promptTextInput(title: 'Notes (optional)', hint: 'Notes');

    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final end = start.add(const Duration(hours: 1));

    final ics = _buildIcsEvent(
      title: title.trim(),
      start: start,
      end: end,
      location: (location ?? '').trim(),
      notes: (notes ?? '').trim(),
    );

    final fileName = _safeFileName('event_${_timestampSlug(start)}.ics', fallback: 'event.ics');
    await _attachBytes(
      bytes: utf8.encode(ics),
      fileName: fileName,
      mimeType: 'text/calendar',
    );
  }

  String _buildIcsEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? location,
    String? notes,
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

  Future<void> _send() async {
    final text = _composerCtrl.text.trim();
    final att = _pendingAttachment;

    if (text.isEmpty && att == null) return;

    _composerCtrl.clear();
    setState(() => _pendingAttachment = null);
    final hiddenOverride = _sendHiddenNext;
    _sendHiddenNext = false;
    await DraftStore.I.clearDraft(conversationId: widget.conversation.id);

    await _repo.sendMessage(
      conversationId: widget.conversation.id,
      text: text,
      isMe: true,
      attachmentRef: att,
      hiddenOverride: hiddenOverride,
    );

    try {
      final latest = await _repo.getMessages(widget.conversation.id);
      if (latest.isNotEmpty) {
        final last = latest.last;
        final safePreview = (last.coverText.trim().isNotEmpty)
            ? last.coverText.trim()
            : (last.text.trim().isNotEmpty ? last.text.trim() : ' ');
        await _convs.updateLastMessage(
          conversationId: widget.conversation.id,
          lastMessage: safePreview,
          when: DateTime.now(),
        );
      }
    } catch (_) {}
  }
  void _scheduleScrollToBottom() {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 120), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.userScrollDirection != ScrollDirection.idle) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _prefetchRealForMessage(Message m) async {
    if (_realCacheByMsgId.containsKey(m.id)) return;

    try {
      final clear = await _repo.revealRealText(m);
      final out = (clear ?? '').trim();
      if (out.isEmpty) return;
      _realCacheByMsgId[m.id] = out;
    } catch (_) {}
  }

  Future<void> _prefetchAllReal() async {
    for (final m in _messages) {
      await _prefetchRealForMessage(m);
    }
  }

  Future<void> _startCall({required bool video}) async {
    final room = 'veil_${widget.conversation.id}';
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
        'subject': widget.conversation.title.trim().isEmpty
            ? 'Veil Call'
            : widget.conversation.title.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start call.')),
      );
    }
  }

  Future<void> _unlockWholeThread({Duration ttl = const Duration(minutes: 5)}) async {
    SecureGate.unlockSession();
    SecureGate.unlockConversation(widget.conversation.id);

    await _unlock.unlockConversation(widget.conversation.id);

    _threadUnlockedUntil = DateTime.now().add(ttl);

    await _prefetchAllReal();
    await _loadDraft();

    if (!mounted) return;

    setState(() {});
    await _reload();
  }

  Future<void> _lockWholeThreadNow() async {
    try {
      await _unlock.lockConversation(widget.conversation.id);
    } catch (_) {}

    SecureGate.lockConversation(widget.conversation.id);

    _threadUnlockedUntil = null;
    _realCacheByMsgId.clear();

    if (!mounted) return;
    setState(() {});
  }

  String _displayText(Message m) {
    if (_threadUnlocked) {
      final real = _realCacheByMsgId[m.id];
      if (real != null && real.trim().isNotEmpty) return real;
    }
    final cover = m.coverText.trim();
    return cover.isEmpty ? m.text : cover;
  }

  void _startHoldTimer(Offset position, PointerDeviceKind kind, int buttons) {
    if (!_unlockProfile.holdToUnlock) return;

    if (kind == PointerDeviceKind.mouse && buttons != kPrimaryMouseButton) {
      return;
    }

    _holdStartPos = position;
    _holdTriggered = false;

    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(seconds: 3), () {
      _holdTimer = null;
      _holdTriggered = true;
      if (!_threadUnlocked) {
        _unlockWholeThread(ttl: const Duration(minutes: 5));
      }
    });
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartPos = null;
    _holdTriggered = false;
  }

  void _onHoldPointerMove(Offset position) {
    final start = _holdStartPos;
    if (start == null) return;
    if (_holdTriggered) return;
    final dx = position.dx - start.dx;
    final dy = position.dy - start.dy;
    if ((dx * dx + dy * dy) > 144) {
      _cancelHoldTimer();
    }
  }

  void _onHoldPointerUp() {
    if (_holdTriggered) {
      _holdTriggered = false;
      _holdStartPos = null;
      return;
    }
    _cancelHoldTimer();
  }

  void _onBubbleTap(String msgId) {
    // Legacy tap patterns disabled in favor of custom bubble signal.
    return;
  }

  void _onBubblePatternInput(Offset localPos, BuildContext ctx) {
    if (!_bubbleUnlockPattern.isSet) return;
    if (_threadUnlocked) return;
    if (_bubbleUnlockPattern.isGesture) return;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    if (size.isEmpty) return;

    final cell = _cellFromOffset(localPos, size);
    if (cell == null) return;

    final now = DateTime.now();
    final lastCell = _lastPatternCell;
    final lastAt = _lastPatternAt;
    final sameCell = lastCell == cell;
    final tooSoon = lastAt != null && now.difference(lastAt).inMilliseconds < 140;

    if (!sameCell || !tooSoon) {
      _bubblePatternInput.add(cell);
      if (_bubblePatternInput.length > _bubbleUnlockPattern.sequence.length) {
        _bubblePatternInput.removeAt(0);
      }
      _lastPatternCell = cell;
      _lastPatternAt = now;
    }

    _bubblePatternTimer?.cancel();
    _bubblePatternTimer = Timer(const Duration(milliseconds: 2400), () {
      _bubblePatternInput.clear();
      _lastPatternCell = null;
      _lastPatternAt = null;
    });

    if (_matchesBubblePattern()) {
      _bubblePatternInput.clear();
      _bubblePatternTimer?.cancel();
      _bubblePatternTimer = null;
      _unlockWholeThread(ttl: const Duration(minutes: 5));
    }
  }

  void _onBubbleGestureStart(Offset localPos, BuildContext ctx) {
    if (!_bubbleUnlockPattern.isGesture) return;
    if (_threadUnlocked) return;
    _bubbleGestureInput.clear();
    _addGesturePoint(localPos, ctx);
  }

  void _onBubbleGestureUpdate(Offset localPos, BuildContext ctx) {
    if (!_bubbleUnlockPattern.isGesture) return;
    if (_threadUnlocked) return;
    _addGesturePoint(localPos, ctx);
  }

  void _onBubbleGestureEnd() {
    if (!_bubbleUnlockPattern.isGesture) return;
    if (_threadUnlocked) return;
    if (_bubbleGestureInput.length < 6) return;
    if (_matchGesture(_bubbleUnlockPattern.path, _bubbleGestureInput)) {
      _bubbleGestureInput.clear();
      _unlockWholeThread(ttl: const Duration(minutes: 5));
    }
  }

  void _addGesturePoint(Offset localPos, BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    if (size.isEmpty) return;
    final nx = (localPos.dx / size.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / size.height).clamp(0.0, 1.0);
    if (_bubbleGestureInput.isNotEmpty) {
      final last = _bubbleGestureInput.last;
      final dx = (nx - last.dx).abs();
      final dy = (ny - last.dy).abs();
      if ((dx + dy) < 0.01) return;
    }
    _bubbleGestureInput.add(Offset(nx, ny));
  }

  bool _matchesBubblePattern() {
    final target = _normalizePattern(_bubbleUnlockPattern.sequence);
    final input = _normalizePattern(_bubblePatternInput);
    if (target.isEmpty || input.isEmpty) return false;
    if (input.length != target.length) return false;
    for (var i = 0; i < target.length; i++) {
      if (input[i] != target[i]) return false;
    }
    return true;
  }

  bool _matchGesture(List<Offset> a, List<Offset> b) {
    final aa = _resampleGesture(List<Offset>.from(a), 32);
    final bb = _resampleGesture(List<Offset>.from(b), 32);
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

  List<Offset> _resampleGesture(List<Offset> pts, int count) {
    if (pts.length < 2) return pts;
    final out = <Offset>[];
    final total = _gestureLength(pts);
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

  double _gestureLength(List<Offset> pts) {
    double sum = 0;
    for (var i = 1; i < pts.length; i++) {
      sum += (pts[i] - pts[i - 1]).distance;
    }
    return sum;
  }

  List<int> _normalizePattern(List<int> seq) {
    if (seq.isEmpty) return const [];
    final out = <int>[seq.first];
    for (var i = 1; i < seq.length; i++) {
      if (seq[i] != seq[i - 1]) out.add(seq[i]);
    }
    return out;
  }

  int? _cellFromOffset(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return null;
    final cellW = size.width / 3;
    final cellH = size.height / 3;
    final col = (local.dx / cellW).floor().clamp(0, 2);
    final row = (local.dy / cellH).floor().clamp(0, 2);
    return (row * 3 + col + 1).toInt();
  }

  Future<void> _confirmDeleteMessage(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => MediaQuery.removeViewInsets(
        context: dctx,
        removeBottom: true,
        child: AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('This will remove this bubble.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await _repo.deleteMessage(conversationId: widget.conversation.id, messageId: m.id);
    await _reload();
  }

  Future<void> _openManageMembers() async {
    final c = await _convs.getById(widget.conversation.id);
    if (c == null) return;
    if (!mounted) return;

    final members = List<GroupMember>.from(c.groupMembers);
    if (members.every((m) => m.id != 'me')) {
      members.insert(0, const GroupMember(id: 'me', name: 'You', isAdmin: true));
    }

    final contacts = await ContactRepository().getAll();
    if (!mounted) return;

    final res = await showDialog<List<GroupMember>>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        final nameCtrl = TextEditingController();
        final searchCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void addMember() {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final member = GroupMember(
                id: _convs.newGroupMemberId(),
                name: name,
                isAdmin: false,
              );
              members.add(member);
              nameCtrl.clear();
              setLocal(() {});
            }

            bool isSelectedContact(Contact c) {
              final id = 'c_${c.id}';
              return members.any((m) => m.id == id);
            }

            void toggleContact(Contact c, bool selected) {
              final id = 'c_${c.id}';
              if (selected) {
                if (members.any((m) => m.id == id)) return;
                members.add(
                  GroupMember(
                    id: id,
                    name: c.coverName.trim().isEmpty ? 'Contact' : c.coverName.trim(),
                    isAdmin: false,
                  ),
                );
              } else {
                members.removeWhere((m) => m.id == id);
              }
              setLocal(() {});
            }

            final q = searchCtrl.text.trim().toLowerCase();
            final filtered = (q.isEmpty)
                ? contacts
                : contacts.where((c) {
                    final name = c.coverName.toLowerCase();
                    final phone = (c.phone ?? '').toLowerCase();
                    final real = (c.realName ?? '').toLowerCase();
                    return name.contains(q) || phone.contains(q) || real.contains(q);
                  }).toList(growable: false);

            return MediaQuery.removeViewInsets(
              context: dctx,
              removeBottom: true,
              child: AlertDialog(
                title: const Text('Members'),
                content: SizedBox(
                  width: 520,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(dctx).size.height * 0.7,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Current members',
                            style: TextStyle(color: Colors.black.withAlpha((0.55 * 255).round())),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (members.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('No members yet.'),
                          ),
                        ...members.map((m) {
                          final isMe = m.id == 'me';
                          return ListTile(
                            title: Text(m.name),
                            subtitle: Text(m.isAdmin ? 'Admin' : 'Member'),
                            trailing: isMe
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      members.removeWhere((x) => x.id == m.id);
                                      setLocal(() {});
                                    },
                                  ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Add from contacts',
                            style: TextStyle(color: Colors.black.withAlpha((0.55 * 255).round())),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: searchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search contacts…',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (_) => setLocal(() {}),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 220,
                          child: filtered.isEmpty
                              ? const Center(child: Text('No contacts.'))
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx2, idx) {
                                    final contact = filtered[idx];
                                    final selected = isSelectedContact(contact);
                                    return CheckboxListTile(
                                      value: selected,
                                      onChanged: (v) => toggleContact(contact, v == true),
                                      title: Text(contact.coverName.isEmpty ? 'Contact' : contact.coverName),
                                      subtitle: (contact.phone ?? '').isEmpty ? null : Text(contact.phone!),
                                      dense: true,
                                      controlAffinity: ListTileControlAffinity.leading,
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(hintText: 'Member name'),
                                onSubmitted: (_) => addMember(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: addMember, child: const Text('Add')),
                          ],
                        ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, List<GroupMember>.from(members)),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (res == null) return;

    await _convs.setGroupMembers(
      conversationId: widget.conversation.id,
      members: res,
    );

    if (!mounted) return;
    setState(() => _isGroup = true);
    await _loadMemberContacts(res);
  }

  Future<void> _openHiddenPanel() async {
    if (_authUiOpen) return;
    if (_hiddenPanelOpen) return;
    _hiddenPanelOpen = true;

    await HiddenPanel.show(
      context,
      conversationId: widget.conversation.id,
      title: widget.conversation.title,
      threadUnlocked: _threadUnlocked,
      onLockNow: _lockWholeThreadNow,
      onClearCache: () {
        _realCacheByMsgId.clear();
        if (mounted) setState(() {});
      },
      messageTtlMinutes: _messageTtlMinutes,
      onSetMessageTtl: (minutes) async {
        await _convs.setMessageTtl(
          conversationId: widget.conversation.id,
          minutes: minutes,
        );
        if (!mounted) return;
        setState(() => _messageTtlMinutes = minutes);
      },
      conversationHidden: _conversationHidden,
      onToggleConversationHidden: () async {
        final next = !_conversationHidden;
        await _convs.setHidden(conversationId: widget.conversation.id, hidden: next);
        if (!mounted) return;
        setState(() => _conversationHidden = next);
      },
      inboxHiddenView: null,
      onToggleInboxView: null,
      onManageMembers: _isGroup ? _openManageMembers : null,
      unlockProfile: _unlockProfile,
      onSetUnlockProfile: (p) async {
        await p.save();
        if (!mounted) return;
        setState(() => _unlockProfile = p);
      },
    );

    _hiddenPanelOpen = false;
    await _loadBubbleUnlockPattern();
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (!_unlockProfile.pullDownPanel) return false;
    if (_hiddenPanelOpen || _authUiOpen) return false;

    if (n is OverscrollNotification) {
      if (_hiddenPanelOpen) return false;
      if (n.metrics.pixels <= 0 && n.overscroll < 0) {
        _pullDistance = (_pullDistance + (-n.overscroll)).clamp(0, 140);
        _markPullDirty();
        if (_pullDistance > 90 && !_pullTriggered) {
          _pullTriggered = true;
          if (_threadUnlocked) {
            _lockWholeThreadNow();
          } else {
            _openHiddenPanel();
          }
        }
      }
    }
    if (n is ScrollUpdateNotification) {
      if (_hiddenPanelOpen) return false;
      final delta = n.scrollDelta ?? 0;
      if (n.metrics.pixels <= 0 && delta < 0) {
        _pullDistance = (_pullDistance + (-delta)).clamp(0, 140);
        _markPullDirty();
        if (_pullDistance > 90 && !_pullTriggered) {
          _pullTriggered = true;
          if (_threadUnlocked) {
            _lockWholeThreadNow();
          } else {
            _openHiddenPanel();
          }
        }
      }
    }

    if (n is ScrollStartNotification) {
      _pullDistance = 0;
      _pullTriggered = false;
      _markPullDirty();
    }

    if (n is ScrollEndNotification) {
      _pullDistance = 0;
      _pullTriggered = false;
      _markPullDirty();
    }

    return false;
  }

  void _onPullDragUpdate(DragUpdateDetails details) {
    if (!_unlockProfile.pullDownPanel) return;
    if (_authUiOpen) return;
    if (_hiddenPanelOpen) return;
    final dy = details.delta.dy;
    if (dy <= 0) return;

    _pullDistance = (_pullDistance + dy).clamp(0, 140);
    _markPullDirty();

    if (_pullDistance > 90 && !_pullTriggered) {
      _pullTriggered = true;
      if (_threadUnlocked) {
        _lockWholeThreadNow();
      } else {
        _openHiddenPanel();
      }
    }
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening call in browser...')),
      );
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser.')),
      );
    }
  }

  void _onPullDragEnd(DragEndDetails details) {
    _pullDistance = 0;
    _pullTriggered = false;
    _markPullDirty();
  }

  void _markPullDirty() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      setState(() {});
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onWheelPull(double delta) {
    if (!_unlockProfile.pullDownPanel) return;
    if (_authUiOpen || _hiddenPanelOpen) return;
    if (delta <= 0) return;
    _pullDistance = (_pullDistance + delta).clamp(0, 140);
    _markPullDirty();

    _pullWheelReset?.cancel();
    _pullWheelReset = Timer(const Duration(milliseconds: 420), () {
      _pullDistance = 0;
      _pullTriggered = false;
      _markPullDirty();
    });

    if (_pullDistance > 90 && !_pullTriggered) {
      _pullTriggered = true;
      if (_threadUnlocked) {
        _lockWholeThreadNow();
      } else {
        _openHiddenPanel();
      }
    }
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo';
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

  Future<void> _openAttachment(AttachmentRef ref) async {
    if (!_threadUnlocked) return;
    await AttachmentStore.openAttachment(
      conversationId: widget.conversation.id,
      ref: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    final titleText = widget.conversation.title.trim().isEmpty
        ? (_isGroup ? 'Group' : 'Conversation')
        : widget.conversation.title.trim();

    final showOwnerHints = SecureGate.isSessionUnlocked;
    final ownerHints = <Widget>[];
    if (showOwnerHints && _threadUnlocked) {
      ownerHints.add(_ownerPill('Unlocked'));
    }
    if (showOwnerHints && _conversationHidden) {
      ownerHints.add(_ownerPill('Hidden'));
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleText,
          style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (_isGroup)
          Text(
            'Group',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        if (ownerHints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ownerHints,
            ),
          ),
      ],
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _cancelHoldTimer();
          _lockWholeThreadNow();
        }
      },
      child: BackgroundScaffold(
        style: VeilBackgroundStyle.thread,
        bottomNavigationBar: const BottomNavStrip(current: BottomNavTab.chats),
        appBar: AppBar(
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _unlockProfile.doubleTapTitle ? _openHiddenPanel : null,
            child: header,
          ),
          actions: [
            IconButton(
              tooltip: 'Call',
              onPressed: () => _startCall(video: false),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: 'Video call',
              onPressed: () => _startCall(video: true),
              icon: const Icon(Icons.videocam_outlined),
            ),
            if (_isGroup)
              IconButton(
                tooltip: 'Members',
                onPressed: _openManageMembers,
                icon: const Icon(Icons.group_outlined),
              ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : NotificationListener<ScrollNotification>(
                          onNotification: _onScrollNotification,
                          child: Listener(
                            onPointerSignal: (event) {
                              if (event is PointerScrollEvent) {
                                final dy = event.scrollDelta.dy;
                                if (dy < 0) {
                                  _onWheelPull(-dy);
                                }
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragUpdate: _unlockProfile.pullDownPanel ? _onPullDragUpdate : null,
                              onVerticalDragEnd: _unlockProfile.pullDownPanel ? _onPullDragEnd : null,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return _messageBubble(_messages[index]);
                                },
                              ),
                            ),
                          ),
                        ),
                ),
                _composer(),
              ],
            ),
            if (_unlockProfile.pullDownPanel)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: (_pullDistance > 8 && !_hiddenPanelOpen) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant.withAlpha((0.6 * 255).round()),
                        ),
                      ),
                      child: Text(
                        _threadUnlocked ? 'Pull to lock' : 'Pull to open Hidden Panel',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_unlockProfile.pullDownPanel)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 28,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      final dy = event.scrollDelta.dy;
                      if (dy < 0) {
                        _onWheelPull(-dy);
                      }
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: _onPullDragUpdate,
                    onVerticalDragEnd: _onPullDragEnd,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(Message m) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final isMe = m.isMe;
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final cross = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final avatar = _bubbleAvatar(m);
    const avatarSize = 28.0;

    final text = _displayText(m).trim();
    final hasText = text.isNotEmpty;
    final att = m.attachment;

    final bubbleColor =
        isMe ? scheme.surface : scheme.surfaceContainerHighest;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());

    return Align(
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _avatarCircle(avatar, m, avatarSize),
            ),
          Flexible(
            child: Builder(
              builder: (bubbleCtx) => Listener(
                onPointerDown: (e) {
                  _startHoldTimer(e.position, e.kind, e.buttons);
                },
                onPointerMove: (e) {
                  _onHoldPointerMove(e.position);
                },
                onPointerUp: (_) => _onHoldPointerUp(),
                onPointerCancel: (_) => _cancelHoldTimer(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onBubbleTap(m.id),
                  onTapDown: (d) =>
                      _onBubblePatternInput(d.localPosition, bubbleCtx),
                  onPanStart: (d) =>
                      _onBubbleGestureStart(d.localPosition, bubbleCtx),
                  onPanUpdate: (d) {
                    _onBubblePatternInput(d.localPosition, bubbleCtx);
                    _onBubbleGestureUpdate(d.localPosition, bubbleCtx);
                  },
                onPanEnd: (_) => _onBubbleGestureEnd(),
                onLongPress: () => _confirmDeleteMessage(m),
                onSecondaryTapDown: (_) => _confirmDeleteMessage(m),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: cross,
                    children: [
                      if (_isGroup && (m.authorName ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            m.authorName!,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      if (hasText)
                        Text(
                          text,
                          style: TextStyle(color: fg, fontSize: 15),
                        ),
                      if (att != null) ...[
                        if (hasText) const SizedBox(height: 8),
                        _attachmentTile(att),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Text(
                            '${_formatDate(m.timestamp)} ${_formatTime(m.timestamp)}',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Text(
                              m.status,
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _avatarCircle(avatar, m, avatarSize),
            ),
        ],
      ),
    );
  }

  ImageProvider? _bubbleAvatar(Message m) {
    if (m.isMe) {
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

    if (_isGroup && (m.authorId ?? '').startsWith('c_')) {
      final cid = (m.authorId ?? '').substring(2);
      final c = _memberContacts[cid];
      final raw = c?.photoB64;
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final bytes = base64Decode(raw);
          if (bytes.isNotEmpty) return MemoryImage(bytes);
        } catch (_) {}
      }
    }

    final raw = _threadContact?.photoB64;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final bytes = base64Decode(raw);
        if (bytes.isNotEmpty) return MemoryImage(bytes);
      } catch (_) {}
    }
    return null;
  }

  Widget _avatarCircle(ImageProvider? img, Message m, double size) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final name = m.isMe
        ? (_ownerName ?? 'Me')
        : _displayNameForMessage(m);
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primary.withAlpha((0.12 * 255).round()),
      backgroundImage: img,
      child: img == null
          ? Text(letter, style: TextStyle(color: fg, fontSize: 12))
          : null,
    );
  }

  String _displayNameForMessage(Message m) {
    if (_isGroup) {
      final raw = (m.authorName ?? '').trim();
      if (raw.isNotEmpty) return raw;
    }
    final contactName = _threadContact?.coverName.trim() ?? '';
    if (contactName.isNotEmpty) return contactName;
    final title = widget.conversation.title.trim();
    if (title.isNotEmpty) return title;
    return 'Contact';
  }

  Widget _attachmentTile(AttachmentRef att) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final enabled = _threadUnlocked;

    return InkWell(
      onTap: enabled ? () => _openAttachment(att) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withAlpha((0.45 * 255).round())),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    att.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatBytes(att.byteLength),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock_outline, color: muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());
    final pending = _pendingAttachment;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Icon(Icons.attach_file, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pending.fileName,
                      style: TextStyle(color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatBytes(pending.byteLength),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _pendingAttachment = null),
                    icon: Icon(Icons.close, color: muted),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Add',
                onPressed: _openAttachmentMenu,
                icon: Icon(Icons.add, color: muted),
              ),
              IconButton(
                tooltip: 'Send to Hidden Inbox',
                onPressed: () {
                  setState(() => _sendHiddenNext = !_sendHiddenNext);
                },
                icon: Icon(
                  _sendHiddenNext ? Icons.visibility_off : Icons.visibility_off_outlined,
                  color: _sendHiddenNext ? Theme.of(context).colorScheme.primary : muted,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _composerCtrl,
                  minLines: 1,
                  maxLines: 5,
                  style: TextStyle(color: fg),
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(color: muted),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                tooltip: 'Send',
                onPressed: _send,
                icon: Icon(Icons.send, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ownerPill(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha((0.12 * 255).round()),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withAlpha((0.45 * 255).round())),
      ),
      child: Text(
        label,
        style: TextStyle(color: scheme.onSurface, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum _AttachmentPickSource {
  downloads,
  systemPicker,
}

enum _AttachAction {
  photo,
  cameraRoll,
  location,
  contact,
  shareContact,
  document,
  calendarEvent,
}
