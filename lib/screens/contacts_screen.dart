import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../data/contact_repository.dart';
import '../data/conversation_store.dart' as convs;
import '../models/contact.dart';
import '../routes/app_routes.dart';
import '../security/owner_auth_flow.dart';
import '../security/biometric_auth_service.dart';
import '../security/secure_gate.dart';
import '../security/unlock_service.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactRepository _repo = ContactRepository();
  final convs.ConversationStore _convs = convs.ConversationStore();

  late Future<List<Contact>> _future;
  Map<String, int> _unreadByContact = const {};
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _repo.getAll();
    _loadUnreadCounts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      _future = _repo.getAll();
    });
    await _loadUnreadCounts();
  }

  Future<void> _loadUnreadCounts() async {
    try {
      final convsList = await _convs.getAllSorted();
      if (!mounted) return;
      final map = <String, int>{};
      for (final c in convsList) {
        final cid = c.contactId;
        if (cid == null || cid.trim().isEmpty) continue;
        if (c.unreadCount <= 0) continue;
        map[cid] = c.unreadCount;
      }
      setState(() => _unreadByContact = map);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadByContact = const {});
    }
  }

  Future<bool> _requireOwnerAccess() async {
    if (SecureGate.isPanicActive) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock blocked (panic active).')),
      );
      return false;
    }

    final hasBio = await BiometricAuthService.hasAvailableBiometrics();
    if (!mounted) return false;
    if (hasBio) {
      final okBio = await OwnerAuthFlow.ensureOwnerSessionUnlocked(context);
      if (!mounted) return false;
      if (okBio) return true;
      return false;
    }

    final unlock = UnlockService();
    final hasPin = await unlock.hasPassphrase();
    if (!mounted) return false;
    if (!hasPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a PIN to access contacts.')),
      );
      return false;
    }

    final pin = await _askPin(context);
    if (!mounted) return false;
    if (pin == null || pin.trim().isEmpty) return false;

    final okPin = await unlock.verifyPassphrase(pin.trim());
    if (!mounted) return false;
    if (!okPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong PIN.')),
      );
      return false;
    }

    SecureGate.unlockSession();
    return true;
  }

  Future<String?> _askPin(BuildContext context) async {
    var pinText = '';
    final res = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: AlertDialog(
            title: const Text(''),
            content: TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'PIN'),
              onChanged: (v) => pinText = v,
              onSubmitted: (_) => Navigator.pop(dctx, pinText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, pinText),
                child: const Text('Unlock'),
              ),
            ],
          ),
        );
      },
    );
    return res;
  }

  Future<void> _openEditDialog(Contact c) async {
    final okAuth = await _requireOwnerAccess();
    if (!mounted) return;
    if (!okAuth) {
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) => _EditContactDialog(
        contact: c,
        onSave: (updated) async {
          await _repo.upsert(updated);
        },
        onDelete: () async {
          await _repo.delete(c.id);
        },
        onOpenChat: () async {
          final conv = await _convs.getOrCreateForContact(
            contactId: c.id,
            fallbackTitle: c.coverName,
          );
          if (!mounted) return;
          await Navigator.of(context).pushNamed(
            AppRoutes.thread,
            arguments: conv,
          );
        },
      ),
    );

    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _createNewContact() async {
    final okAuth = await _requireOwnerAccess();
    if (!mounted) return;
    if (!okAuth) {
      return;
    }
    final fresh = Contact(
      id: _repo.newId(),
      coverName: '',
      coverEmoji: null,
      mode: ContactMode.plain,
      category: ContactCategory.private,
      coverStyleOverride: CoverStyleOverride.auto,
      favorite: false,
      firstName: null,
      lastName: null,
      email: null,
      address: null,
      photoB64: null,
      realName: null,
      realEmoji: null,
      phone: null,
    );

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) => _EditContactDialog(
        contact: fresh,
        isNew: true,
        onSave: (updated) async {
          await _repo.upsert(updated);
        },
        onDelete: () async {},
        onOpenChat: () async {},
      ),
    );

    if (changed == true) {
      await _reload();
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
      bottomNavigationBar: const BottomNavStrip(current: BottomNavTab.contacts),
      appBar: AppBar(
        foregroundColor: fg,
        title: Text('Contacts', style: TextStyle(color: fg)),
        actions: [
          IconButton(
            tooltip: 'New',
            onPressed: _createNewContact,
            icon: Icon(Icons.person_add_alt_1, color: fg),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: Icon(Icons.refresh, color: fg),
          ),
        ],
      ),
      child: FutureBuilder<List<Contact>>(
        future: _future,
        builder: (context, snap) {
          final items = _filter(snap.data ?? const <Contact>[]);

          if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (items.isEmpty) {
            return Center(
              child: Text(
                'No contacts yet.',
                style: TextStyle(color: muted),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: Column(
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
                        hintText: 'Search contacts…',
                        hintStyle: TextStyle(color: muted),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search, color: muted),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 18,
                      color: border,
                    ),
                    itemBuilder: (context, index) {
                      final c = items[index];
                      final unread = _unreadByContact[c.id] ?? 0;

                      final title =
                          c.coverName.trim().isEmpty ? '(no name)' : c.coverName.trim();
                      final avatar = _contactAvatar(c);
                      final leadingText = (c.coverEmoji != null &&
                              c.coverEmoji!.trim().isNotEmpty)
                          ? c.coverEmoji!.trim()
                          : (title.isEmpty ? '?' : title[0].toUpperCase());

                      return InkWell(
                        onTap: () => _openEditDialog(c),
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
                                backgroundColor:
                                    scheme.primary.withAlpha((0.12 * 255).round()),
                                backgroundImage: avatar,
                                child: avatar == null
                                    ? Text(
                                        leadingText,
                                        style: TextStyle(color: fg),
                                      )
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
                                      c.phone ?? '',
                                      style: TextStyle(color: muted, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (unread > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: scheme.primary
                                        .withAlpha((0.12 * 255).round()),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: TextStyle(color: fg, fontSize: 12),
                                  ),
                                )
                              else
                                Icon(Icons.edit, color: muted, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EditContactDialog extends StatefulWidget {
  final Contact contact;
  final bool isNew;

  final Future<void> Function(Contact updated) onSave;
  final Future<void> Function() onDelete;
  final Future<void> Function() onOpenChat;

  const _EditContactDialog({
    required this.contact,
    required this.onSave,
    required this.onDelete,
    required this.onOpenChat,
    this.isNew = false,
  });

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final TextEditingController _coverNameCtrl;
  late final TextEditingController _coverEmojiCtrl;
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _realNameCtrl;
  late final TextEditingController _realEmojiCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;

  late ContactMode _mode;
  late ContactCategory _category;
  late CoverStyleOverride _coverStyleOverride;
  late bool _favorite;
  String? _photoB64;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;

    _coverNameCtrl = TextEditingController(text: c.coverName);
    _coverEmojiCtrl = TextEditingController(text: c.coverEmoji ?? '');
    _firstNameCtrl = TextEditingController(text: c.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: c.lastName ?? '');
    _realNameCtrl = TextEditingController(text: c.realName ?? '');
    _realEmojiCtrl = TextEditingController(text: c.realEmoji ?? '');
    _phoneCtrl = TextEditingController(text: c.phone ?? '');
    _emailCtrl = TextEditingController(text: c.email ?? '');
    _addressCtrl = TextEditingController(text: c.address ?? '');

    _mode = c.mode;
    _category = c.category;
    _coverStyleOverride = c.coverStyleOverride;
    _favorite = c.favorite;
    _photoB64 = c.photoB64;
  }

  @override
  void dispose() {
    _coverNameCtrl.dispose();
    _coverEmojiCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _realNameCtrl.dispose();
    _realEmojiCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Contact _buildUpdated() {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    var cover = _coverNameCtrl.text.trim();
    if (cover.isEmpty && (first.isNotEmpty || last.isNotEmpty)) {
      cover = [first, last].where((s) => s.isNotEmpty).join(' ');
    }

    return widget.contact.copyWith(
      coverName: cover,
      coverEmoji:
          _coverEmojiCtrl.text.trim().isEmpty ? null : _coverEmojiCtrl.text.trim(),
      firstName: first.isEmpty ? null : first,
      lastName: last.isEmpty ? null : last,
      mode: _mode,
      category: _category,
      coverStyleOverride: _coverStyleOverride,
      favorite: _favorite,
      realName: _realNameCtrl.text.trim().isEmpty ? null : _realNameCtrl.text.trim(),
      realEmoji:
          _realEmojiCtrl.text.trim().isEmpty ? null : _realEmojiCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      photoB64: _photoB64,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final updated = _buildUpdated();

      if (updated.coverName.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cover name is required.')),
          );
        }
        return;
      }

      await widget.onSave(updated);

      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final xf = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
        ),
      ],
    );
    if (xf == null) return;
    final bytes = await xf.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() => _photoB64 = base64Encode(bytes));
  }

  void _clearPhoto() {
    setState(() => _photoB64 = null);
  }

  ImageProvider? _photoProvider() {
    final raw = _photoB64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: const Text(
            'This will remove the contact. Conversations are not deleted automatically.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    await widget.onDelete();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _modeLabelForForm(ContactMode m) =>
      (m == ContactMode.dualHidden) ? 'Active' : 'Not active';
  String _catLabel(ContactCategory c) =>
      (c == ContactCategory.business) ? 'Business' : 'Private';
  String _coverStyleLabel(CoverStyleOverride c) {
    switch (c) {
      case CoverStyleOverride.business:
        return 'Business';
      case CoverStyleOverride.private:
        return 'Private';
      case CoverStyleOverride.auto:
        return 'Automatic';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHidden = _mode == ContactMode.dualHidden;

    return AlertDialog(
      title: Text(widget.isNew ? 'New contact' : 'Edit contact'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _firstNameCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'First name',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastNameCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Last name',
                ),
              ),
              TextField(
                controller: _coverNameCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Cover name',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _coverEmojiCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Avatar emoji (optional)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ContactMode>(
                key: ValueKey('mode_${_mode.name}'),
                initialValue: _mode,
                items: ContactMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(_modeLabelForForm(m)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _mode = v ?? ContactMode.plain;
                        }),
                decoration:
                    const InputDecoration(labelText: 'AI generated text'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ContactCategory>(
                key: ValueKey('cat_${_category.name}'),
                initialValue: _category,
                items: ContactCategory.values
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(_catLabel(c)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _category = v ?? ContactCategory.private;
                        }),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<CoverStyleOverride>(
                key: ValueKey('cover_${_coverStyleOverride.name}'),
                initialValue: _coverStyleOverride,
                items: CoverStyleOverride.values
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(_coverStyleLabel(c)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _coverStyleOverride = v ?? CoverStyleOverride.auto;
                        }),
                decoration:
                    const InputDecoration(labelText: 'Cover style (decoy tone)'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _favorite,
                onChanged: _saving ? null : (v) => setState(() => _favorite = v),
                title: const Text('Favorite contact'),
                subtitle: const Text('Show at top of inbox.'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withAlpha((0.12 * 255).round()),
                    backgroundImage: _photoProvider(),
                    child: _photoProvider() == null
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _photoB64 == null ? 'No profile photo' : 'Profile photo set',
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _pickPhoto,
                    child: const Text('Choose'),
                  ),
                  if (_photoB64 != null)
                    TextButton(
                      onPressed: _saving ? null : _clearPhoto,
                      child: const Text('Remove'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Email',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _addressCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Address',
                ),
              ),
              const SizedBox(height: 14),
              if (isHidden) ...[
                const Divider(),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Hidden identity (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _realNameCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Real name',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _realEmojiCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Real emoji',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (!widget.isNew)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  if (widget.isNew) {
                    await _save();
                    return;
                  }
                  await widget.onOpenChat();
                },
          child: const Text('Open chat'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
