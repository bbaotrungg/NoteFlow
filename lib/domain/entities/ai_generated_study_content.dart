/// Cấu trúc đầu ra chuẩn JSON Schema từ Google Gemini 1.5 Flash
class AiGeneratedFlashcardDraft {
  final String front;
  final String back;
  final String? hint;

  const AiGeneratedFlashcardDraft({
    required this.front,
    required this.back,
    this.hint,
  });

  factory AiGeneratedFlashcardDraft.fromJson(Map<String, dynamic> json) {
    return AiGeneratedFlashcardDraft(
      front: (json['front'] as String? ?? '').trim(),
      back: (json['back'] as String? ?? '').trim(),
      hint: (json['hint'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'front': front,
        'back': back,
        if (hint != null && hint!.isNotEmpty) 'hint': hint,
      };
}

class AiGeneratedQuizDraft {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const AiGeneratedQuizDraft({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory AiGeneratedQuizDraft.fromJson(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as List<dynamic>? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Đảm bảo luôn có đủ 4 lựa chọn chuẩn
    while (rawOptions.length < 4) {
      rawOptions.add('Phương án bổ sung ${rawOptions.length + 1}');
    }
    final normalizedOptions = rawOptions.take(4).toList();
    final idx = (json['correct_index'] as num?)?.toInt() ?? 0;

    return AiGeneratedQuizDraft(
      question: (json['question'] as String? ?? '').trim(),
      options: normalizedOptions,
      correctIndex: idx.clamp(0, 3),
      explanation: (json['explanation'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'correct_index': correctIndex,
        'explanation': explanation,
      };
}

class AiGeneratedStudyContent {
  final String summaryMarkdown;
  final List<AiGeneratedFlashcardDraft> flashcards;
  final List<AiGeneratedQuizDraft> quiz;

  const AiGeneratedStudyContent({
    required this.summaryMarkdown,
    required this.flashcards,
    required this.quiz,
  });

  factory AiGeneratedStudyContent.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as String? ?? '').trim();
    final rawCards = (json['flashcards'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AiGeneratedFlashcardDraft.fromJson)
        .where((c) => c.front.isNotEmpty && c.back.isNotEmpty)
        .toList();

    final rawQuiz = (json['quiz'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AiGeneratedQuizDraft.fromJson)
        .where((q) => q.question.isNotEmpty)
        .toList();

    return AiGeneratedStudyContent(
      summaryMarkdown: summary,
      flashcards: rawCards,
      quiz: rawQuiz,
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summaryMarkdown,
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'quiz': quiz.map((e) => e.toJson()).toList(),
      };
}
