import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';

import '../routes/app_routes.dart';
import '../services/external_link_service.dart';
import '../services/vetrina_repository.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';

class VetrinaCreateScreen extends StatefulWidget {
  const VetrinaCreateScreen({super.key});

  @override
  State<VetrinaCreateScreen> createState() => _VetrinaCreateScreenState();
}

class _VetrinaCreateScreenState extends State<VetrinaCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _guidelinesCtrl = TextEditingController();
  final _textDraftCtrl = TextEditingController();
  final _linkDraftCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _tone = 'amber';
  bool _busy = false;
  String? _error;
  bool _optCiteSources = true;
  bool _optStayOnTopic = true;
  bool _optRespectExpertise = false;
  bool _optNoSpam = true;
  final List<_DraftAttachment> _attachments = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    _coverCtrl.dispose();
    _guidelinesCtrl.dispose();
    _textDraftCtrl.dispose();
    _linkDraftCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Sign is required.';
      });
      return;
    }
    final tags = _tagsCtrl.text
        .split(RegExp(r'[;,]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final guidelines = _guidelinesCtrl.text
        .split(RegExp(r'[;,]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final id = await VetrinaRepository.I.createVetrina(
      title: title,
      theme: 'General',
      tags: tags,
      coverUrl: _coverCtrl.text.trim().isEmpty ? null : _coverCtrl.text.trim(),
      coverTone: _tone,
      guidelines: guidelines,
      ruleOptions: {
        'cite_sources_5w': _optCiteSources,
        'stay_on_topic': _optStayOnTopic,
        'respect_expertise': _optRespectExpertise,
        'no_spam': _optNoSpam,
      },
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (id == null) {
      setState(() => _error = 'Creation failed. Please try again.');
      return;
    }
    if (_attachments.isNotEmpty) {
      for (final att in _attachments) {
        await VetrinaRepository.I.addDraftPost(
          vetrinaId: id,
          type: att.type.name,
          label: att.label,
          text: att.text,
          url: att.url,
          localPath: att.localPath,
          mimeType: att.mimeType,
        );
      }
    }
    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.vetrinaDetail, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      appBar: AppBar(
        title: Text('Create Showcase', style: TextStyle(color: fg)),
        foregroundColor: fg,
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Creating…' : 'Create', style: TextStyle(color: fg)),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavStrip(current: BottomNavTab.chats),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).padding.bottom + 80,
          ),
          children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Sign (Showcase name)',
              hintText: 'e.g. Quantum Physics, World Affairs',
            ),
          ),
          const SizedBox(height: 10),
          _attachmentsCard(fg, muted, scheme),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Tags (keywords)',
              hintText: 'e.g. science, geopolitics, book',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _coverCtrl,
            decoration: const InputDecoration(
              labelText: 'Cover URL (optional)',
              hintText: 'Link to an image or video thumbnail',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _tone,
            decoration: const InputDecoration(labelText: 'Cover tone'),
            items: const [
              DropdownMenuItem(value: 'amber', child: Text('Amber')),
              DropdownMenuItem(value: 'blue', child: Text('Blue')),
              DropdownMenuItem(value: 'green', child: Text('Green')),
              DropdownMenuItem(value: 'red', child: Text('Red')),
              DropdownMenuItem(value: 'purple', child: Text('Purple')),
            ],
            onChanged: (v) => setState(() => _tone = v ?? 'amber'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _guidelinesCtrl,
            decoration: const InputDecoration(
              labelText: 'Guidelines (optional)',
              hintText: 'e.g. Read X, watch Y, use AI summaries',
            ),
          ),
          const SizedBox(height: 12),
          _coreRulesCard(fg, muted),
          const SizedBox(height: 12),
          _ruleOptionsCard(fg, muted, scheme),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _coreRulesCard(Color fg, Color muted) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Core rules', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('1) No insults', style: TextStyle(color: muted, fontSize: 12)),
          Text('2) No discrimination', style: TextStyle(color: muted, fontSize: 12)),
          Text('3) Be civil', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text('Definitions', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
          Text('No insults: no attacks on people, ideas, or beliefs.', style: TextStyle(color: muted, fontSize: 11)),
          Text('No discrimination: no hate or bias against groups.', style: TextStyle(color: muted, fontSize: 11)),
          Text('Be civil: respectful tone, even when you disagree.', style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _ruleOptionsCard(Color fg, Color muted, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rule options', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            value: _optCiteSources,
            onChanged: (v) => setState(() => _optCiteSources = v),
            contentPadding: EdgeInsets.zero,
            title: Text('Cite sources (5W baseline)', style: TextStyle(color: fg, fontSize: 13)),
          ),
          SwitchListTile.adaptive(
            value: _optStayOnTopic,
            onChanged: (v) => setState(() => _optStayOnTopic = v),
            contentPadding: EdgeInsets.zero,
            title: Text('Stay on topic', style: TextStyle(color: fg, fontSize: 13)),
          ),
          SwitchListTile.adaptive(
            value: _optRespectExpertise,
            onChanged: (v) => setState(() => _optRespectExpertise = v),
            contentPadding: EdgeInsets.zero,
            title: Text('Respect expertise level', style: TextStyle(color: fg, fontSize: 13)),
          ),
          SwitchListTile.adaptive(
            value: _optNoSpam,
            onChanged: (v) => setState(() => _optNoSpam = v),
            contentPadding: EdgeInsets.zero,
            title: Text('No spam or repetitive posts', style: TextStyle(color: fg, fontSize: 13)),
          ),
          Text(
            'These options guide Veil moderation.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _attachmentsCard(Color fg, Color muted, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Showcase content', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _attachChip('Photo', Icons.photo_outlined, _DraftType.photo),
              _attachChip('Video', Icons.videocam_outlined, _DraftType.video),
              _attachChip('Document', Icons.insert_drive_file_outlined, _DraftType.document),
              _attachChip('Live camera', Icons.videocam, _DraftType.live),
              _attachChip('Text', Icons.text_fields, _DraftType.text),
              _attachChip('Link', Icons.link, _DraftType.link),
            ],
          ),
          const SizedBox(height: 8),
          if (_showTextDraftField())
            TextField(
              controller: _textDraftCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Text content',
                hintText: 'Write the first message for this showcase...',
              ),
              onSubmitted: (_) => _addTextDraft(),
            ),
          if (_showLinkDraftField()) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _linkDraftCtrl,
              decoration: const InputDecoration(
                labelText: 'Link URL',
                hintText: 'https://...',
              ),
              onSubmitted: (_) => _addLinkDraft(),
            ),
          ],
          const SizedBox(height: 8),
          if (_attachments.isEmpty)
            Text('No content attached yet.', style: TextStyle(color: muted, fontSize: 11))
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _attachments.map((a) {
                return Chip(
                  label: Text(a.label),
                  onDeleted: () {
                    setState(() => _attachments.remove(a));
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 6),
          Text(
            'This is the first content shown in your showcase.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _attachChip(String label, IconData icon, _DraftType type) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: () => _handleAttach(type),
    );
  }

  Future<void> _handleAttach(_DraftType type) async {
    switch (type) {
      case _DraftType.photo:
        await _pickMedia(ImageSource.gallery, isVideo: false, type: type);
        break;
      case _DraftType.video:
        await _pickMedia(ImageSource.gallery, isVideo: true, type: type);
        break;
      case _DraftType.document:
        await _pickDocument();
        break;
      case _DraftType.live:
        await _startLiveSession();
        break;
      case _DraftType.text:
        _addTextDraft();
        break;
      case _DraftType.link:
        _addLinkDraft();
        break;
    }
  }

  Future<void> _pickMedia(
    ImageSource source, {
    required bool isVideo,
    required _DraftType type,
  }) async {
    try {
      final file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);
      if (file == null) return;
      _addAttachment(
        type,
        file.name.isEmpty ? (isVideo ? 'Video' : 'Photo') : file.name,
        localPath: file.path,
        mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
      );
    } catch (_) {
      _addAttachment(type, isVideo ? 'Video selected' : 'Photo selected');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final typeGroup = XTypeGroup(label: 'Documents');
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      _addAttachment(
        _DraftType.document,
        file.name,
        localPath: file.path,
        mimeType: file.mimeType,
      );
    } catch (_) {
      _addAttachment(_DraftType.document, 'Document selected');
    }
  }

  Future<void> _startLiveSession() async {
    final room = 'veil_live_${DateTime.now().millisecondsSinceEpoch}';
    final url = 'https://meet.jit.si/$room';
    final opened = await ExternalLinkService.openUrl(url);
    if (!opened) {
      _addAttachment(_DraftType.live, 'Live session link', url: url);
      return;
    }
    _addAttachment(_DraftType.live, 'Live session link', url: url);
  }

  void _addAttachment(
    _DraftType type,
    String label, {
    String? text,
    String? url,
    String? localPath,
    String? mimeType,
  }) {
    setState(() {
      _attachments.add(
        _DraftAttachment(
          type: type,
          label: label,
          text: text,
          url: url,
          localPath: localPath,
          mimeType: mimeType,
        ),
      );
    });
  }

  bool _showTextDraftField() {
    return _attachments.any((a) => a.type == _DraftType.text) ||
        _textDraftCtrl.text.trim().isNotEmpty;
  }

  bool _showLinkDraftField() {
    return _attachments.any((a) => a.type == _DraftType.link) ||
        _linkDraftCtrl.text.trim().isNotEmpty;
  }

  void _addTextDraft() {
    final text = _textDraftCtrl.text.trim();
    if (text.isEmpty) {
      _addAttachment(_DraftType.text, 'Text (pending)');
      return;
    }
    _addAttachment(_DraftType.text, 'Text', text: text);
  }

  void _addLinkDraft() {
    final url = _linkDraftCtrl.text.trim();
    if (url.isEmpty) {
      _addAttachment(_DraftType.link, 'Link (pending)');
      return;
    }
    _addAttachment(_DraftType.link, url, url: url);
  }
}

class _DraftAttachment {
  _DraftAttachment({
    required this.type,
    required this.label,
    this.text,
    this.url,
    this.localPath,
    this.mimeType,
  });

  final _DraftType type;
  final String label;
  final String? text;
  final String? url;
  final String? localPath;
  final String? mimeType;
}

enum _DraftType { photo, video, document, live, text, link }
