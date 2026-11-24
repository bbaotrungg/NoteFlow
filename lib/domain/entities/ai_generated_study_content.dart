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

    // Map defensively from dynamic maps and deduplicate flashcards by front text
    final rawCards = (json['flashcards'] as List<dynamic>? ?? [])
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .map(AiGeneratedFlashcardDraft.fromJson)
        .where((c) => c.front.isNotEmpty && c.back.isNotEmpty)
        .toList();

    final seenFronts = <String>{};
    final uniqueCards = <AiGeneratedFlashcardDraft>[];
    for (final card in rawCards) {
      final key = card.front.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seenFronts.add(key)) {
        uniqueCards.add(card);
      }
    }

    // Map defensively and deduplicate quizzes by question text
    final rawQuiz = (json['quiz'] as List<dynamic>? ?? [])
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .map(AiGeneratedQuizDraft.fromJson)
        .where((q) => q.question.isNotEmpty)
        .toList();

    final seenQuestions = <String>{};
    final uniqueQuiz = <AiGeneratedQuizDraft>[];
    for (final q in rawQuiz) {
      final key = q.question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seenQuestions.add(key)) {
        uniqueQuiz.add(q);
      }
    }

    return AiGeneratedStudyContent(
      summaryMarkdown: summary,
      flashcards: uniqueCards,
      quiz: uniqueQuiz,
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summaryMarkdown,
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'quiz': quiz.map((e) => e.toJson()).toList(),
      };
}
