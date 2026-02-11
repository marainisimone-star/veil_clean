import 'package:flutter/material.dart';

import 'dart:io';

import '../models/vetrina.dart';
import '../models/vetrina_message.dart';
import '../models/vetrina_post.dart';
import '../routes/app_routes.dart';
import '../services/vetrina_repository.dart';
import '../services/vetrina_repository_base.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';
import '../widgets/mini_presence_dock.dart';

class VetrinaFeedScreen extends StatefulWidget {
  const VetrinaFeedScreen({
    super.key,
    this.repository,
    this.showBottomNav = true,
  });

  final VetrinaRepositoryBase? repository;
  final bool showBottomNav;

  @override
  State<VetrinaFeedScreen> createState() => _VetrinaFeedScreenState();
}

class _VetrinaFeedScreenState extends State<VetrinaFeedScreen> {
  late final VetrinaRepositoryBase _repo;
  late Future<List<Vetrina>> _future;
  Offset _contextMenuPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? VetrinaRepository.I;
    _future = _refresh();
  }

  Future<List<Vetrina>> _refresh() async {
    return _repo.fetchVetrine();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = Colors.white;
    final muted = Colors.white70;

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      useGradient: false,
      useOverlay: false,
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        title: Text('Vetrina Showcase', style: TextStyle(color: fg)),
        foregroundColor: fg,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.vetrinaCreate).then((_) {
                setState(() {
                  _future = _refresh();
                });
              });
            },
            child: Text('Create', style: TextStyle(color: fg)),
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
            child: FutureBuilder<List<Vetrina>>(
              future: _future,
              builder: (context, snap) {
                final items = snap.data ?? const <Vetrina>[];
                if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text('No showcases yet.', style: TextStyle(color: muted)),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _future = _refresh();
                    });
                    await _future;
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.of(context).padding.bottom + 80,
                    ),
                    children: [
                      _sectionTitle('Featured showcases', fg, muted),
                      const SizedBox(height: 10),
                      _vetrineColumn(items, scheme),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color fg, Color muted) {
    return Row(
      children: [
        Text(text, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('• Trending', style: TextStyle(color: muted, fontSize: 12)),
      ],
    );
  }

  Widget _vetrineColumn(List<Vetrina> items, ColorScheme scheme) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          Builder(builder: (_) {
            final v = items[i];
            return GestureDetector(
              onTapDown: (details) => _contextMenuPosition = details.globalPosition,
              onSecondaryTapDown: (details) => _contextMenuPosition = details.globalPosition,
              onSecondaryTap: () => _showContextMenu(v),
              onLongPress: () => _showContextMenu(v),
              child: InkWell(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.vetrinaDetail,
                  arguments: v,
                ),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B1B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withAlpha((0.10 * 255).round())),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerStrip(v, scheme),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StreamBuilder<List<VetrinaPost>>(
                              stream: _repo.watchPosts(v.id),
                              builder: (context, snap) {
                                final posts = snap.data ?? const <VetrinaPost>[];
                                final latest = posts.isNotEmpty ? posts.first : null;
                                if (latest == null) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Showcase content', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    _postPreview(latest),
                                    const SizedBox(height: 12),
                                  ],
                                );
                              },
                            ),
                            Text(
                              v.title,
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
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
                                  child: Text(t, style: TextStyle(color: Colors.white, fontSize: 11)),
                                );
                              }).toList(),
                            ),
                            StreamBuilder<List<VetrinaMessage>>(
                              stream: _repo.watchMessages(v.id),
                              builder: (context, snap) {
                                final msgs = snap.data ?? const <VetrinaMessage>[];
                                final latestMsg = msgs.isNotEmpty ? msgs.first : null;
                                if (latestMsg == null) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 10),
                                    Text('Latest discussion', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text(
                                      latestMsg.text,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _headerStrip(Vetrina v, ColorScheme scheme) {
    final tone = (v.coverTone ?? 'amber').toLowerCase();
    final colors = _toneColors(tone);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, color: scheme.onPrimary, size: 18),
            const SizedBox(width: 8),
            Text('Showcase', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _postPreview(VetrinaPost post) {
    final label = post.label.trim().isEmpty ? post.type : post.label;
    final localPath = post.localPath;
    final url = post.url;
    final isPhoto = post.type == 'photo';
    final isText = post.type == 'text';
    final isLink = post.type == 'link';
    final hasLocalFile = localPath != null && localPath.isNotEmpty && File(localPath).existsSync();
    final imageWidget = isPhoto && (url?.isNotEmpty == true || hasLocalFile)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: (url?.isNotEmpty == true)
                  ? Image.network(url!, fit: BoxFit.cover)
                  : Image.file(File(localPath!), fit: BoxFit.cover),
            ),
          )
        : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.06 * 255).round()),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha((0.10 * 255).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageWidget != null) ...[
            imageWidget,
            const SizedBox(height: 8),
          ],
          if (isText && (post.text?.isNotEmpty == true))
            Text(
              post.text!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else if (isLink && (post.url?.isNotEmpty == true))
            Text(
              post.url!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              '${post.type.toUpperCase()}: $label',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(Vetrina v) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = _contextMenuPosition == Offset.zero
        ? overlay.localToGlobal(overlay.size.center(Offset.zero))
        : _contextMenuPosition;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete showcase'),
        ),
      ],
    );
    if (!mounted) return;
    if (selected != 'delete') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete showcase?'),
        content: const Text('This will remove the showcase and its content.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true || !mounted) return;
    await _repo.deleteVetrina(v.id);
    if (!mounted) return;
    setState(() {
      _future = _refresh();
    });
  }

  List<Color> _toneColors(String tone) {
    switch (tone) {
      case 'blue':
        return const [Color(0xFF6FA8FF), Color(0xFF2F6DD3)];
      case 'green':
        return const [Color(0xFF6CE3B4), Color(0xFF1E9E6B)];
      case 'red':
        return const [Color(0xFFFF8A8A), Color(0xFFE04B4B)];
      case 'purple':
        return const [Color(0xFFB98CFF), Color(0xFF6C41C4)];
      default:
        return const [Color(0xFFFFC46B), Color(0xFFD47B2D)];
    }
  }

}
