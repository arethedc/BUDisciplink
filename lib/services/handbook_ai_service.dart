import 'package:cloud_functions/cloud_functions.dart';

class HandbookAiAnswer {
  final String text;
  final List<String> sources;

  const HandbookAiAnswer({required this.text, required this.sources});
}

class HandbookAiService {
  HandbookAiService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-east1');

  final FirebaseFunctions _functions;

  Future<HandbookAiAnswer> ask(String question) async {
    final cleanQuestion = question.trim();
    if (cleanQuestion.isEmpty) {
      return const HandbookAiAnswer(
        text: 'Please enter a question.',
        sources: <String>[],
      );
    }

    final callable = _functions.httpsCallable('askHandbookAi');
    final response = await callable.call(<String, dynamic>{
      'question': cleanQuestion,
    });
    final data =
        (response.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final text = (data['answer'] ?? '').toString().trim();
    final sources = (data['sources'] as List<dynamic>? ?? const [])
        .map((source) => source.toString())
        .where((source) => source.trim().isNotEmpty)
        .toList();

    return HandbookAiAnswer(
      text: text.isEmpty ? 'I could not generate an answer right now.' : text,
      sources: sources,
    );
  }
}
