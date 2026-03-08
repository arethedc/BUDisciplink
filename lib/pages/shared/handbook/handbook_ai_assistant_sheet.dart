import 'package:apps/services/handbook_ai_service.dart';
import 'package:flutter/material.dart';

Future<void> showHandbookAiAssistantSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _HandbookAiAssistantSheet(),
  );
}

class _HandbookAiAssistantSheet extends StatefulWidget {
  const _HandbookAiAssistantSheet();

  @override
  State<_HandbookAiAssistantSheet> createState() =>
      _HandbookAiAssistantSheetState();
}

class _HandbookAiAssistantSheetState extends State<_HandbookAiAssistantSheet> {
  final _service = HandbookAiService();
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = <_Message>[
    const _Message(
      fromUser: false,
      text:
          'Hi! Ask me anything about the Student Handbook. I will answer using handbook content only.',
      sources: <String>[],
    ),
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

    setState(() {
      _messages.add(_Message(fromUser: true, text: question, sources: const []));
      _loading = true;
      _input.clear();
    });
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
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            fromUser: false,
            text:
                'Could not get an AI response right now.\n\nDetails: $error\n\nCheck Firebase AI setup and try again.',
            sources: const <String>[],
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
              color: const Color(0xFFEFF2EA),
              borderRadius: BorderRadius.circular(isDesktop ? 18 : 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFF2F6C44),
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.smart_toy_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Handbook AI Assistant',
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
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_loading && index == _messages.length) {
                          return const _TypingBubble();
                        }
                        final msg = _messages[index];
                        return _MessageBubble(message: msg);
                      },
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
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _ask(),
                            decoration: InputDecoration(
                              hintText: 'Ask about rules, violations, or procedures',
                              filled: true,
                              fillColor: const Color(0xFFF5F7F2),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0x2F000000),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0x2F000000),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2F6C44),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: _loading ? null : _ask,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2F6C44),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
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
                                : const Icon(Icons.send_rounded, size: 18),
                          ),
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

  const _Message({
    required this.fromUser,
    required this.text,
    required this.sources,
  });
}

class _MessageBubble extends StatelessWidget {
  final _Message message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final align = message.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = message.fromUser ? const Color(0xFF2F6C44) : Colors.white;
    final fg = message.fromUser ? Colors.white : const Color(0xFF273127);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: message.fromUser
              ? null
              : Border.all(color: const Color(0x1A000000)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            if (!message.fromUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.sources
                    .take(4)
                    .map(
                      (source) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF5EC),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x2A2F6C44)),
                        ),
                        child: Text(
                          source,
                          style: const TextStyle(
                            color: Color(0xFF2F6C44),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                    .toList(),
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
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
