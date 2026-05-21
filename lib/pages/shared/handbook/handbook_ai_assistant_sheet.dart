import 'dart:convert';

import 'package:apps/services/handbook_ai_service.dart';
import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> showHandbookAiAssistantSheet(BuildContext context) async {
  final media = MediaQuery.of(context);
  final isDesktop = media.size.width >= 1024;

  if (isDesktop) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Student HandBot',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _HandbookAiAssistantSheet(desktopSidePanel: true),
      transitionBuilder: (context, animation, _, child) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _HandbookAiAssistantSheet(desktopSidePanel: false),
  );
}

class _HandbookAiAssistantSheet extends StatefulWidget {
  final bool desktopSidePanel;

  const _HandbookAiAssistantSheet({required this.desktopSidePanel});

  @override
  State<_HandbookAiAssistantSheet> createState() =>
      _HandbookAiAssistantSheetState();
}

class _HandbookAiAssistantSheetState extends State<_HandbookAiAssistantSheet> {
  final _service = HandbookAiService();
  final _input = TextEditingController();
  final _historySearch = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatSessionRecord> _historySessions = <_ChatSessionRecord>[];
  static const int _maxHistorySessions = 30;
  static const _Message _welcomeMessage = _Message(
    fromUser: false,
    text: 'Bud is ready. Ask about policies, procedures, and handbook rules.',
    sources: <String>[],
    sourceRefs: <HandbookAiSourceRef>[],
  );
  late final List<_Message> _messages;
  late String _currentSessionId;
  late DateTime _currentSessionCreatedAt;
  late DateTime _currentSessionUpdatedAt;
  final List<String> _quickPrompts = const <String>[
    'What is the attendance policy?',
    'What happens for first-time violations?',
    'How do I file a leave of absence?',
    'What are the uniform policy rules?',
  ];

  bool _loading = false;
  bool _showHistoryPanel = false;
  String _historyQuery = '';

  @override
  void initState() {
    super.initState();
    _messages = <_Message>[_welcomeMessage];
    _currentSessionId = _newSessionId();
    _currentSessionCreatedAt = DateTime.now();
    _currentSessionUpdatedAt = _currentSessionCreatedAt;
    _loadHistoryFromStorage();
  }

  @override
  void dispose() {
    _input.dispose();
    _historySearch.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _persistChatSession() {
    final hasUserMessage = _messages.any((message) => message.fromUser);
    if (!hasUserMessage) {
      return;
    }

    final updatedAt = DateTime.now();
    _currentSessionUpdatedAt = updatedAt;
    final record = _ChatSessionRecord(
      id: _currentSessionId,
      topic: _deriveTopicFromMessages(_messages),
      createdAt: _currentSessionCreatedAt,
      updatedAt: _currentSessionUpdatedAt,
      messages: List<_Message>.from(_messages),
    );

    final existingIndex = _historySessions.indexWhere((r) => r.id == record.id);
    if (existingIndex >= 0) {
      _historySessions[existingIndex] = record;
    } else {
      _historySessions.add(record);
    }

    _historySessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_historySessions.length > _maxHistorySessions) {
      _historySessions.removeRange(
        _maxHistorySessions,
        _historySessions.length,
      );
    }
    _saveHistoryToStorage();
  }

