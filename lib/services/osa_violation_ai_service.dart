import 'package:cloud_functions/cloud_functions.dart';

class OsaViolationAiAnswer {
  final String text;
  final List<String> sources;
  final Map<String, dynamic> counts;
  final String snapshotAt;

  const OsaViolationAiAnswer({
    required this.text,
    required this.sources,
    required this.counts,
    required this.snapshotAt,
  });
}

class OsaAiChatTurn {
  final String role;
  final String text;

  const OsaAiChatTurn({required this.role, required this.text});
}

class OsaViolationAiService {
  OsaViolationAiService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-east1');

  final FirebaseFunctions _functions;

  Future<OsaViolationAiAnswer> ask(
    String question, {
    List<OsaAiChatTurn> history = const <OsaAiChatTurn>[],
  }) async {
    final cleanQuestion = question.trim();
    if (cleanQuestion.isEmpty) {
      return const OsaViolationAiAnswer(
        text: 'Please enter a question.',
        sources: <String>[],
        counts: <String, dynamic>{},
        snapshotAt: '',
      );
    }

    final callable = _functions.httpsCallable('askOsaViolationAi');
    final cleanedHistory = history
        .where((turn) => turn.text.trim().isNotEmpty)
        .map(
          (turn) => <String, String>{
            'role': turn.role == 'assistant' ? 'assistant' : 'user',
            'text': turn.text.trim(),
          },
        )
        .toList();
    final response = await callable.call(<String, dynamic>{
      'question': cleanQuestion,
      if (cleanedHistory.isNotEmpty) 'history': cleanedHistory,
    });
    final data =
        (response.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final text = (data['answer'] ?? '').toString().trim();
    final sources = (data['sources'] as List<dynamic>? ?? const [])
        .map((source) => source.toString())
        .where((source) => source.trim().isNotEmpty)
        .toList();
    final counts =
        (data['counts'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final snapshotAt = (data['snapshotAt'] ?? '').toString().trim();

    return OsaViolationAiAnswer(
      text: text.isEmpty ? 'I could not generate an answer right now.' : text,
      sources: sources,
      counts: counts,
      snapshotAt: snapshotAt,
    );
  }
}
