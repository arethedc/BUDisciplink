import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:apps/models/handbook_node_doc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_ext;
import 'package:url_launcher/url_launcher.dart';

class HandbookDocsEditorPage extends StatefulWidget {
  const HandbookDocsEditorPage({super.key});

  @override
  State<HandbookDocsEditorPage> createState() => _HandbookDocsEditorPageState();
}

class _UnknownEmbedBuilder extends quill.EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => '__unknown_embed__';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embedType = embedContext.node.value.type;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Text(
        'Unsupported block: $embedType',
        style: const TextStyle(
          color: Color(0xFF6D7F62),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

enum _ImageHandleKind {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  rotate,
}

class _InteractiveImageEmbedBuilder extends quill.EmbedBuilder {
  const _InteractiveImageEmbedBuilder({
    required this.selectedOffset,
    required this.cropMode,
    required this.onSelect,
    required this.onHandleDrag,
    required this.onRotateDrag,
    required this.onRotateQuarterTurn,
  });

  final int? Function() selectedOffset;
  final bool Function() cropMode;
  final void Function(int offset) onSelect;
  final void Function(int offset, _ImageHandleKind handle, Offset delta)
  onHandleDrag;
  final void Function(int offset, double degreeDelta) onRotateDrag;
  final void Function(int offset) onRotateQuarterTurn;

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    final offset = node.documentOffset;
    final imageSource = node.value.data.toString();

    final styleMap = _parseStyleMap(
      node.style.attributes[quill.Attribute.style.key]?.value?.toString() ?? '',
    );

    final width =
        _tryParseDouble(
          node.style.attributes[quill.Attribute.width.key]?.value?.toString(),
        ) ??
        _tryParseDouble(styleMap['width']) ??
        420;
    final height =
        _tryParseDouble(
          node.style.attributes[quill.Attribute.height.key]?.value?.toString(),
        ) ??
        _tryParseDouble(styleMap['height']) ??
        (width * 0.62);

    final rotationDegrees = _tryParseDouble(styleMap['rotation']) ?? 0;
    final alignment = _normalizeAlignment(styleMap['alignment']);
    final displayMode = _normalizeDisplayMode(styleMap['displayMode']);
    final caption = _decodeCaption(styleMap['caption']);
    final cropLeft = (_tryParseDouble(styleMap['cropLeft']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropTop = (_tryParseDouble(styleMap['cropTop']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropRight = (_tryParseDouble(styleMap['cropRight']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropBottom = (_tryParseDouble(styleMap['cropBottom']) ?? 0).clamp(
      0.0,
      0.45,
    );

    return _InteractiveImageEmbedFrame(
      imageSource: imageSource,
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      alignment: alignment,
      displayMode: displayMode,
      caption: caption,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      readOnly: embedContext.readOnly,
      selected: selectedOffset() == offset,
      cropMode: cropMode(),
      onSelect: () => onSelect(offset),
      onHandleDrag: (handle, delta) => onHandleDrag(offset, handle, delta),
      onRotateDrag: (delta) => onRotateDrag(offset, delta),
      onRotateQuarterTurn: () => onRotateQuarterTurn(offset),
    );
  }

  static Map<String, String> _parseStyleMap(String style) {
    final map = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final value = parts.sublist(1).join(':').trim();
      if (name.isEmpty || value.isEmpty) continue;
      map[name] = value;
    }
    return map;
  }

  static double? _tryParseDouble(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.trim());
  }

  static String _normalizeAlignment(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'left' || value == 'right') return value;
    return 'center';
  }

  static String _normalizeDisplayMode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'full' || value == 'side') return value;
    return 'inline';
  }

  static String _decodeCaption(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }
}

class _InteractiveImageEmbedFrame extends StatelessWidget {
  const _InteractiveImageEmbedFrame({
    required this.imageSource,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.alignment,
    required this.displayMode,
    required this.caption,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.readOnly,
    required this.selected,
    required this.cropMode,
    required this.onSelect,
    required this.onHandleDrag,
    required this.onRotateDrag,
    required this.onRotateQuarterTurn,
  });

  final String imageSource;
  final double width;
  final double height;
  final double rotationDegrees;
  final String alignment;
  final String displayMode;
  final String caption;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final bool readOnly;
  final bool selected;
  final bool cropMode;
  final VoidCallback onSelect;
  final void Function(_ImageHandleKind handle, Offset delta) onHandleDrag;
  final void Function(double degreeDelta) onRotateDrag;
  final VoidCallback onRotateQuarterTurn;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: readOnly
          ? SystemMouseCursors.basic
          : selected
          ? SystemMouseCursors.grab
          : SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onSelect(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onTapDown: (_) => onSelect(),
          onPanDown: (_) => onSelect(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxContentWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 920.0;

              var safeWidth = width.clamp(120.0, 1200.0);
              final safeHeight = height.clamp(90.0, 1200.0);

              if (displayMode == 'full') {
                safeWidth = math.max(160.0, maxContentWidth - 6);
              } else if (displayMode == 'side') {
                safeWidth = math.min(safeWidth, maxContentWidth * 0.48);
              } else {
                safeWidth = math.min(safeWidth, maxContentWidth - 4);
              }

              final imageFrame = _buildEditableImageFrame(
                safeWidth: safeWidth,
                safeHeight: safeHeight,
              );
              final captionWidget = caption.trim().isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6D7F62),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );

              Widget content;
              if (displayMode == 'side') {
                final imageCard = SizedBox(width: safeWidth, child: imageFrame);
                final textCard = Expanded(
                  child: Container(
                    constraints: BoxConstraints(minHeight: safeHeight * 0.65),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8F7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Text(
                      caption.trim().isEmpty
                          ? 'Side image block. Add paragraph text above or below this image block.'
                          : caption,
                      style: const TextStyle(
                        color: Color(0xFF556655),
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
                final imageOnRight = alignment == 'right';
                content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!imageOnRight) imageCard,
                    const SizedBox(width: 12),
                    textCard,
                    if (imageOnRight) ...[const SizedBox(width: 12), imageCard],
                  ],
                );
              } else {
                content = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: safeWidth, child: imageFrame),
                    captionWidget,
                  ],
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: _blockAlignment(alignment),
                  child: content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Alignment _blockAlignment(String alignment) {
    if (alignment == 'left') return Alignment.centerLeft;
    if (alignment == 'right') return Alignment.centerRight;
    return Alignment.center;
  }

  Widget _buildEditableImageFrame({
    required double safeWidth,
    required double safeHeight,
  }) {
    final visibleWidthFactor = (1 - cropLeft - cropRight).clamp(0.10, 1.0);
    final visibleHeightFactor = (1 - cropTop - cropBottom).clamp(0.10, 1.0);
    final alignmentX = ((cropLeft - cropRight) / visibleWidthFactor).clamp(
      -1.0,
      1.0,
    );
    final alignmentY = ((cropTop - cropBottom) / visibleHeightFactor).clamp(
      -1.0,
      1.0,
    );
    final hasCrop =
        cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0;

    final imageWidget = _buildImageWidget(
      imageSource: imageSource,
      width: safeWidth,
      height: safeHeight,
      fit: hasCrop ? BoxFit.cover : BoxFit.contain,
    );

    final croppedImage = ClipRect(
      child: Align(
        alignment: Alignment(alignmentX, alignmentY),
        widthFactor: visibleWidthFactor,
        heightFactor: visibleHeightFactor,
        child: imageWidget,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: safeWidth,
          height: safeHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1B5E20)
                  : Colors.black.withValues(alpha: 0.06),
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Transform.rotate(
              angle: rotationDegrees * math.pi / 180,
              child: croppedImage,
            ),
          ),
        ),
        if (selected && !readOnly) ...[
          _handle(
            alignment: Alignment.topLeft,
            kind: _ImageHandleKind.topLeft,
            square: true,
          ),
          _handle(
            alignment: Alignment.topCenter,
            kind: _ImageHandleKind.top,
            square: true,
          ),
          _handle(
            alignment: Alignment.topRight,
            kind: _ImageHandleKind.topRight,
            square: true,
          ),
          _handle(
            alignment: Alignment.centerRight,
            kind: _ImageHandleKind.right,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomRight,
            kind: _ImageHandleKind.bottomRight,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomCenter,
            kind: _ImageHandleKind.bottom,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomLeft,
            kind: _ImageHandleKind.bottomLeft,
            square: true,
          ),
          _handle(
            alignment: Alignment.centerLeft,
            kind: _ImageHandleKind.left,
            square: true,
          ),
          _handle(
            alignment: const Alignment(0, -1.34),
            kind: _ImageHandleKind.rotate,
            square: false,
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                cropMode ? 'Crop handles' : 'Resize handles',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _handle({
    required Alignment alignment,
    required _ImageHandleKind kind,
    required bool square,
  }) {
    final handleSize = square ? 14.0 : 24.0;
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: _cursorForHandle(kind),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onSelect(),
          onPanUpdate: (details) {
            if (kind == _ImageHandleKind.rotate) {
              onRotateDrag(details.delta.dx * 0.45);
              return;
            }
            onHandleDrag(kind, details.delta);
          },
          onTap: kind == _ImageHandleKind.rotate ? onRotateQuarterTurn : null,
          child: Container(
            width: handleSize,
            height: handleSize,
            decoration: BoxDecoration(
              color: square ? Colors.white : const Color(0xFF1B5E20),
              borderRadius: BorderRadius.circular(square ? 3 : 99),
              border: Border.all(
                color: square ? const Color(0xFF1B5E20) : Colors.white,
                width: square ? 1.4 : 1,
              ),
            ),
            child: square
                ? null
                : const Icon(
                    Icons.rotate_right_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  MouseCursor _cursorForHandle(_ImageHandleKind kind) {
    switch (kind) {
      case _ImageHandleKind.top:
      case _ImageHandleKind.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _ImageHandleKind.left:
      case _ImageHandleKind.right:
        return SystemMouseCursors.resizeLeftRight;
      case _ImageHandleKind.topLeft:
      case _ImageHandleKind.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ImageHandleKind.topRight:
      case _ImageHandleKind.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case _ImageHandleKind.rotate:
        return SystemMouseCursors.grab;
    }
  }

  Widget _buildImageWidget({
    required String imageSource,
    required double width,
    required double height,
    required BoxFit fit,
  }) {
    final bytes = _tryDecodeDataUri(imageSource);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _imageError(width, height),
      );
    }
    return Image.network(
      imageSource,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _imageError(width, height),
    );
  }

  Widget _imageError(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF2F2F2),
      alignment: Alignment.center,
      child: const Text(
        'Image unavailable',
        style: TextStyle(color: Color(0xFF6D7F62), fontWeight: FontWeight.w700),
      ),
    );
  }

  Uint8List? _tryDecodeDataUri(String imageSource) {
    if (!imageSource.startsWith('data:image/')) return null;
    final commaIndex = imageSource.indexOf(',');
    if (commaIndex < 0 || commaIndex >= imageSource.length - 1) return null;
    final encoded = imageSource.substring(commaIndex + 1);
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}

class _ImageCropPreview extends StatelessWidget {
  const _ImageCropPreview({
    required this.imageSource,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
  });

  final String imageSource;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  @override
  Widget build(BuildContext context) {
    final visibleWidthFactor = (1 - cropLeft - cropRight).clamp(0.10, 1.0);
    final visibleHeightFactor = (1 - cropTop - cropBottom).clamp(0.10, 1.0);
    final alignmentX = ((cropLeft - cropRight) / visibleWidthFactor).clamp(
      -1.0,
      1.0,
    );
    final alignmentY = ((cropTop - cropBottom) / visibleHeightFactor).clamp(
      -1.0,
      1.0,
    );

    final previewImage = _buildImage();
    return ClipRect(
      child: Align(
        alignment: Alignment(alignmentX, alignmentY),
        widthFactor: visibleWidthFactor,
        heightFactor: visibleHeightFactor,
        child: previewImage,
      ),
    );
  }

  Widget _buildImage() {
    final bytes = _tryDecodeDataUri(imageSource);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
    }
    return Image.network(
      imageSource,
      fit: BoxFit.cover,
      width: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Container(
        alignment: Alignment.center,
        color: const Color(0xFFF2F2F2),
        child: const Text(
          'Image preview unavailable',
          style: TextStyle(
            color: Color(0xFF6D7F62),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Uint8List? _tryDecodeDataUri(String source) {
    if (!source.startsWith('data:image/')) return null;
    final commaIndex = source.indexOf(',');
    if (commaIndex < 0 || commaIndex >= source.length - 1) return null;
    final encoded = source.substring(commaIndex + 1);
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}

class _EditorSaveIntent extends Intent {
  const _EditorSaveIntent();
}

@immutable
class _EditorSaveViewState {
  const _EditorSaveViewState({
    required this.message,
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.autoSaveEnabled,
  });

  final String message;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final bool autoSaveEnabled;
}

class _HandbookDocsEditorPageState extends State<HandbookDocsEditorPage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _text = Color(0xFF1F2A1F);
  static const _muted = Color(0xFF6D7F62);
  static const _autosaveDebounce = Duration(seconds: 1);

  static const _nodeTypes = <String>[
    'policy',
    'procedure',
    'service',
    'info',
    'appendix',
  ];

  static const _categories = <String>[
    'general',
    'student_conduct',
    'academic',
    'administrative',
    'office_service',
    'legal',
  ];

  final _db = FirebaseFirestore.instance;
  final _titleCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _linkedOfficeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _editorFocusNode = FocusNode(debugLabel: 'handbook_editor_focus');
  final _editorScrollController = ScrollController();
  final ValueNotifier<_EditorSaveViewState> _saveViewState = ValueNotifier(
    const _EditorSaveViewState(
      message: 'Saved',
      isSaving: false,
      hasUnsavedChanges: false,
      autoSaveEnabled: false,
    ),
  );

  quill.QuillController _editorController = quill.QuillController.basic();
  late final List<quill.EmbedBuilder> _embedBuilders;
  StreamSubscription<quill.DocChange>? _docChangeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nodeSub;
  Timer? _autosaveTimer;
  Timer? _imageStyleFlushTimer;
  int? _pendingImageStyleOffset;
  Map<String, String>? _pendingImageStyleMap;

  bool _loadingContext = true;
  String? _contextError;
  String? _handbookId;
  String _handbookVersion = '--';
  String _treeSnapshotSignature = '';

  List<HandbookNodeDoc> _nodes = const [];
  final Set<String> _expandedNodeIds = <String>{};
  String? _selectedNodeId;
  int? _activeImageOffset;
  bool _imageCropMode = false;
  bool _imageInteractionMode = false;
  bool _previewMode = false;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _suppressDirty = false;
  bool _autoSaveEnabled = false;
  Future<void>? _saveInFlight;
  int _editVersion = 0;
  String _saveMessage = 'Saved';
  String _query = '';

  String _category = _categories.first;
  String _type = _nodeTypes.first;
  String _status = 'draft';
  bool _visible = true;
  List<String> _tags = const [];
  List<Map<String, dynamic>> _attachments = const [];

  @override
  void initState() {
    super.initState();
    final fallbackBuilders = kIsWeb
        ? quill_ext.FlutterQuillEmbeds.editorWebBuilders()
        : quill_ext.FlutterQuillEmbeds.editorBuilders();
    _embedBuilders = [
      _InteractiveImageEmbedBuilder(
        selectedOffset: () => _activeImageOffset,
        cropMode: () => _imageCropMode,
        onSelect: _onImageOffsetSelected,
        onHandleDrag: _onImageHandleDrag,
        onRotateDrag: _onImageRotateDrag,
        onRotateQuarterTurn: _onImageRotateQuarterTurn,
      ),
      ...fallbackBuilders.where(
        (builder) => builder.key != quill.BlockEmbed.imageType,
      ),
    ];
    _bindEditorDocChanges();
    _titleCtrl.addListener(_onMetaChanged);
    _linkedOfficeCtrl.addListener(_onMetaChanged);
    _publishSaveViewState();
    _loadContext();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _imageStyleFlushTimer?.cancel();
    _docChangeSub?.cancel();
    _nodeSub?.cancel();
    _editorController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _saveViewState.dispose();
    _titleCtrl.dispose();
    _tagCtrl.dispose();
    _linkedOfficeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  HandbookNodeDoc? get _selectedNode => _nodeById(_selectedNodeId);

  HandbookNodeDoc? _nodeById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<HandbookNodeDoc> _childrenOf(String parentId) {
    final nodes = _nodes.where((node) => node.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return nodes;
  }

  List<HandbookNodeDoc> _rootNodes() => _childrenOf('');

  // Save state is pushed through a notifier so autosave status updates do not
  // trigger full-page rebuilds (which can steal focus in web editors).
  void _publishSaveViewState() {
    _saveViewState.value = _EditorSaveViewState(
      message: _saveMessage,
      isSaving: _isSaving,
      hasUnsavedChanges: _hasUnsavedChanges,
      autoSaveEnabled: _autoSaveEnabled,
    );
  }

  // Keep realtime updates cheap while typing:
  // compare only fields that affect tree/properties chrome and ignore heavy
  // rich-text payload to avoid remount-like churn on every autosave snapshot.
  String _buildTreeSnapshotSignature(List<HandbookNodeDoc> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer
        ..write(node.id)
        ..write('|')
        ..write(node.parentId)
        ..write('|')
        ..write(node.sortOrder)
        ..write('|')
        ..write(node.title)
        ..write('|')
        ..write(node.type)
        ..write('|')
        ..write(node.category)
        ..write('|')
        ..write(node.status)
        ..write('|')
        ..write(node.isVisible ? '1' : '0')
        ..write('|')
        ..write(node.tags.join(','))
        ..write(';');
    }
    return buffer.toString();
  }

  String _normalizeCategory(String raw) {
    return _categories.contains(raw) ? raw : _categories.first;
  }

  String _normalizeType(String raw) {
    return _nodeTypes.contains(raw) ? raw : _nodeTypes.first;
  }

  quill.Document _parseDocument(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        final normalized = _normalizeLegacyEmbeds(decoded);
        return quill.Document.fromJson(normalized);
      }
    } catch (_) {}
    final plain = content.trim();
    if (plain.isNotEmpty) {
      return quill.Document()..insert(0, '$plain\n');
    }
    return quill.Document()..insert(0, '\n');
  }

  List<Map<String, dynamic>> _normalizeLegacyEmbeds(List<dynamic> rawOps) {
    final normalizedOps = <Map<String, dynamic>>[];

    for (final rawOp in rawOps) {
      if (rawOp is! Map) continue;
      final op = Map<String, dynamic>.from(rawOp);
      final insert = op['insert'];
      if (insert is Map) {
        final insertMap = Map<String, dynamic>.from(insert);
        final legacyTableData = insertMap['x-embed-table'];
        if (legacyTableData != null) {
          final tableText = legacyTableData.toString().trim();
          if (tableText.isNotEmpty) {
            normalizedOps.add({'insert': '\n$tableText\n'});
          }
          continue;
        }
      }
      normalizedOps.add(op);
    }

    if (normalizedOps.isEmpty) {
      return [
        {'insert': '\n'},
      ];
    }

    final lastInsert = normalizedOps.last['insert'];
    if (lastInsert is String && !lastInsert.endsWith('\n')) {
      normalizedOps.add({'insert': '\n'});
    }
    return normalizedOps;
  }

  Future<void> _loadContext() async {
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });

    try {
      final metaSnap = await _db
          .collection('handbook_meta')
          .doc('current')
          .get();
      final data = metaSnap.data() ?? const <String, dynamic>{};
      final activeVersion = (data['activeVersionId'] ?? '').toString().trim();
      if (activeVersion.isEmpty) {
        throw Exception('Missing handbook_meta/current.activeVersionId');
      }
      if (!mounted) return;
      setState(() {
        _handbookId = activeVersion;
        _handbookVersion = (data['activeVersionLabel'] ?? activeVersion)
            .toString()
            .trim();
        _loadingContext = false;
      });
      _bindNodes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contextError = e.toString();
        _loadingContext = false;
      });
    }
  }

  void _bindNodes() {
    final handbookId = _handbookId;
    if (handbookId == null || handbookId.isEmpty) return;
    _nodeSub?.cancel();
    _nodeSub = _db
        .collection('handbook_nodes')
        .where('handbookId', isEqualTo: handbookId)
        .snapshots()
        .listen(
          (snapshot) {
            final nodes = snapshot.docs.map(HandbookNodeDoc.fromDoc).toList()
              ..sort((a, b) {
                final parentCompare = a.parentId.compareTo(b.parentId);
                if (parentCompare != 0) return parentCompare;
                final orderCompare = a.sortOrder.compareTo(b.sortOrder);
                if (orderCompare != 0) return orderCompare;
                return a.title.compareTo(b.title);
              });
            final nextTreeSignature = _buildTreeSnapshotSignature(nodes);

            if (!mounted) return;
            final treeChanged = nextTreeSignature != _treeSnapshotSignature;
            if (treeChanged) {
              setState(() {
                _nodes = nodes;
                _treeSnapshotSignature = nextTreeSignature;
              });
            } else {
              _nodes = nodes;
            }

            final selectedId = _selectedNodeId;
            final hasSelectedNode =
                selectedId != null &&
                nodes.any((node) => node.id == selectedId);
            if (selectedId == null && nodes.isNotEmpty) {
              _switchToNode(nodes.first.id, force: true);
            } else if (selectedId != null && !hasSelectedNode) {
              if (nodes.isNotEmpty) {
                _switchToNode(nodes.first.id, force: true);
              } else {
                _resetEditorState();
              }
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _contextError = e.toString());
          },
        );
  }

  Future<void> _switchToNode(String nodeId, {bool force = false}) async {
    if (!force && nodeId == _selectedNodeId) return;
    await _saveNodeNow();
    final node = _nodeById(nodeId);
    if (node == null) return;
    _loadNodeToEditor(node);
  }

  void _loadNodeToEditor(HandbookNodeDoc node) {
    final oldController = _editorController;
    final document = _parseDocument(node.content);
    _editorController = quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _editorController.readOnly = false;
    _bindEditorDocChanges();
    oldController.dispose();

    setState(() {
      _selectedNodeId = node.id;
      _activeImageOffset = null;
      _imageCropMode = false;
      _imageInteractionMode = false;
      _previewMode = false;
      _suppressDirty = true;
      _titleCtrl.text = node.title;
      _category = _normalizeCategory(node.category);
      _type = _normalizeType(node.type);
      _status = node.isPublished ? 'published' : 'draft';
      _visible = node.isVisible;
      _tags = List<String>.from(node.tags);
      _attachments = List<Map<String, dynamic>>.from(node.attachments);
      _linkedOfficeCtrl.text = node.linkedOffice;
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
      _expandedNodeIds.add(node.parentId);
      _suppressDirty = false;
    });
    _publishSaveViewState();
  }

  void _bindEditorDocChanges() {
    _docChangeSub?.cancel();
    _docChangeSub = _editorController.document.changes.listen((_) {
      if (_suppressDirty) return;
      _markDirtyAndSchedule();
    });
  }

  void _onMetaChanged() {
    if (_suppressDirty) return;
    _markDirtyAndSchedule();
  }

  void _scheduleAutosaveDebounced() {
    _autosaveTimer?.cancel();
    if (!_autoSaveEnabled || !_hasUnsavedChanges) return;
    _autosaveTimer = Timer(_autosaveDebounce, _saveNodeNow);
  }

  void _markDirtyAndSchedule() {
    if (_selectedNode == null) return;
    _editVersion += 1;
    final shouldRefreshStatus =
        !_hasUnsavedChanges || _saveMessage == 'Saved' || _saveMessage == '';
    _hasUnsavedChanges = true;
    if (shouldRefreshStatus) {
      _saveMessage = 'Unsaved changes';
      _publishSaveViewState();
    }
    _scheduleAutosaveDebounced();
  }

  Future<void> _saveNodeNow() async {
    if (_isSaving) {
      final inFlight = _saveInFlight;
      if (inFlight != null) {
        await inFlight;
      }
      if (!_hasUnsavedChanges) return;
    }
    if (!_hasUnsavedChanges) return;
    final selected = _selectedNode;
    if (selected == null) return;

    _autosaveTimer?.cancel();
    final saveVersion = _editVersion;
    final payload = <String, dynamic>{
      'title': _titleCtrl.text.trim().isEmpty
          ? '(Untitled node)'
          : _titleCtrl.text.trim(),
      'content': jsonEncode(_editorController.document.toDelta().toJson()),
      'category': _category,
      'tags': _tags,
      'type': _type,
      'status': _status,
      'isVisible': _visible,
      'handbookVersion': _handbookVersion,
      'linkedOffice': _linkedOfficeCtrl.text.trim(),
      'attachments': _attachments,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final saveFuture = _db
        .collection('handbook_nodes')
        .doc(selected.id)
        .set(payload, SetOptions(merge: true));
    _saveInFlight = saveFuture;
    _isSaving = true;
    _saveMessage = 'Saving...';
    _publishSaveViewState();
    try {
      await saveFuture;
      if (!mounted) return;
      final stillCurrentNode = _selectedNodeId == selected.id;
      final changedDuringSave = _editVersion != saveVersion;
      if (!stillCurrentNode || changedDuringSave) {
        _hasUnsavedChanges = true;
        _saveMessage = 'Unsaved changes';
      } else {
        _hasUnsavedChanges = false;
        _saveMessage = 'Saved';
      }
      _publishSaveViewState();
    } catch (e) {
      if (!mounted) return;
      _saveMessage = 'Save failed';
      _publishSaveViewState();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      _saveInFlight = null;
      if (mounted) {
        _isSaving = false;
        _publishSaveViewState();
        _scheduleAutosaveDebounced();
      }
    }
  }

  Future<void> _createNode({required String parentId}) async {
    final titleCtrl = TextEditingController();
    String type = _nodeTypes.first;
    String category = _categories.first;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create handbook node'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: _nodeTypes
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => type = value);
                      },
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      items: _categories
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => category = value);
                      },
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;
    final handbookId = _handbookId;
    if (handbookId == null || handbookId.isEmpty) return;

    final title = titleCtrl.text.trim().isEmpty
        ? '(Untitled node)'
        : titleCtrl.text.trim();
    final siblings = _childrenOf(parentId);
    final nextSortOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;

    final nodeRef = _db.collection('handbook_nodes').doc();
    await nodeRef.set({
      'handbookId': handbookId,
      'parentId': parentId,
      'title': title,
      'content': jsonEncode(
        (quill.Document()..insert(0, '\n')).toDelta().toJson(),
      ),
      'category': category,
      'tags': const <String>[],
      'type': type,
      'sortOrder': nextSortOrder,
      'status': 'draft',
      'isVisible': true,
      'handbookVersion': _handbookVersion,
      'linkedOffice': '',
      'attachments': const <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      if (parentId.isNotEmpty) _expandedNodeIds.add(parentId);
    });
    await _switchToNode(nodeRef.id, force: true);
  }

  Future<void> _deleteNode(String nodeId) async {
    final target = _nodeById(nodeId);
    if (target == null) return;
    final descendants = _collectDescendants(nodeId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete node'),
          content: Text(
            descendants.isEmpty
                ? 'Delete "${target.title}"?'
                : 'Delete "${target.title}" and ${descendants.length} nested nodes?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final batch = _db.batch();
    batch.delete(_db.collection('handbook_nodes').doc(nodeId));
    for (final child in descendants) {
      batch.delete(_db.collection('handbook_nodes').doc(child.id));
    }
    await batch.commit();

    if (!mounted) return;
    if (_selectedNodeId == nodeId) setState(() => _selectedNodeId = null);
  }

  List<HandbookNodeDoc> _collectDescendants(String parentId) {
    final result = <HandbookNodeDoc>[];
    void walk(String pid) {
      final children = _childrenOf(pid);
      for (final child in children) {
        result.add(child);
        walk(child.id);
      }
    }

    walk(parentId);
    return result;
  }

  Future<void> _moveNodeWithinSiblings(String nodeId, int direction) async {
    final target = _nodeById(nodeId);
    if (target == null) return;
    final siblings = _childrenOf(target.parentId);
    final currentIndex = siblings.indexWhere((n) => n.id == nodeId);
    if (currentIndex < 0) return;
    final newIndex = currentIndex + direction;
    if (newIndex < 0 || newIndex >= siblings.length) return;

    final reordered = [...siblings];
    final item = reordered.removeAt(currentIndex);
    reordered.insert(newIndex, item);

    final batch = _db.batch();
    for (var i = 0; i < reordered.length; i++) {
      batch.update(_db.collection('handbook_nodes').doc(reordered[i].id), {
        'sortOrder': i,
      });
    }
    await batch.commit();
  }

  Future<void> _setNodePublishState({
    required String nodeId,
    required String status,
  }) async {
    if (nodeId == _selectedNodeId) {
      setState(() => _status = status);
      _markDirtyAndSchedule();
      return;
    }

    await _db.collection('handbook_nodes').doc(nodeId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool _isDescendantOf(String nodeId, String potentialAncestorId) {
    var cursor = _nodeById(nodeId);
    final visited = <String>{};
    while (cursor != null && cursor.parentId.isNotEmpty) {
      if (visited.contains(cursor.id)) break;
      visited.add(cursor.id);
      if (cursor.parentId == potentialAncestorId) return true;
      cursor = _nodeById(cursor.parentId);
    }
    return false;
  }

  Future<void> _moveNodeToParent(String nodeId, String newParentId) async {
    final moving = _nodeById(nodeId);
    if (moving == null) return;
    if (nodeId == newParentId) return;
    if (_isDescendantOf(newParentId, nodeId)) return;

    final targetParent = newParentId == '__root__' ? '' : newParentId;
    final siblings = _childrenOf(targetParent);
    final nextOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;

    await _db.collection('handbook_nodes').doc(nodeId).set({
      'parentId': targetParent,
      'sortOrder': nextOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      if (targetParent.isNotEmpty) _expandedNodeIds.add(targetParent);
    });
  }

  Future<void> _insertTableTemplate() async {
    var columns = 3;
    var rows = 3;
    final shouldInsert = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Insert table'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: columns,
                    items: List.generate(
                      8,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} columns'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => columns = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Columns',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rows,
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} rows'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => rows = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Rows',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Insert'),
                ),
              ],
            );
          },
        );
      },
    );
    if (shouldInsert != true) return;

    final tableText = _buildMarkdownTable(columns: columns, rows: rows);
    final index = _editorController.selection.baseOffset;
    final cursor = index < 0 ? _editorController.document.length - 1 : index;
    final text = '\n$tableText\n';
    _editorController.replaceText(
      cursor,
      0,
      text,
      TextSelection.collapsed(offset: cursor + text.length),
    );
  }

  String _buildMarkdownTable({required int columns, required int rows}) {
    final safeColumns = columns < 1 ? 1 : columns;
    final safeRows = rows < 1 ? 1 : rows;

    final header = List.generate(
      safeColumns,
      (index) => 'Column ${index + 1}',
    ).join(' | ');
    final divider = List.filled(safeColumns, '---').join(' | ');

    final lines = <String>['| $header |', '| $divider |'];
    for (var rowIndex = 0; rowIndex < safeRows; rowIndex++) {
      final row = List.generate(
        safeColumns,
        (cellIndex) => 'Value ${rowIndex + 1}.${cellIndex + 1}',
      ).join(' | ');
      lines.add('| $row |');
    }
    return lines.join('\n');
  }

  Future<void> _attachFile({required bool insertLinkIntoEditor}) async {
    final selected = _selectedNode;
    if (selected == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final safeName = (picked.name.isEmpty ? 'attachment' : picked.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'handbook_nodes/${selected.id}/attachments/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    final entry = <String, dynamic>{
      'name': picked.name,
      'url': url,
      'path': path,
      'size': picked.size,
      'uploadedAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      _attachments = [..._attachments, entry];
      _hasUnsavedChanges = true;
    });

    var insertedInEditor = false;
    if (insertLinkIntoEditor) {
      final index = _editorController.selection.baseOffset;
      final cursor = index < 0 ? _editorController.document.length - 1 : index;
      if (_isImageFileName(picked.name)) {
        final imageSource = _buildImageEmbedSource(
          fileName: picked.name,
          bytes: bytes,
          downloadUrl: url,
        );
        _editorController.replaceText(
          cursor,
          0,
          quill.BlockEmbed.image(imageSource),
          TextSelection.collapsed(offset: cursor + 1),
        );
        _editorController.replaceText(
          cursor + 1,
          0,
          '\n',
          TextSelection.collapsed(offset: cursor + 2),
        );
        insertedInEditor = true;
      } else {
        final text = '\n${picked.name}: $url\n';
        _editorController.replaceText(
          cursor,
          0,
          text,
          TextSelection.collapsed(offset: cursor + text.length),
        );
        insertedInEditor = true;
      }
    }

    if (!insertedInEditor) {
      _markDirtyAndSchedule();
    }
  }

  quill.OffsetValue<quill.Embed>? _selectedImageEmbed() {
    try {
      final embedNode = quill.getEmbedNode(
        _editorController,
        _editorController.selection.start,
      );
      if (embedNode.value.value.type == quill.BlockEmbed.imageType) {
        return embedNode;
      }
    } catch (_) {}
    return null;
  }

  void _onImageOffsetSelected(int imageOffset) {
    if (_previewMode) return;
    setState(() {
      _activeImageOffset = imageOffset;
      _imageInteractionMode = true;
    });
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;
    _editorController.updateSelection(
      TextSelection.collapsed(offset: imageOffset),
      quill.ChangeSource.local,
    );
  }

  void _setImageInteractionMode(bool enabled) {
    if (_imageInteractionMode == enabled) return;
    setState(() {
      _imageInteractionMode = enabled;
      if (!enabled) {
        _imageCropMode = false;
        _activeImageOffset = null;
      }
    });
    if (!enabled) {
      _editorController.skipRequestKeyboard = false;
      _editorFocusNode.requestFocus();
    } else {
      _editorFocusNode.unfocus();
    }
  }

  Map<String, String> _parseCssStyleMap(String style) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final value = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        values[name] = value;
      }
    }
    return values;
  }

  String _composeCssStyle(Map<String, String> values) {
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
  }

  int? _resolveImageOffset(int offset) {
    final maxOffset = _editorController.document.length - 1;
    final candidates = <int>{
      offset,
      offset - 1,
      offset + 1,
      _activeImageOffset ?? -1,
    };
    for (final candidate in candidates) {
      if (candidate < 0 || candidate > maxOffset) continue;
      try {
        final embed = quill.getEmbedNode(_editorController, candidate);
        if (embed.value.value.type == quill.BlockEmbed.imageType) {
          return embed.offset;
        }
      } catch (_) {}
    }
    return null;
  }

  String _imageStyleStringAt(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return '';
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return '';
    return node.style.attributes[quill.Attribute.style.key]?.value
            ?.toString() ??
        '';
  }

  bool _safeFormatImage(int offset, quill.Attribute<dynamic> attribute) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return false;
    try {
      // Image drag/resize emits dense pointer updates; if the embed offset goes
      // stale between frames, formatting should fail safely instead of throwing.
      _editorController
        ..skipRequestKeyboard = true
        ..formatText(resolvedOffset, 1, attribute);
      return true;
    } on FormatException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _imageStyleMap(int offset) {
    return _parseCssStyleMap(_imageStyleStringAt(offset));
  }

  double _styleDouble(
    Map<String, String> map,
    String key, {
    double fallback = 0,
  }) {
    return double.tryParse(map[key] ?? '') ?? fallback;
  }

  double? _readImageHeight(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return null;
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return null;
    final heightValue = node.style.attributes[quill.Attribute.height.key]?.value
        ?.toString();
    final styleMap = _imageStyleMap(resolvedOffset);
    final styleHeight = styleMap['height'];
    if (heightValue == null || heightValue.trim().isEmpty) {
      return double.tryParse(styleHeight ?? '');
    }
    return double.tryParse(heightValue) ?? double.tryParse(styleHeight ?? '');
  }

  void _setImageStyleMap(int offset, Map<String, String> styleMap) {
    final nextStyle = _composeCssStyle(styleMap);
    final currentStyle = _imageStyleStringAt(offset);
    if (nextStyle == currentStyle) return;
    _safeFormatImage(offset, quill.StyleAttribute(nextStyle));
  }

  void _setImageStyleMapThrottled(int offset, Map<String, String> styleMap) {
    _pendingImageStyleOffset = offset;
    _pendingImageStyleMap = Map<String, String>.from(styleMap);
    if (_imageStyleFlushTimer != null) return;
    _imageStyleFlushTimer = Timer(const Duration(milliseconds: 28), () {
      _imageStyleFlushTimer = null;
      final pendingOffset = _pendingImageStyleOffset;
      final pendingStyle = _pendingImageStyleMap;
      _pendingImageStyleOffset = null;
      _pendingImageStyleMap = null;
      if (pendingOffset == null || pendingStyle == null) return;
      _setImageStyleMap(pendingOffset, pendingStyle);
      if (_pendingImageStyleOffset != null && _pendingImageStyleMap != null) {
        _setImageStyleMapThrottled(
          _pendingImageStyleOffset!,
          _pendingImageStyleMap!,
        );
      }
    });
  }

  bool _isHorizontalHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.left ||
        handle == _ImageHandleKind.right ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isVerticalHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.top ||
        handle == _ImageHandleKind.bottom ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isLeftHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.left ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.bottomLeft;
  }

  bool _isRightHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.right ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isTopHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.top ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.topRight;
  }

  bool _isBottomHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.bottom ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.bottomRight;
  }

  void _onImageHandleDrag(int offset, _ImageHandleKind handle, Offset delta) {
    if (_previewMode || handle == _ImageHandleKind.rotate) return;
    if (_activeImageOffset != offset || !_imageInteractionMode) {
      setState(() {
        _activeImageOffset = offset;
        _imageInteractionMode = true;
      });
    }
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;

    final currentWidth = (_readImageWidth(offset) ?? 420).clamp(120, 1400);
    final currentHeight = (_readImageHeight(offset) ?? (currentWidth * 0.62))
        .clamp(90, 1400);
    final styleMap = _imageStyleMap(offset);

    if (_imageCropMode) {
      var cropLeft = _styleDouble(styleMap, 'cropLeft');
      var cropTop = _styleDouble(styleMap, 'cropTop');
      var cropRight = _styleDouble(styleMap, 'cropRight');
      var cropBottom = _styleDouble(styleMap, 'cropBottom');

      if (_isHorizontalHandle(handle)) {
        if (_isLeftHandle(handle)) {
          cropLeft += delta.dx / currentWidth;
        }
        if (_isRightHandle(handle)) {
          cropRight -= delta.dx / currentWidth;
        }
      }

      if (_isVerticalHandle(handle)) {
        if (_isTopHandle(handle)) {
          cropTop += delta.dy / currentHeight;
        }
        if (_isBottomHandle(handle)) {
          cropBottom -= delta.dy / currentHeight;
        }
      }

      cropLeft = cropLeft.clamp(0.0, 0.45);
      cropTop = cropTop.clamp(0.0, 0.45);
      cropRight = cropRight.clamp(0.0, 0.45);
      cropBottom = cropBottom.clamp(0.0, 0.45);

      final horizontalTotal = cropLeft + cropRight;
      if (horizontalTotal > 0.85) {
        final scale = 0.85 / horizontalTotal;
        cropLeft *= scale;
        cropRight *= scale;
      }
      final verticalTotal = cropTop + cropBottom;
      if (verticalTotal > 0.85) {
        final scale = 0.85 / verticalTotal;
        cropTop *= scale;
        cropBottom *= scale;
      }

      styleMap['cropLeft'] = cropLeft.toStringAsFixed(3);
      styleMap['cropTop'] = cropTop.toStringAsFixed(3);
      styleMap['cropRight'] = cropRight.toStringAsFixed(3);
      styleMap['cropBottom'] = cropBottom.toStringAsFixed(3);
      _setImageStyleMapThrottled(offset, styleMap);
      return;
    }

    var width = currentWidth.toDouble();
    var height = currentHeight.toDouble();

    if (_isHorizontalHandle(handle)) {
      if (_isRightHandle(handle)) width += delta.dx;
      if (_isLeftHandle(handle)) width -= delta.dx;
    }
    if (_isVerticalHandle(handle)) {
      if (_isBottomHandle(handle)) height += delta.dy;
      if (_isTopHandle(handle)) height -= delta.dy;
    }

    final updatedStyle = _imageStyleMap(offset);
    updatedStyle['width'] = width.clamp(120, 1400).toStringAsFixed(0);
    updatedStyle['height'] = height.clamp(90, 1400).toStringAsFixed(0);
    _setImageStyleMapThrottled(offset, updatedStyle);
  }

  void _onImageRotateDrag(int offset, double degreeDelta) {
    if (_previewMode) return;
    if (_activeImageOffset != offset || !_imageInteractionMode) {
      setState(() {
        _activeImageOffset = offset;
        _imageInteractionMode = true;
      });
    }
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;
    final styleMap = _imageStyleMap(offset);
    final currentRotation = _styleDouble(styleMap, 'rotation');
    var updatedRotation = currentRotation + degreeDelta;
    while (updatedRotation >= 360) {
      updatedRotation -= 360;
    }
    while (updatedRotation < 0) {
      updatedRotation += 360;
    }
    styleMap['rotation'] = updatedRotation.toStringAsFixed(2);
    _setImageStyleMapThrottled(offset, styleMap);
  }

  void _onImageRotateQuarterTurn(int offset) {
    _onImageRotateDrag(offset, 90);
  }

  void _rotateImageLeft(int offset) {
    _onImageRotateDrag(offset, -90);
  }

  void _rotateImageRight(int offset) {
    _onImageRotateDrag(offset, 90);
  }

  void _openImageCropEditor(int offset) {
    final styleMap = _imageStyleMap(offset);
    var cropLeft = _styleDouble(styleMap, 'cropLeft').clamp(0.0, 0.45);
    var cropTop = _styleDouble(styleMap, 'cropTop').clamp(0.0, 0.45);
    var cropRight = _styleDouble(styleMap, 'cropRight').clamp(0.0, 0.45);
    var cropBottom = _styleDouble(styleMap, 'cropBottom').clamp(0.0, 0.45);

    final imageSource = _imageSourceAtOffset(offset);
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void normalizeCrop() {
              final horizontalTotal = cropLeft + cropRight;
              if (horizontalTotal > 0.85) {
                final scale = 0.85 / horizontalTotal;
                cropLeft *= scale;
                cropRight *= scale;
              }
              final verticalTotal = cropTop + cropBottom;
              if (verticalTotal > 0.85) {
                final scale = 0.85 / verticalTotal;
                cropTop *= scale;
                cropBottom *= scale;
              }
            }

            void updateCropValues() {
              normalizeCrop();
              final updatedStyle = _imageStyleMap(offset);
              updatedStyle['cropLeft'] = cropLeft.toStringAsFixed(3);
              updatedStyle['cropTop'] = cropTop.toStringAsFixed(3);
              updatedStyle['cropRight'] = cropRight.toStringAsFixed(3);
              updatedStyle['cropBottom'] = cropBottom.toStringAsFixed(3);
              _setImageStyleMap(offset, updatedStyle);
            }

            return AlertDialog(
              title: const Text('Crop image'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageSource.isNotEmpty)
                        Container(
                          height: 190,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F4F3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: _ImageCropPreview(
                            imageSource: imageSource,
                            cropLeft: cropLeft,
                            cropTop: cropTop,
                            cropRight: cropRight,
                            cropBottom: cropBottom,
                          ),
                        ),
                      const SizedBox(height: 10),
                      _cropSlider(
                        label: 'Left',
                        value: cropLeft,
                        onChanged: (value) {
                          setDialogState(() {
                            cropLeft = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Top',
                        value: cropTop,
                        onChanged: (value) {
                          setDialogState(() {
                            cropTop = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Right',
                        value: cropRight,
                        onChanged: (value) {
                          setDialogState(() {
                            cropRight = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Bottom',
                        value: cropBottom,
                        onChanged: (value) {
                          setDialogState(() {
                            cropBottom = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final resetStyle = _imageStyleMap(offset);
                    resetStyle.remove('cropLeft');
                    resetStyle.remove('cropTop');
                    resetStyle.remove('cropRight');
                    resetStyle.remove('cropBottom');
                    _setImageStyleMap(offset, resetStyle);
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _imageSourceAtOffset(int offset) {
    final resolvedOffset = _resolveImageOffset(offset) ?? offset;
    final ops = _editorController.document.toDelta().toList();
    var cursor = 0;
    for (final op in ops) {
      final data = op.data;
      if (data is String) {
        cursor += data.length;
        continue;
      }
      if (data is Map) {
        if (cursor == resolvedOffset) {
          final source = data[quill.BlockEmbed.imageType];
          if (source != null) return source.toString();
        }
        cursor += 1;
      }
    }
    return '';
  }

  Widget _cropSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ${(value * 100).round()}%',
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        ),
        Slider(
          value: value,
          min: 0,
          max: 0.45,
          divisions: 45,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showImageLayoutTools() {
    final fallbackOffset = _activeImageOffset ?? _selectedImageEmbed()?.offset;
    if (fallbackOffset != null) {
      _onImageOffsetSelected(fallbackOffset);
    }
    _showImageLayoutSheet(forcedImageOffset: fallbackOffset);
  }

  void _showImageLayoutSheet({int? forcedImageOffset}) {
    final imageOffset =
        forcedImageOffset ??
        _activeImageOffset ??
        _selectedImageEmbed()?.offset;
    if (imageOffset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an image in the editor first.')),
      );
      return;
    }
    _onImageOffsetSelected(imageOffset);
    var previewWidth = _readImageWidth(imageOffset) ?? 360;
    var currentAlignment = _readImageAlignment(imageOffset);
    var currentDisplayMode = _readImageDisplayMode(imageOffset);
    final captionCtrl = TextEditingController(
      text: _readImageCaption(imageOffset),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Image options',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'Width',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${previewWidth.round()} px',
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: previewWidth.clamp(120, 960).toDouble(),
                      min: 120,
                      max: 960,
                      divisions: 84,
                      label: '${previewWidth.round()}',
                      onChanged: (value) =>
                          setSheetState(() => previewWidth = value),
                      onChangeEnd: (value) {
                        _setImageWidth(imageOffset, value);
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Small'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 220);
                            setSheetState(() => previewWidth = 220);
                          },
                        ),
                        ActionChip(
                          label: const Text('Medium'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 360);
                            setSheetState(() => previewWidth = 360);
                          },
                        ),
                        ActionChip(
                          label: const Text('Large'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 520);
                            setSheetState(() => previewWidth = 520);
                          },
                        ),
                        ActionChip(
                          label: const Text('Reset'),
                          onPressed: () {
                            _clearImageWidth(imageOffset);
                            setSheetState(() => previewWidth = 360);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Alignment',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Left'),
                          selected: currentAlignment == 'left',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'left');
                            setSheetState(() => currentAlignment = 'left');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Center'),
                          selected: currentAlignment == 'center',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'center');
                            setSheetState(() => currentAlignment = 'center');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Right'),
                          selected: currentAlignment == 'right',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'right');
                            setSheetState(() => currentAlignment = 'right');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Display mode',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Inline'),
                          selected: currentDisplayMode == 'inline',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'inline');
                            setSheetState(() => currentDisplayMode = 'inline');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Full Width'),
                          selected: currentDisplayMode == 'full',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'full');
                            setSheetState(() => currentDisplayMode = 'full');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Side Image'),
                          selected: currentDisplayMode == 'side',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'side');
                            setSheetState(() => currentDisplayMode = 'side');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _rotateImageLeft(imageOffset),
                          icon: const Icon(Icons.rotate_left_rounded),
                          label: const Text('Rotate Left'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _rotateImageRight(imageOffset),
                          icon: const Icon(Icons.rotate_right_rounded),
                          label: const Text('Rotate Right'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openImageCropEditor(imageOffset),
                          icon: const Icon(Icons.crop_rounded),
                          label: const Text('Crop Editor'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: captionCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Caption',
                        hintText: 'Add image caption',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) =>
                          _setImageCaption(imageOffset, value),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () =>
                            _setImageCaption(imageOffset, captionCtrl.text),
                        child: const Text('Apply Caption'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(captionCtrl.dispose);
  }

  double? _readImageWidth(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return null;
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return null;
    final widthValue = node.style.attributes[quill.Attribute.width.key]?.value
        ?.toString();
    final styleMap = _imageStyleMap(resolvedOffset);
    final styleWidth = styleMap['width'];
    if (widthValue == null || widthValue.trim().isEmpty) {
      return double.tryParse(styleWidth ?? '');
    }
    return double.tryParse(widthValue) ?? double.tryParse(styleWidth ?? '');
  }

  void _setImageWidth(int offset, double width) {
    final styleMap = _imageStyleMap(offset);
    styleMap['width'] = width.toStringAsFixed(0);
    _setImageStyleMap(offset, styleMap);
    _markDirtyAndSchedule();
  }

  void _clearImageWidth(int offset) {
    final styleMap = _imageStyleMap(offset);
    styleMap.remove('width');
    _setImageStyleMap(offset, styleMap);
    _markDirtyAndSchedule();
  }

  void _setImageAlignment(int offset, String alignment) {
    final currentStyle = _imageStyleStringAt(offset);
    final updatedStyle = _upsertCssStyle(
      currentStyle,
      'alignment',
      _normalizeImageAlignment(alignment),
    );

    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  String _upsertCssStyle(String style, String key, String value) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final val = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && val.isNotEmpty) {
        values[name] = val;
      }
    }
    values[key] = value;
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
  }

  String _normalizeImageAlignment(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'left' || normalized == 'right') return normalized;
    return 'center';
  }

  String _normalizeImageDisplayMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'full' || normalized == 'side') return normalized;
    return 'inline';
  }

  String _readImageAlignment(int offset) {
    final styleMap = _imageStyleMap(offset);
    return _normalizeImageAlignment(styleMap['alignment'] ?? 'center');
  }

  String _readImageDisplayMode(int offset) {
    final styleMap = _imageStyleMap(offset);
    return _normalizeImageDisplayMode(styleMap['displayMode'] ?? 'inline');
  }

  String _readImageCaption(int offset) {
    final styleMap = _imageStyleMap(offset);
    final raw = (styleMap['caption'] ?? '').trim();
    if (raw.isEmpty) return '';
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  void _setImageDisplayMode(int offset, String mode) {
    final currentStyle = _imageStyleStringAt(offset);
    final updatedStyle = _upsertCssStyle(
      currentStyle,
      'displayMode',
      _normalizeImageDisplayMode(mode),
    );
    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  void _setImageCaption(int offset, String caption) {
    final currentStyle = _imageStyleStringAt(offset);
    final encoded = caption.trim().isEmpty
        ? ''
        : Uri.encodeComponent(caption.trim());
    final updatedStyle = encoded.isEmpty
        ? _removeCssStyleKey(currentStyle, 'caption')
        : _upsertCssStyle(currentStyle, 'caption', encoded);
    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  String _removeCssStyleKey(String style, String key) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final val = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && val.isNotEmpty && name != key) {
        values[name] = val;
      }
    }
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
  }

  bool _isImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  String _buildImageEmbedSource({
    required String fileName,
    required List<int> bytes,
    required String downloadUrl,
  }) {
    if (!kIsWeb) return downloadUrl;
    final lower = fileName.toLowerCase();
    final mimeType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.gif')
        ? 'image/gif'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : lower.endsWith('.bmp')
        ? 'image/bmp'
        : lower.endsWith('.svg')
        ? 'image/svg+xml'
        : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  int _wordCount() {
    final plain = _editorController.document
        .toPlainText()
        .replaceAll('\uFFFC', ' ')
        .trim();
    if (plain.isEmpty) return 0;
    return plain.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length;
  }

  int _characterCount() {
    final plain = _editorController.document
        .toPlainText()
        .replaceAll('\uFFFC', '')
        .replaceAll('\n', ' ')
        .trimRight();
    return plain.length;
  }

  String _activeBlockLabel() {
    final attrs = _editorController.getSelectionStyle().attributes;
    final headerValue = attrs[quill.Attribute.header.key]?.value;
    if (headerValue != null) {
      return 'Heading ${headerValue.toString()}';
    }

    final listValue = attrs[quill.Attribute.list.key]?.value?.toString();
    if (listValue == 'ordered') return 'Numbered list';
    if (listValue == 'bullet') return 'Bulleted list';
    if (listValue == 'checked') return 'Checklist';

    if (attrs.containsKey(quill.Attribute.blockQuote.key)) return 'Quote';
    if (attrs.containsKey(quill.Attribute.codeBlock.key)) return 'Code block';
    return 'Paragraph';
  }

  Future<void> _handleInsertAction(String action) async {
    if (action == 'table') {
      await _insertTableTemplate();
      return;
    }
    if (action == 'image') {
      await _attachFile(insertLinkIntoEditor: true);
      return;
    }
    if (action == 'attachment') {
      await _attachFile(insertLinkIntoEditor: false);
      return;
    }
    if (action == 'link') {
      await _promptInsertLink();
      return;
    }
  }

  Future<void> _promptInsertLink() async {
    final selection = _editorController.selection;
    final length = (selection.end - selection.start).abs();
    final hasSelection = length > 0;

    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Insert link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasSelection)
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display text',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              if (!hasSelection) const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;

    if (hasSelection) {
      final start = selection.start < selection.end
          ? selection.start
          : selection.end;
      _editorController.formatText(
        start,
        length,
        quill.Attribute.fromKeyValue(quill.Attribute.link.key, url),
      );
      return;
    }

    final insertText = textCtrl.text.trim().isEmpty
        ? url
        : textCtrl.text.trim();
    final start = selection.start < 0 ? 0 : selection.start;
    _editorController.replaceText(
      start,
      0,
      insertText,
      TextSelection.collapsed(offset: start + insertText.length),
    );
    _editorController.formatText(
      start,
      insertText.length,
      quill.Attribute.fromKeyValue(quill.Attribute.link.key, url),
    );
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    setState(() {
      final updated = [..._attachments]..removeAt(index);
      _attachments = updated;
    });
    _markDirtyAndSchedule();
  }

  void _resetEditorState() {
    final old = _editorController;
    _editorController = quill.QuillController.basic();
    _editorController.readOnly = false;
    _bindEditorDocChanges();
    old.dispose();
    _titleCtrl.clear();
    _linkedOfficeCtrl.clear();
    setState(() {
      _selectedNodeId = null;
      _activeImageOffset = null;
      _imageCropMode = false;
      _imageInteractionMode = false;
      _tags = const [];
      _attachments = const [];
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
    });
    _publishSaveViewState();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_contextError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _contextError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _headerBar(),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1280;
                  final tablet = constraints.maxWidth >= 980 && !wide;

                  if (wide) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 330,
                            child: RepaintBoundary(child: _leftTreePanel()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RepaintBoundary(child: _editorPanel()),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 310,
                            child: RepaintBoundary(child: _propertiesPanel()),
                          ),
                        ],
                      ),
                    );
                  }

                  if (tablet) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 300,
                            child: RepaintBoundary(child: _leftTreePanel()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => FractionallySizedBox(
                                          heightFactor: 0.88,
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: _propertiesPanel(),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.tune_rounded),
                                    label: const Text('Properties'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: RepaintBoundary(child: _editorPanel()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 6,
                          child: RepaintBoundary(child: _leftTreePanel()),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 8,
                          child: RepaintBoundary(child: _editorPanel()),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: ValueListenableBuilder<_EditorSaveViewState>(
        valueListenable: _saveViewState,
        builder: (context, saveState, child) {
          return Row(
            children: [
              const Icon(Icons.description_rounded, color: _primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Handbook Docs Editor',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              _statusChip('Version', _handbookVersion),
              const SizedBox(width: 8),
              _statusChip(
                'Save',
                saveState.autoSaveEnabled
                    ? 'Auto | ${saveState.message}'
                    : saveState.message,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  _autoSaveEnabled = !_autoSaveEnabled;
                  if (!_autoSaveEnabled) {
                    _autosaveTimer?.cancel();
                  } else {
                    _scheduleAutosaveDebounced();
                  }
                  _publishSaveViewState();
                },
                icon: Icon(
                  saveState.autoSaveEnabled
                      ? Icons.sync_rounded
                      : Icons.sync_disabled_rounded,
                ),
                label: Text(saveState.autoSaveEnabled ? 'Auto On' : 'Auto Off'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _selectedNode == null
                    ? null
                    : () => setState(() {
                        _previewMode = !_previewMode;
                        _editorController.readOnly = _previewMode;
                      }),
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: Icon(
                  _previewMode ? Icons.edit_rounded : Icons.visibility_rounded,
                ),
                label: Text(_previewMode ? 'Edit' : 'Preview'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.15)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _surface({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _leftTreePanel() {
    final roots = _rootNodes().where(_matchesNodeOrDescendant).toList();
    return _surface(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Handbook Structure',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _createNode(parentId: ''),
                  icon: const Icon(Icons.add_circle_rounded, color: _primary),
                  tooltip: 'Add root node',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search nodes',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) => true,
              onAcceptWithDetails: (details) =>
                  _moveNodeToParent(details.data, '__root__'),
              builder: (context, candidateData, rejectedData) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: [
                    if (candidateData.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _primary.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Text(
                          'Drop here to move as root',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (roots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'No nodes yet. Add your first node.',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ...roots.map((node) => _treeNodeTile(node: node, depth: 0)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _treeNodeTile({required HandbookNodeDoc node, required int depth}) {
    final children = _childrenOf(node.id);
    final selected = _selectedNodeId == node.id;
    final expanded = _query.isNotEmpty || _expandedNodeIds.contains(node.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final draggingId = details.data;
            if (draggingId == node.id) return false;
            if (_isDescendantOf(node.id, draggingId)) return false;
            return true;
          },
          onAcceptWithDetails: (details) =>
              _moveNodeToParent(details.data, node.id),
          builder: (context, candidateData, rejectedData) {
            return LongPressDraggable<String>(
              data: node.id,
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _primary.withValues(alpha: 0.3)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 8),
                    ],
                  ),
                  child: Text(
                    node.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                margin: EdgeInsets.only(left: depth * 18.0, bottom: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? _primary.withValues(alpha: 0.10)
                      : candidateData.isNotEmpty
                      ? _primary.withValues(alpha: 0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? _primary.withValues(alpha: 0.32)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _switchToNode(node.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        if (children.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (expanded) {
                                  _expandedNodeIds.remove(node.id);
                                } else {
                                  _expandedNodeIds.add(node.id);
                                }
                              });
                            },
                            icon: Icon(
                              expanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                            ),
                            visualDensity: VisualDensity.compact,
                          )
                        else
                          const SizedBox(width: 28),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _text,
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  _tinyBadge(node.type),
                                  const SizedBox(width: 4),
                                  _tinyBadge(node.status),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _moveNodeWithinSiblings(node.id, -1),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 17,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _moveNodeWithinSiblings(node.id, 1),
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 17,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'add_child') {
                              _createNode(parentId: node.id);
                            } else if (value == 'publish') {
                              _setNodePublishState(
                                nodeId: node.id,
                                status: 'published',
                              );
                            } else if (value == 'unpublish') {
                              _setNodePublishState(
                                nodeId: node.id,
                                status: 'draft',
                              );
                            } else if (value == 'delete') {
                              _deleteNode(node.id);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'add_child',
                              child: Text('Add child node'),
                            ),
                            PopupMenuItem(
                              value: 'publish',
                              child: Text('Publish'),
                            ),
                            PopupMenuItem(
                              value: 'unpublish',
                              child: Text('Unpublish'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (expanded)
          ...children
              .where(_matchesNodeOrDescendant)
              .map((child) => _treeNodeTile(node: child, depth: depth + 1)),
      ],
    );
  }

  bool _matchesNodeOrDescendant(HandbookNodeDoc node) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final localHit =
        node.title.toLowerCase().contains(q) ||
        node.type.toLowerCase().contains(q) ||
        node.category.toLowerCase().contains(q) ||
        node.tags.any((tag) => tag.toLowerCase().contains(q));
    if (localHit) return true;
    return _childrenOf(node.id).any(_matchesNodeOrDescendant);
  }

  Widget _tinyBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _editorPanel() {
    if (_selectedNode == null) {
      return _surface(
        child: const Center(
          child: Text(
            'Select a node to start editing.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final currentImageOffset =
        _activeImageOffset ?? _selectedImageEmbed()?.offset;
    final hasSelectedImage = currentImageOffset != null;

    final editorWidget = quill.QuillEditor.basic(
      controller: _editorController,
      focusNode: _editorFocusNode,
      scrollController: _editorScrollController,
      config: quill.QuillEditorConfig(
        scrollable: true,
        autoFocus: false,
        expands: false,
        showCursor: !_imageInteractionMode,
        onTapDown: (details, getPositionForOffset) {
          if (_imageInteractionMode) {
            return true;
          }
          return false;
        },
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 64),
        embedBuilders: _embedBuilders,
        unknownEmbedBuilder: const _UnknownEmbedBuilder(),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _EditorSaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _EditorSaveIntent(),
      },
      child: Actions(
        actions: {
          _EditorSaveIntent: CallbackAction<_EditorSaveIntent>(
            onInvoke: (intent) {
              _saveNodeNow();
              return null;
            },
          ),
        },
        child: _surface(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Node title',
                  ),
                ),
              ),
              const Divider(height: 1),
              if (!_previewMode)
                quill.QuillSimpleToolbar(
                  controller: _editorController,
                  config: quill.QuillSimpleToolbarConfig(
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showHeaderStyle: true,
                    showListBullets: true,
                    showListNumbers: true,
                    showQuote: true,
                    showLink: true,
                    showCodeBlock: true,
                    showAlignmentButtons: true,
                    showLeftAlignment: true,
                    showCenterAlignment: true,
                    showRightAlignment: true,
                    showJustifyAlignment: true,
                    showSearchButton: false,
                    showDirection: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showFontFamily: false,
                    showFontSize: true,
                    showUndo: true,
                    showRedo: true,
                    multiRowsDisplay: false,
                  ),
                ),
              if (_previewMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  color: _primary.withValues(alpha: 0.05),
                  child: const Text(
                    'Preview mode - read-only',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            PopupMenuButton<String>(
                              enabled: !_previewMode,
                              onSelected: _handleInsertAction,
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'table',
                                  child: Text('Table'),
                                ),
                                PopupMenuItem(
                                  value: 'image',
                                  child: Text('Inline Image'),
                                ),
                                PopupMenuItem(
                                  value: 'link',
                                  child: Text('Hyperlink'),
                                ),
                                PopupMenuItem(
                                  value: 'attachment',
                                  child: Text('Attachment'),
                                ),
                              ],
                              child: IgnorePointer(
                                child: OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.add_box_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Insert'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _previewMode
                                  ? null
                                  : _showImageLayoutTools,
                              icon: const Icon(
                                Icons.photo_size_select_large,
                                size: 18,
                              ),
                              label: const Text('Image Layout'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (!_previewMode && hasSelectedImage)
                                  ? () => _rotateImageLeft(currentImageOffset)
                                  : null,
                              icon: const Icon(
                                Icons.rotate_left_rounded,
                                size: 18,
                              ),
                              label: const Text('Rotate L'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (!_previewMode && hasSelectedImage)
                                  ? () => _rotateImageRight(currentImageOffset)
                                  : null,
                              icon: const Icon(
                                Icons.rotate_right_rounded,
                                size: 18,
                              ),
                              label: const Text('Rotate R'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (!_previewMode && hasSelectedImage)
                                  ? () {
                                      setState(() {
                                        _imageCropMode = !_imageCropMode;
                                      });
                                    }
                                  : null,
                              icon: Icon(
                                _imageCropMode
                                    ? Icons.crop_free_rounded
                                    : Icons.crop_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _imageCropMode ? 'Crop On' : 'Crop Off',
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (!_previewMode && hasSelectedImage)
                                  ? () {
                                      final styleMap = _imageStyleMap(
                                        currentImageOffset,
                                      );
                                      styleMap.remove('cropLeft');
                                      styleMap.remove('cropTop');
                                      styleMap.remove('cropRight');
                                      styleMap.remove('cropBottom');
                                      _setImageStyleMap(
                                        currentImageOffset,
                                        styleMap,
                                      );
                                      setState(() => _imageCropMode = false);
                                    }
                                  : null,
                              icon: const Icon(
                                Icons.filter_none_rounded,
                                size: 18,
                              ),
                              label: const Text('Clear Crop'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: !_previewMode && hasSelectedImage
                          ? () =>
                                _setImageInteractionMode(!_imageInteractionMode)
                          : null,
                      icon: Icon(
                        _imageInteractionMode
                            ? Icons.keyboard_rounded
                            : Icons.photo_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _imageInteractionMode ? 'Type Mode' : 'Image Mode',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _saveNodeNow,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save now'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 920),
                      margin: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListenableBuilder(
                        listenable: _editorController,
                        child: editorWidget,
                        builder: (context, child) {
                          final plain = _editorController.document
                              .toPlainText()
                              .replaceAll('\n', '')
                              .trim();
                          final showEmptyHint = plain.isEmpty && !_previewMode;
                          return Stack(
                            children: [
                              Positioned.fill(child: child!),
                              if (showEmptyHint)
                                const IgnorePointer(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      38,
                                      30,
                                      38,
                                      24,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        'Start writing this handbook section...',
                                        style: TextStyle(
                                          color: _muted,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              _editorStatusBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_editorController, _saveViewState]),
        builder: (context, child) {
          final saveState = _saveViewState.value;
          final words = _wordCount();
          final chars = _characterCount();
          final block = _activeBlockLabel();
          return Row(
            children: [
              Text(
                block,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$words words | $chars chars',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                saveState.autoSaveEnabled ? 'Autosave on' : 'Autosave off',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                saveState.message,
                style: TextStyle(
                  color: saveState.isSaving ? _primary : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ctrl/Cmd + S',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _propertiesPanel() {
    final selected = _selectedNode;
    return _surface(
      child: selected == null
          ? const Center(
              child: Text(
                'No node selected.',
                style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Properties',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _propertiesSection(
                      title: 'Classification',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _category,
                            items: _categories
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _category = value);
                              _markDirtyAndSchedule();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _type,
                            items: _nodeTypes
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _type = value);
                              _markDirtyAndSchedule();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Node type',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            items: const [
                              DropdownMenuItem(
                                value: 'draft',
                                child: Text('draft'),
                              ),
                              DropdownMenuItem(
                                value: 'published',
                                child: Text('published'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _status = value);
                              _markDirtyAndSchedule();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _propertiesSection(
                      title: 'Visibility',
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _visible,
                            onChanged: (value) {
                              setState(() => _visible = value);
                              _markDirtyAndSchedule();
                            },
                            title: const Text('Visible to readers'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _linkedOfficeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Linked office/service',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _propertiesSection(
                      title: 'Tags',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ..._tags.map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  onDeleted: () {
                                    setState(() {
                                      _tags = _tags
                                          .where((t) => t != tag)
                                          .toList();
                                    });
                                    _markDirtyAndSchedule();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tagCtrl,
                                  decoration: const InputDecoration(
                                    hintText: 'Add tag',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () {
                                  final tag = _tagCtrl.text.trim();
                                  if (tag.isEmpty || _tags.contains(tag)) {
                                    _tagCtrl.clear();
                                    return;
                                  }
                                  setState(() {
                                    _tags = [..._tags, tag];
                                    _tagCtrl.clear();
                                  });
                                  _markDirtyAndSchedule();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _primary,
                                ),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _propertiesSection(
                      title: 'Attachments',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _attachFile(insertLinkIntoEditor: false),
                            icon: const Icon(Icons.attach_file_rounded),
                            label: const Text('Attach file'),
                          ),
                          const SizedBox(height: 8),
                          if (_attachments.isEmpty)
                            const Text(
                              'No attachments',
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ..._attachments.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final name = (item['name'] ?? 'file').toString();
                            final url = (item['url'] ?? '').toString();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: url.isEmpty
                                        ? null
                                        : () => _openUrl(url),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _removeAttachment(index),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _propertiesSection(
                      title: 'Metadata',
                      child: Column(
                        children: [
                          _metaInfoRow('Node ID', selected.id),
                          _metaInfoRow('Handbook', selected.handbookId),
                          _metaInfoRow(
                            'Last updated',
                            selected.updatedAt?.toLocal().toString() ?? '--',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _propertiesSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _metaInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