  Future<void> _ask() async {
    final question = _input.text.trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _showHistoryPanel = false;
      _messages.add(
        _Message(
          fromUser: true,
          text: question,
          sources: const [],
          sourceRefs: const <HandbookAiSourceRef>[],
        ),
      );
      _loading = true;
      _input.clear();
    });
    _persistChatSession();
    _scrollToBottom();

    try {
      final answer = await _service.ask(question);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            fromUser: false,
            text: answer.text,
            sources: answer.sources,
            sourceRefs: answer.sourceRefs,
          ),
        );
      });
      _persistChatSession();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            fromUser: false,
            text: 'Could not get an AI response right now.\n\nDetails: $error',
            sources: const <String>[],
            sourceRefs: const <HandbookAiSourceRef>[],
          ),
        );
      });
      _persistChatSession();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      _scrollToBottom();
    }
  }

  void _askQuickPrompt(String prompt) {
    if (_loading) return;
    _input.text = prompt;
    _ask();
  }

  String _newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _historyStorageKey() {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    return uid.isEmpty ? 'handbot_history_guest' : 'handbot_history_$uid';
  }

  Future<void> _loadHistoryFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyStorageKey());
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final records = decoded
          .whereType<Map>()
          .map((rawRecord) {
            final map = rawRecord.cast<String, dynamic>();
            return _ChatSessionRecord.fromJson(map);
          })
          .whereType<_ChatSessionRecord>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _historySessions
          ..clear()
          ..addAll(records);
      });
    } catch (_) {}
  }

  Future<void> _saveHistoryToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_historySessions.isEmpty) {
        await prefs.remove(_historyStorageKey());
        return;
      }
      final encoded = jsonEncode(
        _historySessions.map((record) => record.toJson()).toList(),
      );
      await prefs.setString(_historyStorageKey(), encoded);
    } catch (_) {}
  }

  String _deriveTopicFromMessages(List<_Message> messages) {
    final candidates = messages
        .where((m) => m.fromUser && m.text.trim().isNotEmpty)
        .toList(growable: false);
    final raw = candidates.isEmpty ? 'Chat' : candidates.first.text.trim();
    if (raw.length <= 64) return raw;
    return '${raw.substring(0, 64)}...';
  }

  String _formatHistoryDate(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[value.month - 1];
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$month ${value.day}, ${value.year}  $hour:$minute $period';
  }

  void _toggleHistoryPanel() {
    setState(() {
      _showHistoryPanel = !_showHistoryPanel;
      if (!_showHistoryPanel) {
        _historySearch.clear();
        _historyQuery = '';
      }
    });
  }

  void _loadHistorySession(_ChatSessionRecord selected) {
    setState(() {
      _currentSessionId = selected.id;
      _currentSessionCreatedAt = selected.createdAt;
      _currentSessionUpdatedAt = selected.updatedAt;
      _messages
        ..clear()
        ..addAll(selected.messages);
      _loading = false;
      _showHistoryPanel = false;
      _historySearch.clear();
      _historyQuery = '';
    });
    _scrollToBottom();
  }

  List<_ChatSessionRecord> _filteredHistorySessions() {
    final sessions = List<_ChatSessionRecord>.from(_historySessions)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final q = _historyQuery.trim().toLowerCase();
    if (q.isEmpty) return sessions;
    return sessions
        .where((record) {
          final topic = record.topic.toLowerCase();
          final updated = _formatHistoryDate(record.updatedAt).toLowerCase();
          return topic.contains(q) || updated.contains(q);
        })
        .toList(growable: false);
  }

  Widget _buildHistoryPanel() {
    final sessions = _filteredHistorySessions();
    final hasAnyHistory = _historySessions.isNotEmpty;
    return Material(
      color: Colors.white,
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: Color(0xFF1B5E20),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Chat History',
                    style: TextStyle(
                      color: Color(0xFF1F2A1F),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _toggleHistoryPanel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF1B5E20),
                  tooltip: 'Close history',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _historySearch,
              onChanged: (value) => setState(() => _historyQuery = value),
              decoration: InputDecoration(
                hintText: 'Search topic or date',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Text(
                      hasAnyHistory
                          ? 'No matching chat history.'
                          : 'No chat history yet.',
                      style: const TextStyle(
                        color: Color(0xFF6D7F62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = sessions[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _loadHistorySession(record),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.topic,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF1F2A1F),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatHistoryDate(record.updatedAt),
                                  style: const TextStyle(
                                    color: Color(0xFF6D7F62),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
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
        ],
      ),
    );
  }

  Future<void> _openSource(HandbookAiSourceRef source) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final sectionId = source.sectionId.trim();
    final versionId = source.versionId.trim();

    setState(() => _showHistoryPanel = false);
    _persistChatSession();
    rootNavigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    rootNavigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _HandbookSourcePage(
          title: source.label,
          versionId: versionId,
          sectionId: sectionId,
          excerpt: source.excerpt,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildPanel({required bool desktop}) {
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: desktop ? 520 : double.infinity,
        maxHeight: desktop ? media.size.height - 24 : media.size.height * 0.92,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(desktop ? 18 : 16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF1B5E20),
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: desktop
                    ? (details) {
                        if (details.primaryVelocity != null &&
                            details.primaryVelocity! > 450) {
                          Navigator.of(context).maybePop();
                        }
                      }
                    : null,
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Student HandBot (Bud)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleHistoryPanel,
                      icon: Icon(
                        _showHistoryPanel
                            ? Icons.history_toggle_off_rounded
                            : Icons.history_rounded,
                      ),
                      color: Colors.white,
                      tooltip: 'Chat history',
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const _HandBotScrollBehavior(),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: desktop,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                12,
                              ),
                              itemCount: _messages.length + (_loading ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_loading && index == _messages.length) {
                                  return const _TypingBubble();
                                }
                                final msg = _messages[index];
                                return _MessageBubble(
                                  message: msg,
                                  onSourceTap: _openSource,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Color(0x1F000000)),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 34,
                              child: ScrollConfiguration(
                                behavior: const _HandBotScrollBehavior(),
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _quickPrompts.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final prompt = _quickPrompts[index];
                                    return ActionChip(
                                      onPressed: () => _askQuickPrompt(prompt),
                                      label: Text(
                                        prompt,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _input,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _ask(),
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Ask about policy, process, requirement, or sanction...',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _loading ? null : _ask,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.send_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_showHistoryPanel)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleHistoryPanel,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  if (_showHistoryPanel)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: desktop ? 380 : 340,
                        ),
                        child: _buildHistoryPanel(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    if (widget.desktopSidePanel) {
      return SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: _buildPanel(desktop: true),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _buildPanel(desktop: false),
        ),
      ),
    );
  }
}

class _Message {
  final bool fromUser;
  final String text;
  final List<String> sources;
  final List<HandbookAiSourceRef> sourceRefs;

  const _Message({
    required this.fromUser,
    required this.text,
    required this.sources,
    required this.sourceRefs,
  });

  Map<String, dynamic> toJson() {
    return {
      'fromUser': fromUser,
      'text': text,
      'sources': sources,
      'sourceRefs': sourceRefs
          .map(
            (r) => {
              'label': r.label,
              'sectionId': r.sectionId,
              'versionId': r.versionId,
              'excerpt': r.excerpt,
            },
          )
          .toList(growable: false),
    };
  }

  static _Message? fromJson(Map<String, dynamic> raw) {
    final text = (raw['text'] ?? '').toString();
    if (text.trim().isEmpty) return null;
    final sources = (raw['sources'] as List<dynamic>? ?? const [])
        .map((s) => s.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    final refs = (raw['sourceRefs'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((r) {
          final map = r.cast<String, dynamic>();
          final label = (map['label'] ?? '').toString().trim();
          if (label.isEmpty) return null;
          return HandbookAiSourceRef(
            label: label,
            sectionId: (map['sectionId'] ?? '').toString(),
            versionId: (map['versionId'] ?? '').toString(),
            excerpt: (map['excerpt'] ?? '').toString(),
          );
        })
        .whereType<HandbookAiSourceRef>()
        .toList(growable: false);
    return _Message(
      fromUser: raw['fromUser'] == true,
      text: text,
      sources: sources,
      sourceRefs: refs,
    );
  }
}

class _ChatSessionRecord {
  final String id;
  final String topic;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<_Message> messages;

  const _ChatSessionRecord({
    required this.id,
    required this.topic,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic': topic,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(growable: false),
    };
  }

  static _ChatSessionRecord? fromJson(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final topic = (raw['topic'] ?? '').toString().trim();
    if (id.isEmpty || topic.isEmpty) return null;
    final createdAtRaw = (raw['createdAt'] ?? '').toString();
    final updatedAtRaw = (raw['updatedAt'] ?? '').toString();
    final createdAt = DateTime.tryParse(createdAtRaw);
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (createdAt == null || updatedAt == null) return null;
    final messages = (raw['messages'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => _Message.fromJson(m.cast<String, dynamic>()))
        .whereType<_Message>()
        .toList(growable: false);
    if (messages.isEmpty) return null;
    return _ChatSessionRecord(
      id: id,
      topic: topic,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: messages,
    );
  }
}

class _HandbookSourcePage extends StatelessWidget {
  final String title;
  final String versionId;
  final String sectionId;
  final String excerpt;

  const _HandbookSourcePage({
    required this.title,
    required this.versionId,
    required this.sectionId,
    required this.excerpt,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Text(
          title.trim().isEmpty ? 'Handbook Source' : title.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
      body: HbHandbookPage(
        forcedVersionId: versionId.isEmpty ? null : versionId,
        forcedVersionLabel: versionId.isEmpty ? null : versionId,
        initialSectionId: sectionId.isEmpty ? null : sectionId,
        initialHighlightText: excerpt,
        openSelectedOnMobile: true,
        showAiFab: false,
        hideTopHeader: true,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _Message message;
  final ValueChanged<HandbookAiSourceRef>? onSourceTap;

  const _MessageBubble({required this.message, this.onSourceTap});

  @override
  Widget build(BuildContext context) {
    final align = message.fromUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bg = message.fromUser
        ? const Color(0xFF1B5E20)
        : const Color(0xFFFFFFFF);
    final fg = message.fromUser ? Colors.white : const Color(0xFF1F2A1F);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (message.sourceRefs.isNotEmpty) ...[
                const Text(
                  'Source',
                  style: TextStyle(
                    color: Color(0xFF6D7F62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: message.sourceRefs
                      .map(
                        (source) => InkWell(
                          onTap: onSourceTap == null
                              ? null
                              : () => onSourceTap!(source),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: Text(
                              source.label,
                              style: const TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ] else
                Text(
                  'Source: ${message.sources.join(", ")}',
                  style: TextStyle(
                    color: message.fromUser
                        ? Colors.white70
                        : const Color(0xFF6D7F62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _HandBotScrollBehavior extends MaterialScrollBehavior {
  const _HandBotScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
