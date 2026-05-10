import 'dart:async';

import 'package:flutter/material.dart';

enum AppNoticeTone { primary, success, danger, warning, neutral }

class AppScaffoldMessenger {
  static AppNoticeDispatcher of(BuildContext context) =>
      AppNoticeDispatcher(context);
}

class AppNoticeDispatcher {
  final BuildContext _context;

  const AppNoticeDispatcher(this._context);

  void showSnackBar(SnackBar bar) {
    final message = _extractMessage(bar.content);
    if (message.trim().isEmpty) return;
    _AppInlineNoticeHost.show(
      _context,
      message: message,
      tone: _toneFromSnackBar(bar),
      duration: bar.duration,
    );
  }

  static String _extractMessage(Widget content) {
    if (content is Text) {
      return content.data ?? content.textSpan?.toPlainText() ?? '';
    }
    if (content is RichText) return content.text.toPlainText();
    if (content is SelectableText) return content.data ?? '';
    if (content is DefaultTextStyle) return _extractMessage(content.child);
    if (content is Icon) return '';
    if (content is Row) {
      for (final child in content.children) {
        final text = _extractMessage(child);
        if (text.trim().isNotEmpty) return text;
      }
      return '';
    }
    if (content is Column) {
      for (final child in content.children) {
        final text = _extractMessage(child);
        if (text.trim().isNotEmpty) return text;
      }
      return '';
    }
    if (content is Padding) {
      final child = content.child;
      if (child != null) return _extractMessage(child);
      return '';
    }
    if (content is Expanded) return _extractMessage(content.child);
    if (content is Flexible) return _extractMessage(content.child);
    if (content is Container) {
      final child = content.child;
      if (child != null) return _extractMessage(child);
    }
    return '';
  }

  static AppNoticeTone _toneFromSnackBar(SnackBar bar) {
    final color = bar.backgroundColor;
    if (color == null) return AppNoticeTone.primary;

    final hsl = HSLColor.fromColor(color);
    final hue = hsl.hue;
    final sat = hsl.saturation;

    if (sat > 0.25) {
      if (hue >= 330 || hue < 20) return AppNoticeTone.danger;
      if (hue >= 20 && hue < 55) return AppNoticeTone.warning;
      if (hue >= 90 && hue < 170) return AppNoticeTone.success;
    }

    return AppNoticeTone.primary;
  }
}

class _AppInlineNoticeData {
  final String id;
  final String message;
  final AppNoticeTone tone;

  const _AppInlineNoticeData({
    required this.id,
    required this.message,
    required this.tone,
  });
}

class _AppInlineNoticeHost {
  final OverlayState _overlay;
  final ValueNotifier<List<_AppInlineNoticeData>> _items =
      ValueNotifier<List<_AppInlineNoticeData>>(<_AppInlineNoticeData>[]);
  final Map<String, Timer> _timers = <String, Timer>{};

  OverlayEntry? _entry;
  int _seq = 0;

  static final Map<OverlayState, _AppInlineNoticeHost> _hosts =
      <OverlayState, _AppInlineNoticeHost>{};

  _AppInlineNoticeHost._(this._overlay);

  static void show(
    BuildContext context, {
    required String message,
    AppNoticeTone tone = AppNoticeTone.primary,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final host = _hosts.putIfAbsent(
      overlay,
      () => _AppInlineNoticeHost._(overlay),
    );
    host._show(message: message, tone: tone, duration: duration);
  }

  void _show({
    required String message,
    required AppNoticeTone tone,
    required Duration duration,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    _ensureEntry();

    final id = 'app_notice_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final item = _AppInlineNoticeData(id: id, message: trimmed, tone: tone);

    const maxItems = 5;
    final next = <_AppInlineNoticeData>[item, ..._items.value];
    if (next.length > maxItems) {
      for (final dropped in next.skip(maxItems)) {
        _timers.remove(dropped.id)?.cancel();
      }
    }

    _items.value = next.take(maxItems).toList(growable: false);
    _timers[id] = Timer(duration, () => _remove(id));
  }

  void _remove(String id) {
    _timers.remove(id)?.cancel();
    final filtered = _items.value
        .where((n) => n.id != id)
        .toList(growable: false);
    if (filtered.length == _items.value.length) return;
    _items.value = filtered;

    if (filtered.isEmpty) {
      _entry?.remove();
      _entry = null;
    }
  }

  void _ensureEntry() {
    if (_entry != null) return;

    _entry = OverlayEntry(
      builder: (context) {
        final media = MediaQuery.of(context);
        final isMobile = media.size.width < 700;
        const topInset = 14.0;
        const bottomInset = 12.0;

        return Positioned.fill(
          child: SafeArea(
            child: ValueListenableBuilder<List<_AppInlineNoticeData>>(
              valueListenable: _items,
              builder: (context, notices, _) {
                if (notices.isEmpty) return const SizedBox.shrink();

                return Align(
                  alignment: isMobile
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isMobile ? 0 : topInset,
                      bottom: isMobile ? bottomInset : 0,
                      left: 12,
                      right: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      verticalDirection: isMobile
                          ? VerticalDirection.up
                          : VerticalDirection.down,
                      children: notices
                          .map((notice) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: isMobile
                                      ? media.size.width - 18
                                      : 560,
                                ),
                                child: _AppInlineNoticeCard(
                                  data: notice,
                                  onClose: () => _remove(notice.id),
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    _overlay.insert(_entry!);
  }
}

class _AppInlineNoticeCard extends StatelessWidget {
  final _AppInlineNoticeData data;
  final VoidCallback onClose;

  const _AppInlineNoticeCard({required this.data, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final title = switch (data.tone) {
      AppNoticeTone.primary => 'Notice',
      AppNoticeTone.success => 'Success',
      AppNoticeTone.danger => 'Error',
      AppNoticeTone.warning => 'Warning',
      AppNoticeTone.neutral => 'Update',
    };

    final scheme = switch (data.tone) {
      AppNoticeTone.primary => (
        bg: const Color(0xFFEAF7EE),
        fg: const Color(0xFF1B5E20),
        soft: const Color(0xFFD8EFDF),
        icon: Icons.info_outline_rounded,
      ),
      AppNoticeTone.success => (
        bg: const Color(0xFFE8F7ED),
        fg: const Color(0xFF2F855A),
        soft: const Color(0xFFD5F0DE),
        icon: Icons.check_circle_outline_rounded,
      ),
      AppNoticeTone.danger => (
        bg: const Color(0xFFFDECEE),
        fg: const Color(0xFFC53030),
        soft: const Color(0xFFF8DBDF),
        icon: Icons.cancel_outlined,
      ),
      AppNoticeTone.warning => (
        bg: const Color(0xFFFFF7E6),
        fg: const Color(0xFFB7791F),
        soft: const Color(0xFFF8EDCD),
        icon: Icons.warning_amber_rounded,
      ),
      AppNoticeTone.neutral => (
        bg: const Color(0xFFF2F3F5),
        fg: const Color(0xFF4A5568),
        soft: const Color(0xFFE5E8ED),
        icon: Icons.info_outline_rounded,
      ),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.fg.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.09),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.soft,
                shape: BoxShape.circle,
              ),
              child: Icon(scheme.icon, size: 18, color: scheme.fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.message,
                      style: TextStyle(
                        color: scheme.fg.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.2,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkResponse(
              radius: 16,
              splashColor: scheme.fg.withValues(alpha: 0.12),
              highlightColor: Colors.transparent,
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.close_rounded, size: 18, color: scheme.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
