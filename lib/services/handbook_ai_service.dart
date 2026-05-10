import 'package:cloud_functions/cloud_functions.dart';

class HandbookAiSourceRef {
  final String label;
  final String sectionId;
  final String versionId;
  final String excerpt;

  const HandbookAiSourceRef({
    required this.label,
    required this.sectionId,
    required this.versionId,
    required this.excerpt,
  });
}

class HandbookAiAnswer {
  final String text;
  final List<String> sources;
  final List<HandbookAiSourceRef> sourceRefs;

  const HandbookAiAnswer({
    required this.text,
    required this.sources,
    required this.sourceRefs,
  });
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
        sourceRefs: <HandbookAiSourceRef>[],
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
    final sourceRefs = (data['sourceRefs'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final map = raw.cast<String, dynamic>();
          final label = (map['label'] ?? '').toString().trim();
          final sectionId = (map['sectionId'] ?? '').toString().trim();
          final versionId = (map['versionId'] ?? '').toString().trim();
          final excerpt = (map['excerpt'] ?? '').toString().trim();
          if (label.isEmpty) return null;
          return HandbookAiSourceRef(
            label: label,
            sectionId: sectionId,
            versionId: versionId,
            excerpt: excerpt,
          );
        })
        .whereType<HandbookAiSourceRef>()
        .toList();

    return HandbookAiAnswer(
      text: text.isEmpty ? 'I could not generate an answer right now.' : text,
      sources: sources,
      sourceRefs: sourceRefs,
    );
  }
}
