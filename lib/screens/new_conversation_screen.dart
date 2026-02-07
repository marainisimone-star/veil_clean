import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/contact_repository.dart';
import '../data/conversation_store.dart';
import '../models/contact.dart';
import '../routes/app_routes.dart';
import '../widgets/background_scaffold.dart';

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final ContactRepository _contacts = ContactRepository();
  final ConversationStore _convs = ConversationStore();

  late Future<List<Contact>> _future;

  final _searchCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _contacts.getAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _contacts.getAll();
    });
  }

  Future<void> _openThreadForConversationId(String conversationId) async {
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.inbox,
      (route) => false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = await _convs.getById(conversationId);
      if (c == null) return;
      if (!mounted) return;

      Navigator.pushNamed(
        context,
        AppRoutes.thread,
        arguments: c,
      );
    });
  }

  Future<void> _startChatWithContact(Contact c) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final conv = await _convs.getOrCreateForContact(
        contactId: c.id,
        fallbackTitle: c.coverName,
      );
      await _openThreadForConversationId(conv.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _looksLikePhoneOrEmail(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;

    final hasAt = t.contains('@');
    final digits = t.replaceAll(RegExp(r'[^0-9+]'), '');
    final looksPhone = digits.replaceAll('+', '').length >= 7;

    return hasAt || looksPhone;
  }

  bool _isManualValid(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;

    if (_looksLikePhoneOrEmail(t)) {
      if (t == '@') return false;
      if (t == '+' || t.replaceAll('+', '').isEmpty) return false;
      return true;
    }

    return t.length >= 2;
  }

  Future<void> _startChatWithManual() async {
    final raw = _manualCtrl.text.trim();
    if (!_isManualValid(raw)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone/email or a name.')),
      );
      return;
    }

    final isPhoneOrEmail = _looksLikePhoneOrEmail(raw);

    final coverName = isPhoneOrEmail ? 'New contact' : raw;
    final phoneOrEmail = isPhoneOrEmail ? raw : null;

    if (_saving) return;
    setState(() => _saving = true);

    try {
      FocusScope.of(context).unfocus();

      final c = Contact(
        id: _contacts.newId(),
        coverName: coverName,
        coverEmoji: null,
        mode: ContactMode.plain,
        category: ContactCategory.private,
        realName: null,
        realEmoji: null,
        phone: phoneOrEmail,
      );

      await _contacts.upsert(c);

      final conv = await _convs.getOrCreateForContact(
        contactId: c.id,
        fallbackTitle: c.coverName,
      );

      _manualCtrl.clear();

      await _openThreadForConversationId(conv.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createGroup() async {
    final name = _groupCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required.')),
      );
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    try {
      final conv = await _convs.createGroup(title: name);
      _groupCtrl.clear();
      await _openThreadForConversationId(conv.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Contact> _filter(List<Contact> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;

    return all.where((c) {
      final cover = c.coverName.toLowerCase();
      final phone = (c.phone ?? '').toLowerCase();
      final real = (c.realName ?? '').toLowerCase();
      final email = (c.email ?? '').toLowerCase();
      final first = (c.firstName ?? '').toLowerCase();
      final last = (c.lastName ?? '').toLowerCase();
      return cover.contains(q) ||
          phone.contains(q) ||
          real.contains(q) ||
          email.contains(q) ||
          first.contains(q) ||
          last.contains(q);
    }).toList(growable: false);
  }

  ImageProvider? _contactAvatar(Contact c) {
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
        foregroundColor: fg,
        title: Text('New conversation', style: TextStyle(color: fg)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: (_saving) ? null : _reload,
            icon: Icon(Icons.refresh, color: fg),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                // Group creation
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create a group',
                        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _groupCtrl,
                              enabled: !_saving,
                              style: TextStyle(color: fg),
                              decoration: const InputDecoration(
                                hintText: 'Group name',
                                hintStyle: TextStyle(color: Colors.black54),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _createGroup(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: (_saving) ? null : _createGroup,
                            child: Text(_saving ? '...' : 'Create'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Manual entry
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start with a number / email (not in contacts)',
                        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _manualCtrl,
                              enabled: !_saving,
                              style: TextStyle(color: fg),
                              decoration: const InputDecoration(
                                hintText: 'Phone or email (or a name)',
                                hintStyle: TextStyle(color: Colors.black54),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _startChatWithManual(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: (_saving) ? null : _startChatWithManual,
                            child: Text(_saving ? '...' : 'Start'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Contacts picker
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Or pick an existing contact',
                        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchCtrl,
                        enabled: !_saving,
                        style: TextStyle(color: fg),
                        decoration: const InputDecoration(
                          hintText: 'Search contact…',
                          hintStyle: TextStyle(color: Colors.black54),
                          prefixIcon: Icon(Icons.search, color: Colors.black54),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: FutureBuilder<List<Contact>>(
                    future: _future,
                    builder: (context, snap) {
                      final all = snap.data ?? const <Contact>[];
                      final items = _filter(all);

                      if (snap.connectionState == ConnectionState.waiting && all.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (items.isEmpty) {
                        return Center(
                          child: Text('No matching contacts.', style: TextStyle(color: muted)),
                        );
                      }

                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, i) => Divider(
                          height: 16,
                          color: border,
                        ),
                        itemBuilder: (context, i) {
                          final c = items[i];
                          final title = c.coverName.trim().isEmpty ? '(no name)' : c.coverName.trim();
                          final avatar = _contactAvatar(c);
                          final leadingText = (c.coverEmoji != null && c.coverEmoji!.trim().isNotEmpty)
                              ? c.coverEmoji!.trim()
                              : (title.isEmpty ? '?' : title[0].toUpperCase());

                          return InkWell(
                            onTap: (_saving) ? null : () => _startChatWithContact(c),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: border),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: scheme.primary.withAlpha((0.12 * 255).round()),
                                    backgroundImage: avatar,
                                    child: avatar == null
                                        ? Text(leadingText, style: TextStyle(color: fg))
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            color: fg,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          (c.phone ?? '').isEmpty ? ' ' : (c.phone ?? ''),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: muted, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.chevron_right, color: muted),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
