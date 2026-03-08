import 'package:apps/models/handbook_topic_doc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';

class HandbookTopicContentScreen extends StatefulWidget {
  final HandbookTopicDoc topic;
  final bool manageMode;
  final String? overrideTitle;
  final bool embedded;
  final VoidCallback? onBack;

  const HandbookTopicContentScreen({
    super.key,
    required this.topic,
    this.manageMode = false,
    this.overrideTitle,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<HandbookTopicContentScreen> createState() =>
      _HandbookTopicContentScreenState();
}

class _HandbookTopicContentScreenState
    extends State<HandbookTopicContentScreen> {
  static const _backgroundColor = Colors.white;
  static const _topBarColor = Color(0xFF1B5E20);

  final List<Map<String, dynamic>> _editBlocks = [];

  bool _editMode = false;
  bool _saving = false;
  bool _didInitBlocks = false;
  int _blockIdCounter = 0;

  DocumentReference<Map<String, dynamic>> get _contentRef => FirebaseFirestore
      .instance
      .collection('handbook_contents')
      .doc(widget.topic.id);

  void _initBlocks(List<dynamic> blocks) {
    if (_didInitBlocks) return;
    _editBlocks
      ..clear()
      ..addAll(
        blocks.whereType<Map>().map((block) {
          final normalized = Map<String, dynamic>.from(block);
          normalized['_id'] = (normalized['_id'] ?? '').toString().trim().isEmpty
              ? _nextBlockId()
              : normalized['_id'];
          return normalized;
        }),
      );
    _didInitBlocks = true;
  }

  String _nextBlockId() {
    _blockIdCounter++;
    return 'b_${DateTime.now().microsecondsSinceEpoch}_$_blockIdCounter';
  }

  void _toggleEditMode(List<dynamic> blocks) {
    if (_editMode) {
      setState(() {
        _editMode = false;
        _didInitBlocks = false;
        _editBlocks.clear();
      });
      return;
    }

    setState(() {
      _editMode = true;
      _didInitBlocks = false;
    });
    _initBlocks(blocks);
  }

  void _addBlock(String type) {
    setState(() {
      if (type == 'image') {
        _editBlocks.add({
          '_id': _nextBlockId(),
          'type': 'image',
          'url': '',
          'path': '',
          'caption': '',
        });
      } else if (type == 'subsection') {
        _editBlocks.add({
          '_id': _nextBlockId(),
          'type': 'subsection',
          'number': '',
          'title': '',
          'text': '',
        });
      } else {
        _editBlocks.add({'_id': _nextBlockId(), 'type': type, 'text': ''});
      }
    });
  }

  void _removeBlock(int index) {
    setState(() => _editBlocks.removeAt(index));
  }

  void _reorderBlocks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _editBlocks.removeAt(oldIndex);
      _editBlocks.insert(newIndex, item);
    });
  }

  Future<Map<String, String>?> _uploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('No file bytes returned. Please try another image.');
    }
    final name =
        (picked.name.isNotEmpty ? picked.name : 'image.jpg').replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
    final path =
        'handbook_images/${widget.topic.id}/${DateTime.now().millisecondsSinceEpoch}_$name';

    final ref = FirebaseStorage.instance.ref().child(path);
    final contentType = _contentTypeFromFileName(name);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    return {'url': url, 'path': path};
  }

  Future<void> _saveDraftContent({required bool hasDoc}) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await _contentRef.set({
        'topicId': widget.topic.id,
        'draftBlocks': _editBlocks,
        if (!hasDoc) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _editMode = false;
        _didInitBlocks = false;
        _editBlocks.clear();
      });
      _showSavedToast('Draft saved');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publishContent({required bool hasDoc}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _contentRef.set({
        'topicId': widget.topic.id,
        'draftBlocks': _editBlocks,
        'publishedBlocks': _editBlocks,
        'blocks': _editBlocks,
        'isPublished': true,
        if (!hasDoc) 'createdAt': FieldValue.serverTimestamp(),
        'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _editMode = false;
        _didInitBlocks = false;
        _editBlocks.clear();
      });
      _showSavedToast('Content published');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSavedToast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: _topBarColor),
    );
  }

  Future<void> _openDraftForEdit() async {
    final snapshot = await _contentRef.get();
    final data = snapshot.data() ?? {};
    final publishedBlocks =
        (data['publishedBlocks'] as List<dynamic>?) ??
        (data['blocks'] as List<dynamic>? ?? []);
    final draftBlocks =
        (data['draftBlocks'] as List<dynamic>?) ?? publishedBlocks;
    _toggleEditMode(draftBlocks);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 430).clamp(1.0, 1.2);
    final pad = (16.0 * scale).clamp(16.0, 24.0);
    final showEmbeddedHeader = widget.embedded && (widget.manageMode || width < 900);

    final content = Container(
      color: _backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            if (!widget.embedded)
              Container(
                color: _topBarColor,
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed:
                          widget.onBack ??
                          () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.overrideTitle ??
                            (widget.manageMode
                                ? 'Manage ${widget.topic.code} ${widget.topic.title}'
                                : '${widget.topic.code} ${widget.topic.title}'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.manageMode)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : _openDraftForEdit,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_editMode ? 'Cancel' : 'Edit'),
                      ),
                    if (widget.manageMode && _editMode)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                final snapshot = await _contentRef.get();
                                await _saveDraftContent(hasDoc: snapshot.exists);
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save Draft'),
                      ),
                    if (widget.manageMode && _editMode)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                final snapshot = await _contentRef.get();
                                await _publishContent(hasDoc: snapshot.exists);
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Publish'),
                      ),
                  ],
                ),
              ),
            if (showEmbeddedHeader)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed:
                              widget.onBack ?? () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          tooltip: 'Back to topics',
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Handbook / Topic',
                                style: TextStyle(
                                  color: Color(0xFF6D7F62),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.topic.code} ${widget.topic.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF1F2A1F),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.manageMode)
                          OutlinedButton(
                            onPressed: _saving ? null : _openDraftForEdit,
                            child: Text(_editMode ? 'Cancel' : 'Edit'),
                          ),
                      ],
                    ),
                    if (widget.manageMode && _editMode) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final snapshot = await _contentRef.get();
                                    await _saveDraftContent(
                                      hasDoc: snapshot.exists,
                                    );
                                  },
                            child: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Draft'),
                          ),
                          FilledButton(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final snapshot = await _contentRef.get();
                                    await _publishContent(
                                      hasDoc: snapshot.exists,
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: _topBarColor,
                            ),
                            child: const Text('Publish'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _contentRef.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error:\n${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final doc = snapshot.data!;
                  final data = doc.data() ?? {};
                  final publishedBlocks =
                      (data['publishedBlocks'] as List<dynamic>?) ??
                      (data['blocks'] as List<dynamic>? ?? []);
                  final draftBlocks =
                      (data['draftBlocks'] as List<dynamic>?) ?? publishedBlocks;
                  final blocksForView = publishedBlocks;

                  if (!doc.exists && !_editMode) {
                    return const Center(
                      child: Text('No content found for this topic.'),
                    );
                  }

                  if (_editMode) {
                    _initBlocks(draftBlocks);
                    return _EditorBody(
                      blocks: _editBlocks,
                      scale: scale,
                      pad: pad,
                      onAddBlock: _addBlock,
                      onRemoveBlock: _removeBlock,
                      onReorder: _reorderBlocks,
                      onPickImage: (index) async {
                        try {
                          final upload = await _uploadImage();
                          if (upload == null || !mounted) return;
                          setState(() {
                            _editBlocks[index]['url'] = upload['url'] ?? '';
                            _editBlocks[index]['path'] = upload['path'] ?? '';
                          });
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Image upload failed: $e'),
                              backgroundColor: Colors.red.shade700,
                            ),
                          );
                        }
                      },
                      onUpdateText: (index, value) {
                        _editBlocks[index]['text'] = value;
                      },
                      onUpdateCaption: (index, value) {
                        _editBlocks[index]['caption'] = value;
                      },
                    );
                  }

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      14 * scale,
                      pad,
                      16 * scale,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: blocksForView
                          .map(
                            (block) => _BlockView(block: block, scale: scale),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            ),
            if (widget.manageMode && !_editMode)
              Container(
                width: double.infinity,
                color: const Color(0xFFE5EFE5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: const Text(
                  'Manage Mode: edit draft and publish when ready.',
                  style: TextStyle(
                    color: Color(0xFF2F6C44),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(backgroundColor: _backgroundColor, body: content);
  }
}

class _BlockView extends StatelessWidget {
  final dynamic block;
  final double scale;

  const _BlockView({required this.block, required this.scale});

  @override
  Widget build(BuildContext context) {
    final map = (block as Map).cast<String, dynamic>();
    final type = (map['type'] ?? 'p').toString();
    final text = (map['text'] ?? '').toString();
    final number = (map['number'] ?? '').toString();
    final title = (map['title'] ?? '').toString();

    if (type == 'image') {
      final url = (map['url'] ?? '').toString();
      final path = (map['path'] ?? '').toString();
      final caption = (map['caption'] ?? '').toString();

      return Padding(
        padding: EdgeInsets.only(bottom: 12 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HandbookImagePreview(url: url, storagePath: path),
            if (caption.isNotEmpty) ...[
              SizedBox(height: 6 * scale),
              Text(
                caption,
                style: TextStyle(
                  fontSize: (13.5 * scale).clamp(13.0, 15.0),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5B655A),
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (type == 'subsection') {
      final depth = _subsectionDepth(number);
      final leftPad = (depth - 1).clamp(0, 4) * 12.0;
      final heading = [
        if (number.trim().isNotEmpty) number.trim(),
        if (title.trim().isNotEmpty) title.trim(),
      ].join(' ');

      return Padding(
        padding: EdgeInsets.only(bottom: 10 * scale, left: leftPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading.isEmpty ? 'Untitled subsection' : heading,
              style: TextStyle(
                fontSize: (16 - (depth > 1 ? 1 : 0)).toDouble(),
                fontWeight: FontWeight.w900,
                height: 1.3,
                color: const Color(0xFF2B332B),
              ),
            ),
            if (text.trim().isNotEmpty) ...[
              SizedBox(height: 6 * scale),
              Text(
                text.trim(),
                style: TextStyle(
                  fontSize: (14.2 * scale).clamp(13.8, 15.6),
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: const Color(0xFF3D4438),
                ),
              ),
            ],
          ],
        ),
      );
    }

    switch (type) {
      case 'h1':
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: Text(
            text,
            style: TextStyle(
              fontSize: (22 * scale).clamp(20.0, 26.0),
              fontWeight: FontWeight.w900,
              height: 1.2,
              color: const Color(0xFF2B332B),
            ),
          ),
        );
      case 'h2':
        return Padding(
          padding: EdgeInsets.only(top: 10 * scale, bottom: 8 * scale),
          child: Text(
            text,
            style: TextStyle(
              fontSize: (18 * scale).clamp(17.0, 22.0),
              fontWeight: FontWeight.w900,
              height: 1.25,
              color: const Color(0xFF2B332B),
            ),
          ),
        );
      case 'p':
      default:
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: Text(
            text,
            style: TextStyle(
              fontSize: (14.5 * scale).clamp(14.0, 16.0),
              fontWeight: FontWeight.w600,
              height: 1.55,
              color: const Color(0xFF3D4438),
            ),
          ),
        );
    }
  }
}

class _EditorBody extends StatelessWidget {
  final List<Map<String, dynamic>> blocks;
  final double scale;
  final double pad;
  final void Function(String type) onAddBlock;
  final void Function(int index) onRemoveBlock;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Future<void> Function(int index) onPickImage;
  final void Function(int index, String value) onUpdateText;
  final void Function(int index, String value) onUpdateCaption;

  const _EditorBody({
    required this.blocks,
    required this.scale,
    required this.pad,
    required this.onAddBlock,
    required this.onRemoveBlock,
    required this.onReorder,
    required this.onPickImage,
    required this.onUpdateText,
    required this.onUpdateCaption,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onAddBlock('h1'),
                icon: const Icon(Icons.title_rounded),
                label: const Text('H1'),
              ),
              OutlinedButton.icon(
                onPressed: () => onAddBlock('h2'),
                icon: const Icon(Icons.title_outlined),
                label: const Text('H2'),
              ),
              OutlinedButton.icon(
                onPressed: () => onAddBlock('p'),
                icon: const Icon(Icons.notes_rounded),
                label: const Text('Paragraph'),
              ),
              OutlinedButton.icon(
                onPressed: () => onAddBlock('image'),
                icon: const Icon(Icons.image_rounded),
                label: const Text('Image'),
              ),
              OutlinedButton.icon(
                onPressed: () => onAddBlock('subsection'),
                icon: const Icon(Icons.format_list_numbered_rounded),
                label: const Text('Subsection'),
              ),
            ],
          ),
          SizedBox(height: 16 * scale),
          if (blocks.isEmpty) const Text('No blocks yet. Add one above.'),
          if (blocks.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: blocks.length,
              onReorder: onReorder,
              itemBuilder: (context, index) {
                final block = blocks[index];
                final blockId = (block['_id'] ?? 'idx_$index').toString();
                final type = (block['type'] ?? 'p').toString();
                final text = (block['text'] ?? '').toString();
                final url = (block['url'] ?? '').toString();
                final path = (block['path'] ?? '').toString();
                final caption = (block['caption'] ?? '').toString();
                final number = (block['number'] ?? '').toString();
                final title = (block['title'] ?? '').toString();

                return Container(
                  key: ValueKey(blockId),
                  margin: EdgeInsets.only(bottom: 12 * scale),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: Color(0xFF6D7F62),
                              ),
                            ),
                          ),
                          Text(
                            type.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => onRemoveBlock(index),
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Remove block',
                          ),
                        ],
                      ),
                      if (type == 'image') ...[
                        _HandbookImagePreview(
                          url: url,
                          storagePath: path,
                          height: 140,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => onPickImage(index),
                          icon: const Icon(Icons.upload_rounded),
                          label: const Text('Upload Image'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: caption,
                          onChanged: (value) => onUpdateCaption(index, value),
                          decoration: const InputDecoration(
                            labelText: 'Caption (optional)',
                          ),
                        ),
                      ] else if (type == 'subsection') ...[
                        TextFormField(
                          initialValue: number,
                          onChanged: (value) {
                            blocks[index]['number'] = value;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Subsection Number (e.g. 13.5.1)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: title,
                          onChanged: (value) {
                            blocks[index]['title'] = value;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Subsection Title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: text,
                          onChanged: (value) => onUpdateText(index, value),
                          maxLines: null,
                          decoration: const InputDecoration(
                            labelText: 'Optional paragraph under this subsection',
                          ),
                        ),
                      ] else ...[
                        TextFormField(
                          initialValue: text,
                          onChanged: (value) => onUpdateText(index, value),
                          maxLines: null,
                          decoration: const InputDecoration(labelText: 'Text'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HandbookImagePreview extends StatelessWidget {
  final String url;
  final String storagePath;
  final double height;

  const _HandbookImagePreview({
    required this.url,
    required this.storagePath,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedHandbookImage>(
      future: _resolveHandbookImage(url: url, storagePath: storagePath),
      builder: (context, snapshot) {
        final resolved = snapshot.data ?? const _ResolvedHandbookImage();
        if (snapshot.connectionState == ConnectionState.waiting &&
            resolved.url.isEmpty &&
            resolved.bytes == null) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E6E6),
              borderRadius: BorderRadius.circular(12),
            ),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (resolved.bytes == null && resolved.url.isEmpty) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E6E6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('Image not available')),
          );
        }

        if (resolved.bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              resolved.bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                height: height,
                color: const Color(0xFFE6E6E6),
                alignment: Alignment.center,
                child: const Text('Failed to load image'),
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            resolved.url,
            fit: BoxFit.cover,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            errorBuilder: (_, __, ___) => Container(
              height: height,
              color: const Color(0xFFE6E6E6),
              alignment: Alignment.center,
              child: const Text('Failed to load image'),
            ),
          ),
        );
      },
    );
  }
}

String _contentTypeFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return 'image/jpeg';
}

Future<_ResolvedHandbookImage> _resolveHandbookImage({
  required String url,
  required String storagePath,
}) async {
  final trimmedStoragePath = storagePath.trim();
  String? resolvedPath;
  if (trimmedStoragePath.isNotEmpty) {
    resolvedPath = trimmedStoragePath;
  } else {
    final trimmedUrl = url.trim();
    if (trimmedUrl.startsWith('gs://')) {
      try {
        resolvedPath = FirebaseStorage.instance.refFromURL(trimmedUrl).fullPath;
      } catch (_) {}
    } else if (trimmedUrl.startsWith('http://') ||
        trimmedUrl.startsWith('https://')) {
      resolvedPath = _extractStoragePathFromDownloadUrl(trimmedUrl);
    } else if (trimmedUrl.isNotEmpty && !trimmedUrl.contains('://')) {
      resolvedPath = trimmedUrl;
    }
  }

  if (resolvedPath != null && resolvedPath.isNotEmpty) {
    try {
      final ref = FirebaseStorage.instance.ref(resolvedPath);
      final bytes = await ref.getData(15 * 1024 * 1024);
      if (bytes != null && bytes.isNotEmpty) {
        return _ResolvedHandbookImage(
          url: await ref.getDownloadURL(),
          bytes: bytes,
        );
      }
    } catch (_) {}
    try {
      final refreshed = await FirebaseStorage.instance
          .ref(resolvedPath)
          .getDownloadURL();
      return _ResolvedHandbookImage(url: refreshed);
    } catch (_) {}
  }

  final trimmedUrl = url.trim();
  if (trimmedUrl.isEmpty) return const _ResolvedHandbookImage();

  if (trimmedUrl.startsWith('gs://')) {
    try {
      final refreshed = await FirebaseStorage.instance
          .refFromURL(trimmedUrl)
          .getDownloadURL();
      return _ResolvedHandbookImage(url: refreshed);
    } catch (_) {
      return const _ResolvedHandbookImage();
    }
  }

  if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
    return _ResolvedHandbookImage(url: trimmedUrl);
  }

  try {
    return _ResolvedHandbookImage(
      url: await FirebaseStorage.instance.ref(trimmedUrl).getDownloadURL(),
    );
  } catch (_) {
    return const _ResolvedHandbookImage();
  }
}

String? _extractStoragePathFromDownloadUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return null;
  if (!uri.host.contains('firebasestorage.googleapis.com')) return null;
  final path = uri.path;
  final marker = '/o/';
  final index = path.indexOf(marker);
  if (index < 0) return null;
  final encoded = path.substring(index + marker.length);
  if (encoded.isEmpty) return null;
  return Uri.decodeComponent(encoded);
}

class _ResolvedHandbookImage {
  final String url;
  final Uint8List? bytes;

  const _ResolvedHandbookImage({this.url = '', this.bytes});
}

int _subsectionDepth(String number) {
  final raw = number.trim();
  if (raw.isEmpty) return 1;
  final parts = raw.split('.').where((e) => e.trim().isNotEmpty).length;
  return parts <= 0 ? 1 : parts;
}
