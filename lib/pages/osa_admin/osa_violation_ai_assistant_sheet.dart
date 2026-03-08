import 'package:apps/services/osa_violation_ai_service.dart';
import 'package:flutter/material.dart';

Future<void> showOsaViolationAiAssistantSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _OsaViolationAiAssistantSheet(),
  );
}

class _OsaViolationAiAssistantSheet extends StatefulWidget {
  const _OsaViolationAiAssistantSheet();

  @override
  State<_OsaViolationAiAssistantSheet> createState() =>
      _OsaViolationAiAssistantSheetState();
}

class _OsaViolationAiAssistantSheetState
    extends State<_OsaViolationAiAssistantSheet> {
  final _service = OsaViolationAiService();
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = <_Message>[
    const _Message(
      fromUser: false,
      text:
          'OSA AI is ready. Ask about violation trends, statuses, missed meetings, or recent case patterns.',
      sources: <String>[],
      includeInHistory: false,
    ),
  ];
  final List<String> _quickPrompts = const <String>[
    'What are the top 5 violations in the last 30 days?',
    'How many cases are unresolved and why?',
    'Show patterns for missed meetings this week.',
    'Give me operational priorities for today.',
  ];

  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _input.text.trim();
    if (question.isEmpty || _loading) return;
    final history = _buildHistoryTurns();

    setState(() {
      _messages.add(
        _Message(
          fromUser: true,
          text: question,
          sources: const [],
          includeInHistory: true,
        ),
      );
      _loading = true;
      _input.clear();
    });
    _scrollToBottom();

    try {
      final answer = await _service.ask(question, history: history);
      if (!mounted) return;
      final sources = <String>[
        ...answer.sources,
        if (answer.snapshotAt.isNotEmpty) 'snapshot ${answer.snapshotAt}',
      ];
      setState(() {
        _messages.add(
          _Message(
            fromUser: false,
            text: answer.text,
            sources: sources,
            includeInHistory: true,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            fromUser: false,
            text: 'Could not get an AI response right now.\n\nDetails: $error',
            sources: const <String>[],
            includeInHistory: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
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

  List<OsaAiChatTurn> _buildHistoryTurns() {
    final turns = _messages
        .where((message) => message.includeInHistory)
        .map(
          (message) => OsaAiChatTurn(
            role: message.fromUser ? 'user' : 'assistant',
            text: message.text,
          ),
        )
        .toList();
    if (turns.length <= 8) return turns;
    return turns.sublist(turns.length - 8);
  }

  void _askQuickPrompt(String prompt) {
    if (_loading) return;
    _input.text = prompt;
    _ask();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 900;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: isDesktop ? 24 : 0,
          right: isDesktop ? 24 : 0,
          top: isDesktop ? 24 : 0,
          bottom: media.viewInsets.bottom,
        ),
        child: Align(
          alignment: isDesktop ? Alignment.bottomRight : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 560 : double.infinity,
              maxHeight: media.size.height * (isDesktop ? 0.86 : 0.92),
            ),
            child: Material(
              color: const Color(0xFFF6FAF6),
              borderRadius: BorderRadius.circular(isDesktop ? 18 : 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFF1B5E20),
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.analytics_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'OSA Violation AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
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
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount:
                          _messages.length +
                          (_loading ? 1 : 0) +
                          (_messages.length == 1 ? 1 : 0),
                      itemBuilder: (context, index) {
                        final hasQuickPrompts = _messages.length == 1;
                        final promptOffset = hasQuickPrompts ? 1 : 0;
                        final typingIndex = promptOffset + _messages.length;
                        if (hasQuickPrompts && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _quickPrompts
                                  .map(
                                    (prompt) => ActionChip(
                                      onPressed: () => _askQuickPrompt(prompt),
                                      label: Text(
                                        prompt,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                        }
                        if (_loading && index == typingIndex) {
                          return const _TypingBubble();
                        }
                        final msg = _messages[index - promptOffset];
                        return _MessageBubble(message: msg);
                      },
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0x1F000000))),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
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
                                  'Ask about trends, unresolved cases, missed meetings...',
                              filled: true,
                              fillColor: const Color(0xFFF4F7F4),
                              contentPadding: const EdgeInsets.symmetric(
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
                          child: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message {
  final bool fromUser;
  final String text;
  final List<String> sources;
  final bool includeInHistory;

  const _Message({
    required this.fromUser,
    required this.text,
    required this.sources,
    required this.includeInHistory,
  });
}

class _MessageBubble extends StatelessWidget {
  final _Message message;
  const _MessageBubble({required this.message});

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
