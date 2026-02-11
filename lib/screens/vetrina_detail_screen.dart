import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../models/vetrina.dart';
import '../models/vetrina_message.dart';
import '../models/vetrina_post.dart';
import '../services/external_link_service.dart';
import '../services/vetrina_repository.dart';
import '../services/vetrina_repository_base.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';
import '../widgets/mini_presence_dock.dart';

class VetrinaDetailScreen extends StatefulWidget {
  const VetrinaDetailScreen({
    super.key,
    required this.vetrinaId,
    this.initial,
    this.repository,
    this.showBottomNav = true,
  });

  final String vetrinaId;
  final Vetrina? initial;
  final VetrinaRepositoryBase? repository;
  final bool showBottomNav;

  @override
  State<VetrinaDetailScreen> createState() => _VetrinaDetailScreenState();
}

class _VetrinaDetailScreenState extends State<VetrinaDetailScreen> {
  late final VetrinaRepositoryBase _repo;
  late Future<Vetrina?> _future;
  final _msgCtrl = TextEditingController();
  bool _sending = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? VetrinaRepository.I;
    _future = _repo.getById(widget.vetrinaId);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePromote() async {
    final ok = await _repo.promote(widget.vetrinaId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Promoted to your network.')),
      );
      setState(() {
        _future = _repo.getById(widget.vetrinaId);
      });
    } else {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Already promoted.')),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final result = await _repo.addMessage(
      vetrinaId: widget.vetrinaId,
      text: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (result == 'ok' || result == 'warned') {
      _msgCtrl.clear();
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (result) {
      case 'warned':
        messenger?.showSnackBar(const SnackBar(content: Text('Warning: stay civil.')));
        break;
      case 'restricted':
        messenger?.showSnackBar(const SnackBar(content: Text('You are temporarily restricted.')));
        break;
      case 'excluded':
        messenger?.showSnackBar(const SnackBar(content: Text('You are excluded from this showcase.')));
        break;
      case 'empty':
        messenger?.showSnackBar(const SnackBar(content: Text('Message is empty.')));
        break;
      case 'auth':
        messenger?.showSnackBar(const SnackBar(content: Text('Please sign in first.')));
        break;
      case 'error':
        messenger?.showSnackBar(const SnackBar(content: Text('Could not send message.')));
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = Colors.white;
    final muted = Colors.white70;
    final border = Colors.white.withAlpha((0.10 * 255).round());

    return BackgroundScaffold(
      style: VeilBackgroundStyle.thread,
      useGradient: false,
      useOverlay: false,
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        title: Text('Vetrina Showcase', style: TextStyle(color: fg)),
        foregroundColor: fg,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Promote',
            onPressed: _handlePromote,
            icon: const Icon(Icons.campaign_outlined),
          ),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav
          ? const BottomNavStrip(
              current: BottomNavTab.chats,
              dock: MiniPresenceDock(mode: PresenceMode.social, compact: true),
            )
          : null,
      child: Stack(
        children: [
          Container(
            color: const Color(0xFF0F0F0F),
            child: FutureBuilder<Vetrina?>(
              future: _future,
              builder: (context, snap) {
                final v = snap.data ?? widget.initial;
                if (snap.connectionState == ConnectionState.waiting && v == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (v == null) {
                  return Center(
                    child: Text('Showcase not found.', style: TextStyle(color: muted)),
                  );
                }

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(context).padding.bottom + 80,
                  ),
                  children: [
                    _heroWithContent(v, scheme, fg, muted, border),
                    const SizedBox(height: 16),
                    Text(v.title, style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: v.tags.map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.12 * 255).round()),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(t, style: TextStyle(color: fg, fontSize: 11)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _rulesCard(v, fg, muted, scheme, border),
                    const SizedBox(height: 16),
                    _discussionCard(fg, muted, scheme, border),
                    const SizedBox(height: 16),
                    _actionBar(context, fg, scheme),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Color border, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  Widget _heroWithContent(
    Vetrina v,
    ColorScheme scheme,
    Color fg,
    Color muted,
    Color border,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _coverSlim(v, scheme),
        Positioned(
          left: 0,
          right: 0,
          bottom: -16,
          child: _showcaseContentCard(fg, muted, border),
        ),
      ],
    );
  }

  Widget _showcaseContentCard(Color fg, Color muted, Color border) {
    return _card(
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Showcase content', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          StreamBuilder<List<VetrinaPost>>(
            stream: _repo.watchPosts(widget.vetrinaId),
            builder: (context, snap) {
              final items = snap.data ?? const <VetrinaPost>[];
              if (items.isEmpty) {
                return Text('No content yet.', style: TextStyle(color: muted, fontSize: 11));
              }
              return Column(
                children: items.take(5).map((p) {
                  final label = p.label.trim().isEmpty ? p.type : p.label.trim();
                  final localPath = p.localPath;
                  final url = p.url;
                  final isPhoto = p.type == 'photo';
                  final isText = p.type == 'text';
                  final isLink = p.type == 'link';
                  final isLive = p.type == 'live';
                    final hasLocalFile =
                        localPath != null && localPath.isNotEmpty && File(localPath).existsSync();
                    final imageWidget = isPhoto && (url?.isNotEmpty == true || hasLocalFile)
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 180,
                                width: double.infinity,
                                child: (url?.isNotEmpty == true)
                                    ? Image.network(url!, fit: BoxFit.cover)
                                    : Image.file(File(localPath!), fit: BoxFit.cover),
                              ),
                            ),
                          )
                        : null;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.04 * 255).round()),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha((0.08 * 255).round())),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageWidget != null) imageWidget,
                        if (isText && (p.text?.isNotEmpty == true))
                          Text(
                            p.text!,
                            style: TextStyle(color: fg, fontSize: 12),
                          )
                        else if ((isLink || isLive) && (p.url?.isNotEmpty == true))
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.url!,
                                  style: TextStyle(color: fg, fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => ExternalLinkService.openUrl(p.url!),
                                child: const Text('Open'),
                              ),
                            ],
                          )
                        else
                          Text(
                            '${p.type.toUpperCase()}: $label',
                            style: TextStyle(color: fg, fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _coverSlim(Vetrina v, ColorScheme scheme) {
    final url = v.coverUrl ?? '';
    if (url.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 90,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(url, fit: BoxFit.cover),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withAlpha((0.25 * 255).round()),
                      Colors.black.withAlpha((0.15 * 255).round()),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 10,
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined, color: scheme.onPrimary, size: 18),
                    const SizedBox(width: 6),
                    Text('Showcase', style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3A28), Color(0xFF2B2017)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, color: scheme.onPrimary, size: 18),
            const SizedBox(width: 6),
            Text('Showcase', style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _rulesCard(Vetrina v, Color fg, Color muted, ColorScheme scheme, Color border) {
    final guidelines = v.guidelines;
    final quizOptional = v.quizEnabled ? 'true' : 'false';
    final options = v.ruleOptions;
    final optList = <String>[];
    if (options['cite_sources_5w'] == true) optList.add('Cite sources (5W baseline)');
    if (options['stay_on_topic'] == true) optList.add('Stay on topic');
    if (options['respect_expertise'] == true) optList.add('Respect expertise level');
    if (options['no_spam'] == true) optList.add('No spam or repetitive posts');

    return _card(
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Core rules', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('1) No insults', style: TextStyle(color: muted, fontSize: 11)),
          Text('2) No discrimination', style: TextStyle(color: muted, fontSize: 11)),
          Text('3) Be civil', style: TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 6),
          Text('Definitions', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
          Text('No insults: no attacks on people, ideas, or beliefs.', style: TextStyle(color: muted, fontSize: 11)),
          Text('No discrimination: no hate or bias against groups.', style: TextStyle(color: muted, fontSize: 11)),
          Text('Be civil: respectful tone, even when you disagree.', style: TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 10),
          Text('Rule options', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (optList.isEmpty)
            Text('No extra rule options selected.', style: TextStyle(color: muted, fontSize: 11))
          else
            ...optList.map((o) => Text('- $o', style: TextStyle(color: muted, fontSize: 11))),
          const SizedBox(height: 10),
          Text('Guidelines', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (guidelines.isEmpty)
            Text('No extra guidelines.', style: TextStyle(color: muted, fontSize: 11))
          else
            ...guidelines.map((g) => Text('- $g', style: TextStyle(color: muted, fontSize: 11))),
          const SizedBox(height: 8),
          Text('Optional quiz: $quizOptional', style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _discussionCard(Color fg, Color muted, ColorScheme scheme, Color border) {
    return _card(
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discussion', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          StreamBuilder<List<VetrinaMessage>>(
            stream: _repo.watchMessages(widget.vetrinaId),
            builder: (context, snap) {
              final items = snap.data ?? const <VetrinaMessage>[];
              if (items.isEmpty) {
                return Text('No messages yet.', style: TextStyle(color: muted, fontSize: 11));
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final m = items[index];
                  final flags = m.ai['flags'] is List
                      ? (m.ai['flags'] as List).map((e) => e.toString()).toList()
                      : const <String>[];
                  final moderation = (m.ai['moderation'] ?? 'ok').toString();
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.04 * 255).round()),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha((0.08 * 255).round())),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moderation == 'warned' ? '[Warned]' : 'Message',
                          style: TextStyle(color: muted, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(m.text, style: TextStyle(color: fg, fontSize: 13)),
                        if (flags.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Flags: ${flags.join(', ')}', style: TextStyle(color: muted, fontSize: 10)),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: 'Attach',
                onPressed: _showAttachSheet,
                icon: Icon(Icons.add_circle_outline, color: fg),
              ),
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  style: TextStyle(color: fg),
                  decoration: InputDecoration(
                    hintText: 'Write a message...',
                    hintStyle: TextStyle(color: muted),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withAlpha((0.06 * 255).round()),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withAlpha((0.12 * 255).round())),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _sending ? null : _sendMessage,
                child: Text(_sending ? '...' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachSheet() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Photo'),
                onTap: () => Navigator.pop(ctx, _AttachAction.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video'),
                onTap: () => Navigator.pop(ctx, _AttachAction.video),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Document'),
                onTap: () => Navigator.pop(ctx, _AttachAction.document),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Live camera'),
                onTap: () => Navigator.pop(ctx, _AttachAction.live),
              ),
            ],
          ),
        );
      },
    );
    if (action == null) return;
    switch (action) {
      case _AttachAction.photo:
        await _pickMedia(ImageSource.gallery, isVideo: false);
        break;
      case _AttachAction.video:
        await _pickMedia(ImageSource.gallery, isVideo: true);
        break;
      case _AttachAction.document:
        _showInfo('Document upload will be enabled next.');
        break;
      case _AttachAction.live:
        _showInfo('Live camera will be enabled next.');
        break;
    }
  }

  Future<void> _pickMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);
      if (file == null) return;
      _showInfo(isVideo ? 'Video selected.' : 'Photo selected.');
    } catch (_) {
      _showInfo('Could not open picker.');
    }
  }

  void _showInfo(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _actionBar(BuildContext context, Color fg, ColorScheme scheme) {
    final accessBtn = SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _repo.requestAccess(widget.vetrinaId),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2F6DD3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Join showcase'),
      ),
    );

    final shareBtn = SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text('Share', style: TextStyle(color: fg)),
      ),
    );

    final promoteBtn = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _handlePromote,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Promote'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );

    return Column(
      children: [
        accessBtn,
        const SizedBox(height: 10),
        shareBtn,
        const SizedBox(height: 10),
        promoteBtn,
      ],
    );
  }

}

enum _AttachAction { photo, video, document, live }
