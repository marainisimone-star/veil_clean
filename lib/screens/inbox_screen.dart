import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/conversation_store.dart' as convs;
import '../data/contact_repository.dart';
import '../data/local_storage.dart';
import '../data/message_events.dart';
import '../data/message_repository.dart' as msgs;
import '../models/contact.dart';
import '../models/conversation.dart';
import '../routes/app_routes.dart';
import '../screens/hidden_panel.dart';
import '../security/unlock_profile.dart';
import '../widgets/background_scaffold.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final convs.ConversationStore _store = convs.ConversationStore();
  final ContactRepository _contactsRepo = ContactRepository();
  final msgs.MessageRepository _msgs = msgs.MessageRepository();
  late Future<List<Conversation>> _future;
  Map<String, Contact> _contactsById = const {};
  int _hiddenUnreadCount = 0;
  StreamSubscription<MessageEvent>? _sub;
  Timer? _refreshDebounce;

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  static const String _kHiddenView = 'veil_inbox_hidden_view_v1';
  bool _showHidden = false;
  UnlockProfile _unlockProfile = UnlockProfile.defaults();

  @override
  void initState() {
    super.initState();
    _future = _store.getAllSorted();
    _loadViewMode();
    _loadUnlockProfile();
    _loadContacts();
    _loadHiddenUnreadCount();
    _subscribeMessages();
  }

  Future<void> _loadViewMode() async {
    final v = LocalStorage.getString(_kHiddenView) == '1';
    if (!mounted) return;
    setState(() => _showHidden = v);
  }

  Future<void> _loadUnlockProfile() async {
    final profile = await UnlockProfile.load();
    if (!mounted) return;
    setState(() => _unlockProfile = profile);
  }

  Future<void> _setViewMode(bool hidden) async {
    await LocalStorage.setString(_kHiddenView, hidden ? '1' : '0');
    if (!mounted) return;
    setState(() => _showHidden = hidden);
    await _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _refreshDebounce?.cancel();
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _reload() async {
    setState(() {
      _future = _store.getAllSorted();
    });
    await _loadContacts();
    await _loadHiddenUnreadCount();
  }

  Future<void> _loadContacts() async {
    try {
      final items = await _contactsRepo.getAll();
      if (!mounted) return;
      setState(() {
        _contactsById = {for (final c in items) c.id: c};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _contactsById = const {});
    }
  }

  Future<void> _loadHiddenUnreadCount() async {
    try {
      final all = await _store.getAllSorted();
      if (!mounted) return;
      final count = all
          .where((c) => c.isHidden && c.unreadCount > 0)
          .fold<int>(0, (a, b) => a + b.unreadCount);
      setState(() => _hiddenUnreadCount = count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hiddenUnreadCount = 0);
    }
  }

  void _subscribeMessages() {
    _sub = _msgs.events.listen((event) {
      if (!mounted) return;
      if (event.type != MessageEventType.added) return;
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _reload();
      });
    });
  }

  ImageProvider? _contactAvatar(Contact? c) {
    if (c == null) return null;
    final raw = c.photoB64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openThread(Conversation c) async {
    await Navigator.pushNamed(context, AppRoutes.thread, arguments: c);

    await _store.markRead(c.id);

    if (!mounted) return;
    await _reload();
  }

  void _newConversation() {
    Navigator.pushNamed(context, AppRoutes.newConversation);
  }

  Future<void> _openContacts() async {
    await Navigator.pushNamed(context, AppRoutes.contacts);
    if (!mounted) return;
    await _reload();
  }

  void _openHiddenPanel() {
    HiddenPanel.show(
      context,
      inboxHiddenView: _showHidden,
      onToggleInboxView: () => _setViewMode(!_showHidden),
      unlockProfile: _unlockProfile,
      onSetUnlockProfile: (p) async {
        await p.save();
        if (!mounted) return;
        setState(() => _unlockProfile = p);
      },
    );
  }

  String _formatStamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(day).inDays;

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');

    if (diffDays == 0) return '$hh:$mm';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) return '${diffDays}d';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  Future<void> _confirmDelete(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('This will remove "${c.title}" from the inbox.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    await _store.removeConversation(c.id);
    if (!mounted) return;
    await _reload();
  }

  Future<void> _showConversationMenu({
    required Conversation c,
    required Offset globalPosition,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;

    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'delete',
        child: Text('Delete'),
      ),
    ];
    if (_showHidden) {
      items.insert(
        0,
        const PopupMenuItem<String>(
          value: 'unhide',
          child: Text('Move to main inbox'),
        ),
      );
    }

    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: items,
    );

    if (chosen == 'unhide') {
      await _store.setHidden(conversationId: c.id, hidden: false);
      if (!mounted) return;
      await _reload();
      return;
    }

    if (chosen == 'delete') {
      await _confirmDelete(c);
    }
  }

  Future<void> _showConversationMenuSimple(Conversation c) async {
    if (_showHidden) {
      final chosen = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Conversation'),
          content: Text('What do you want to do with "${c.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, 'unhide'),
              child: const Text('Move to main inbox'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, 'delete'),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (chosen == 'unhide') {
        await _store.setHidden(conversationId: c.id, hidden: false);
        if (!mounted) return;
        await _reload();
        return;
      }
      if (chosen == 'delete') {
        await _confirmDelete(c);
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Conversation'),
        content: Text('Delete "${c.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await _confirmDelete(c);
    }
  }

  List<Conversation> _filter(List<Conversation> all) {
    final q = _searchCtrl.text.trim().toLowerCase();

    final scoped = all.where((c) => c.isHidden == _showHidden).toList(growable: false);

    if (q.isEmpty) return scoped;

    return scoped.where((c) {
      final title = c.title.toLowerCase();
      final last = c.lastMessage.toLowerCase();
      return title.contains(q) || last.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final cardBg = scheme.surface;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _openHiddenPanel,
          child: Builder(
            builder: (ctx) {
              return TextButton(
                onPressed: () {},
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        _showHidden ? 'Hidden' : 'Inbox',
                        style: TextStyle(color: fg),
                      ),
                    ),
                    if (!_showHidden && _hiddenUnreadCount > 0)
                      Positioned(
                        right: 0,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          if (_showHidden)
            TextButton(
              onPressed: () => _setViewMode(false),
              child: Text('Inbox', style: TextStyle(color: fg)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.onboarding,
                (route) => false,
              );
            },
            child: Text('Onboarding', style: TextStyle(color: fg)),
          ),
          IconButton(
            tooltip: 'Contacts',
            onPressed: _openContacts,
            icon: Icon(Icons.people_alt_outlined, color: fg),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: Icon(Icons.refresh, color: fg),
          ),
        ],
      ),
      child: Stack(
        children: [
          FutureBuilder<List<Conversation>>(
            future: _future,
            builder: (context, snap) {
              final items = _filter(snap.data ?? const <Conversation>[]);

              if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        style: TextStyle(color: fg),
                        decoration: InputDecoration(
                          hintText: 'Search conversations…',
                          hintStyle: TextStyle(color: muted),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search, color: muted),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              _showHidden ? 'No hidden conversations.' : 'No conversations yet.',
                              style: TextStyle(color: muted),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _reload,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 18,
                                color: border,
                              ),
                              itemBuilder: (context, index) {
                                final c = items[index];
                                final contact = (c.contactId == null)
                                    ? null
                                    : _contactsById[c.contactId];
                                final avatar = _contactAvatar(contact);

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onSecondaryTapDown: (d) {
                                    _showConversationMenu(c: c, globalPosition: d.globalPosition);
                                  },
                                  onLongPressStart: (d) {
                                    _showConversationMenu(c: c, globalPosition: d.globalPosition);
                                  },
                                  onLongPress: () => _showConversationMenuSimple(c),
                                  child: InkWell(
                                    onTap: () => _openThread(c),
                                    onLongPress: () => _showConversationMenuSimple(c),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: border,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: scheme.primary.withAlpha((0.12 * 255).round()),
                                            backgroundImage: avatar,
                                            child: avatar == null
                                                ? Text(
                                                    c.title.isEmpty ? '?' : c.title[0].toUpperCase(),
                                                    style: TextStyle(color: fg),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        c.title,
                                                        style: TextStyle(
                                                          color: fg,
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      _formatStamp(c.lastUpdated),
                                                      style: TextStyle(color: muted, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  c.lastMessage.isEmpty ? ' ' : c.lastMessage,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(color: muted, fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          if (c.unreadCount > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: scheme.primary.withAlpha((0.12 * 255).round()),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${c.unreadCount}',
                                                style: TextStyle(color: fg, fontSize: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: FloatingActionButton(
              onPressed: _newConversation,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}
