import 'dart:async';
import 'dart:math' as math;

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/ai_generated_study_content.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/study_assistant_message.dart';
import '../../domain/entities/study_set_entity.dart';

/// Dịch vụ Trợ lý Học tập AI (AI Study Assistant Service)
/// - Hoạt động theo nguyên tắc Context Grounding: Chỉ trả lời dựa trên học liệu thực tế của người dùng.
/// - Kiểm soát Token Bounding: Giới hạn ngữ cảnh học liệu tối đa 10.000 ký tự để tối ưu tốc độ và chi phí.
/// - Hỗ trợ giải thích khái niệm, hỏi đáp thấu đáo và sinh câu hỏi luyện tập có cấu trúc (Practice Generation).
/// - Không tự ý ghi đè dữ liệu người dùng: Các câu hỏi luyện tập được trả về dưới dạng bản nháp để người dùng phê duyệt.
/// - Cung cấp cơ chế Offline Synthesis thông minh khi không có kết nối mạng hoặc chưa cấu hình API key.
class AiStudyAssistantService {
  final String _apiKey;
  final SupabaseClient? _supabaseClient;
  final Uuid _uuid = const Uuid();

  AiStudyAssistantService({String? apiKey, SupabaseClient? supabaseClient})
      : _apiKey = apiKey ?? AppConstants.geminiApiKey,
        _supabaseClient = supabaseClient;

  /// Giới hạn ký tự ngữ cảnh học liệu để tránh tràn token và timeout
  static const int maxGroundedContextChars = 10000;

  /// Xây dựng chuỗi ngữ cảnh được neo (Grounded Context) từ StudySetEntity
  String buildGroundedContext({
    required StudySetEntity studySet,
    String? subjectName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('=== BỘ HỌC LIỆU: "${studySet.title}" ===');
    if (subjectName != null && subjectName.isNotEmpty) {
      buffer.writeln('Môn học: $subjectName');
    }

    if (studySet.summaryMarkdown.isNotEmpty) {
      buffer.writeln('\n[BẢN TÓM TẮT TRỌNG TÂM]');
      buffer.writeln(studySet.summaryMarkdown);
    }

    if (studySet.flashcards.isNotEmpty) {
      buffer.writeln('\n[DANH SÁCH THẺ GHI NHỚ FLASHCARD]');
      for (int i = 0; i < studySet.flashcards.length; i++) {
        final f = studySet.flashcards[i];
        if (f.isDeleted) continue;
        buffer.writeln('Thẻ ${i + 1}:');
        buffer.writeln('  - Câu hỏi/Thuật ngữ: ${f.frontText}');
        buffer.writeln('  - Định nghĩa/Đáp án: ${f.backText}');
        if (f.hint != null && f.hint!.isNotEmpty) {
          buffer.writeln('  - Gợi ý: ${f.hint}');
        }
      }
    }

    if (studySet.quizQuestions.isNotEmpty) {
      buffer.writeln('\n[DANH SÁCH CÂU HỎI TRẮC NGHIỆM]');
      for (int i = 0; i < studySet.quizQuestions.length; i++) {
        final q = studySet.quizQuestions[i];
        if (q.isDeleted) continue;
        buffer.writeln('Câu hỏi ${i + 1}: ${q.questionText}');
        for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
          final isCorrect = optIdx == q.correctIndex;
          buffer.writeln(
              '    $optIdx. ${q.options[optIdx]}${isCorrect ? ' (ĐÁP ÁN ĐÚNG)' : ''}');
        }
        if (q.explanation.isNotEmpty) {
          buffer.writeln('    Giải thích: ${q.explanation}');
        }
      }
    }

    var fullText = buffer.toString();
    if (fullText.length > maxGroundedContextChars) {
      fullText =
          '${fullText.substring(0, maxGroundedContextChars)}\n\n[...Ngữ cảnh đã được rút gọn để tối ưu giới hạn token...]';
    }
    return fullText;
  }

  /// Gửi câu hỏi tới Trợ lý AI và nhận câu trả lời được neo trên học liệu
  Future<StudyAssistantMessage> askAssistant({
    required String userPrompt,
    StudySetEntity? studySet,
    String? subjectName,
    List<StudyAssistantMessage> conversationHistory = const [],
  }) async {
    final cleanPrompt = userPrompt.trim();
    if (cleanPrompt.isEmpty) {
      throw const GeminiAiFailure('Nội dung câu hỏi không được để trống.');
    }

    final groundedContext = studySet != null
        ? buildGroundedContext(studySet: studySet, subjectName: subjectName)
        : 'Người dùng đang học tập chung các môn trong ứng dụng NoteFlow.';

    // 1. Thử gọi qua Supabase Edge Function Proxy bảo mật
    if (_supabaseClient != null && _supabaseClient.auth.currentUser != null) {
      try {
        final res = await _supabaseClient.functions.invoke(
          AppConstants.geminiEdgeFunctionName,
          body: {
            'action': 'ask_assistant',
            'userPrompt': cleanPrompt,
            'groundedContext': groundedContext,
            'history': conversationHistory
                .map((m) => {
                      'isUser': m.isUser,
                      'content': m.content,
                    })
                .toList(),
          },
        );
        if (res.status == 200 && res.data != null) {
          final data = res.data;
          final replyText = data is Map<String, dynamic>
              ? (data['reply'] as String?) ?? ''
              : '';
          if (replyText.isNotEmpty) {
            return _parseAssistantResponse(
              rawText: replyText,
              studySet: studySet,
            );
          }
        }
      } catch (_) {
        // Edge Function chưa được deploy -> tự động fallback sang direct SDK hoặc offline
      }
    }

    // 2. Nếu không có API Key, dùng bộ tổng hợp Offline Grounding thông minh
    if (_apiKey.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return _synthesizeOfflineAssistantResponse(
        prompt: cleanPrompt,
        studySet: studySet,
        subjectName: subjectName,
      );
    }

    const systemInstruction = '''
Bạn là "Trợ lý Học tập AI NoteFlow" (AI Study Assistant) chuyên sâu dành cho sinh viên Khoa Khoa học Máy tính - Đại học VKU.
NGUYÊN TẮC BẮT BUỘC (GROUNDING & SAFETY RULES):
1. Bạn PHẢI trả lời dựa trên học liệu được cung cấp bên dưới (Grounded Context).
2. Hãy trích dẫn cụ thể căn cứ trong câu trả lời (ví dụ: [Căn cứ: Thẻ ghi nhớ 2] hoặc [Căn cứ: Mục tóm tắt trọng tâm]).
3. Nếu câu hỏi nằm ngoài tài liệu được cung cấp, hãy lịch sự thông báo cho sinh viên biết nội dung này không có trong tài liệu và cung cấp hướng dẫn tham khảo bổ sung nếu phù hợp mà không bịa đặt kiến thức chuyên môn.
4. Trả lời bằng Markdown rõ ràng, thân thiện, súc tích.
5. Nếu người dùng yêu cầu "tạo thêm câu hỏi" hoặc "luyện tập", hãy đưa ra 1-3 câu hỏi trắc nghiệm hoặc flashcard nháp và định dạng rõ ràng để sinh viên tự kiểm tra.
6. Kết thúc câu trả lời, hãy gợi ý 2 câu hỏi tiếp nối ngắn gọn trong ngoặc nhọn dạng: {{Gợi ý: ...}}
''';

    final model = GenerativeModel(
      model: AppConstants.geminiModelName,
      apiKey: _apiKey,
      systemInstruction: Content.system(systemInstruction),
      generationConfig: GenerationConfig(
        temperature: 0.3,
        topP: 0.85,
        maxOutputTokens: 2048,
      ),
    );

    // Xây dựng chuỗi lịch sử hội thoại
    final historyContents = <Content>[];

    // Đưa ngữ cảnh học liệu vào đầu cuộc hội thoại
    historyContents.add(
        Content.text('NGỮ CẢNH HỌC LIỆU ĐƯỢC CUNG CẤP:\n$groundedContext'));

    // Giới hạn 6 tin nhắn gần nhất để không vượt token
    final recentHistory = conversationHistory.length > 6
        ? conversationHistory.sublist(conversationHistory.length - 6)
        : conversationHistory;

    for (final msg in recentHistory) {
      if (msg.isUser) {
        historyContents.add(Content.text('Sinh viên: ${msg.content}'));
      } else if (msg.isAssistant && !msg.isError) {
        historyContents.add(Content.model([TextPart(msg.content)]));
      }
    }

    historyContents.add(Content.text(cleanPrompt));

    int attempt = 0;
    while (attempt < AppConstants.maxApiRetries) {
      attempt++;
      try {
        final response = await model
            .generateContent(historyContents)
            .timeout(AppConstants.apiTimeout);

        final rawReply = response.text;
        if (rawReply == null || rawReply.trim().isEmpty) {
          throw const GeminiAiFailure('Gemini trả về câu trả lời rỗng.');
        }

        return _parseAssistantResponse(
          rawText: rawReply,
          studySet: studySet,
        );
      } on TimeoutException catch (e) {
        if (attempt >= AppConstants.maxApiRetries) {
          throw GeminiAiFailure(
            'Trợ lý AI phản hồi quá thời gian chờ sau $attempt lần thử: ${_sanitizeErrorMessage(e)}',
            originalError: e,
          );
        }
      } catch (e) {
        if (attempt >= AppConstants.maxApiRetries) {
          if (e is GeminiAiFailure) rethrow;
          throw GeminiAiFailure(
            'Lỗi kết nối Trợ lý AI: ${_sanitizeErrorMessage(e)}',
            originalError: e,
          );
        }
      }

      final backoffMs = (math.pow(2, attempt - 1) * 1000).toInt();
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
    }

    throw const GeminiAiFailure('Không thể nhận phản hồi từ Trợ lý AI.');
  }

  /// Khử thông tin nhạy cảm (API key) khỏi thông báo lỗi
  String _sanitizeErrorMessage(dynamic e) {
    var str = e.toString();
    str = str.replaceAll(RegExp(r'key=[A-Za-z0-9_-]+'), 'key=[REDACTED]');
    str =
        str.replaceAll(RegExp(r'AIza[0-9A-Za-z-_]{35}'), '[REDACTED_API_KEY]');
    return str;
  }

  /// Trích xuất các gợi ý hành động và tham chiếu từ câu trả lời AI
  StudyAssistantMessage _parseAssistantResponse({
    required String rawText,
    StudySetEntity? studySet,
  }) {
    final suggestedActions = <String>[];
    final rawReferences = <String>[];

    // Trích xuất {{Gợi ý: ...}}
    final suggestionRegex = RegExp(r'\{\{Gợi ý:\s*(.*?)\}\}');
    final matches = suggestionRegex.allMatches(rawText);
    for (final match in matches) {
      final s = match.group(1)?.trim();
      if (s != null && s.isNotEmpty) {
        suggestedActions.add(s);
      }
    }

    // Trích xuất [Căn cứ: ...]
    final refRegex = RegExp(r'\[Căn cứ:\s*(.*?)\]');
    final refMatches = refRegex.allMatches(rawText);
    for (final m in refMatches) {
      final r = m.group(1)?.trim();
      if (r != null && r.isNotEmpty && !rawReferences.contains(r)) {
        rawReferences.add(r);
      }
    }

    // Xác thực căn cứ học thuật (Loại bỏ các căn cứ bịa đặt không có trong bộ học liệu)
    final references = validateGroundedCitations(rawReferences, studySet);

    // Dọn dẹp văn bản hiển thị
    final cleanContent = rawText.replaceAll(suggestionRegex, '').trim();

    // Tự động phân tích các câu hỏi trắc nghiệm nháp nếu có
    final practiceQuizzes = _detectPracticeQuizzes(rawText);
    final practiceCards = _detectPracticeFlashcards(rawText);

    if (suggestedActions.isEmpty) {
      suggestedActions.addAll([
        'Giải thích chi tiết hơn',
        'Tạo câu hỏi trắc nghiệm tự luyện',
        'Lấy ví dụ thực tế',
      ]);
    }

    return StudyAssistantMessage(
      id: _uuid.v4(),
      studySetId: studySet?.id,
      role: StudyAssistantRole.assistant,
      content: cleanContent,
      timestamp: DateTime.now(),
      references: references,
      suggestedActions: suggestedActions.take(3).toList(),
      practiceQuizzes: practiceQuizzes,
      practiceFlashcards: practiceCards,
    );
  }

  /// Xác thực trích dẫn nguồn căn cứ học thuật so với ngữ cảnh thực tế
  List<String> validateGroundedCitations(
    List<String> rawCitations,
    StudySetEntity? studySet,
  ) {
    if (studySet == null || rawCitations.isEmpty) return rawCitations;
    final validated = <String>[];
    final cards = studySet.flashcards.where((f) => !f.isDeleted).toList();

    for (final ref in rawCitations) {
      final refLower = ref.toLowerCase();
      // 1. Căn cứ vào bản tóm tắt bài giảng
      if (refLower.contains('tóm tắt') || refLower.contains('summary')) {
        validated.add(ref);
        continue;
      }
      // 2. Căn cứ theo số thứ tự thẻ (ví dụ: "Thẻ 1", "Thẻ ghi nhớ 2")
      final cardNumMatch =
          RegExp(r'(?:thẻ(?:\s*ghi\s*nhớ)?)\s*(\d+)', caseSensitive: false)
              .firstMatch(ref);
      if (cardNumMatch != null) {
        final cardNum = int.tryParse(cardNumMatch.group(1) ?? '');
        if (cardNum != null && cardNum >= 1 && cardNum <= cards.length) {
          validated.add(ref);
          continue;
        } else {
          // Số thẻ vượt quá số thẻ thực tế -> Bịa đặt -> Loại bỏ
          continue;
        }
      }
      // 3. Căn cứ theo tên/thuật ngữ trong thẻ hoặc câu hỏi quiz
      final cardMatches = cards.any((c) {
        final f = c.frontText.toLowerCase();
        return refLower.contains(f) || (f.length > 5 && f.contains(refLower));
      });
      final quizMatches = studySet.quizQuestions.any((q) {
        final qt = q.questionText.toLowerCase();
        return refLower.contains(qt) ||
            (qt.length > 5 && qt.contains(refLower));
      });
      if (cardMatches || quizMatches) {
        validated.add(ref);
      }
    }
    return validated;
  }

  /// Phát hiện câu hỏi trắc nghiệm nháp mà AI sinh trong phản hồi
  List<AiGeneratedQuizDraft> _detectPracticeQuizzes(String text) {
    final quizzes = <AiGeneratedQuizDraft>[];
    // Tìm cấu trúc câu hỏi có các lựa chọn A, B, C, D
    final questionPattern = RegExp(
      r'(?:Câu hỏi|Câu|Q\d+)?\s*(.*?)\n+\s*[A-Da-d][\.\)]\s*(.*?)\n+\s*[A-Da-d][\.\)]\s*(.*?)\n+\s*[A-Da-d][\.\)]\s*(.*?)\n+\s*[A-Da-d][\.\)]\s*(.*?)(?:\n+.*?Đáp án(?:\s*đúng)?:\s*([A-Da-d]))?',
      dotAll: false,
    );

    for (final match in questionPattern.allMatches(text)) {
      final qText = match.group(1)?.trim() ?? '';
      final optA = match.group(2)?.trim() ?? '';
      final optB = match.group(3)?.trim() ?? '';
      final optC = match.group(4)?.trim() ?? '';
      final optD = match.group(5)?.trim() ?? '';
      final ansStr = match.group(6)?.toUpperCase() ?? 'A';

      if (qText.isNotEmpty && optA.isNotEmpty && optB.isNotEmpty) {
        int correctIdx = 0;
        if (ansStr.contains('B')) correctIdx = 1;
        if (ansStr.contains('C')) correctIdx = 2;
        if (ansStr.contains('D')) correctIdx = 3;

        quizzes.add(
          AiGeneratedQuizDraft(
            question: qText.replaceAll(RegExp(r'^\d+[\.\)]\s*'), ''),
            options: [optA, optB, optC, optD],
            correctIndex: correctIdx,
            explanation:
                'Câu hỏi tự luyện do Trợ lý AI NoteFlow tạo từ bài giảng.',
          ),
        );
      }
    }
    return quizzes;
  }

  /// Phát hiện flashcard nháp trong phản hồi
  List<AiGeneratedFlashcardDraft> _detectPracticeFlashcards(String text) {
    final cards = <AiGeneratedFlashcardDraft>[];
    final cardPattern = RegExp(
      r'(?:Mặt trước|Khái niệm|Thuật ngữ|Front):\s*(.*?)\n+(?:Mặt sau|Định nghĩa|Giải thích|Back):\s*(.*?)(?:\n+Gợi ý:\s*(.*?))?(?=\n\n|\Z)',
      caseSensitive: false,
    );

    for (final match in cardPattern.allMatches(text)) {
      final front = match.group(1)?.trim() ?? '';
      final back = match.group(2)?.trim() ?? '';
      final hint = match.group(3)?.trim();
      if (front.isNotEmpty && back.isNotEmpty) {
        cards.add(
          AiGeneratedFlashcardDraft(
            front: front,
            back: back,
            hint: hint,
          ),
        );
      }
    }
    return cards;
  }

  /// Phản hồi Offline Grounded thông minh dựa trên dữ liệu StudySetEntity có sẵn
  StudyAssistantMessage _synthesizeOfflineAssistantResponse({
    required String prompt,
    StudySetEntity? studySet,
    String? subjectName,
  }) {
    final lowerPrompt = prompt.toLowerCase();
    final buffer = StringBuffer();
    final references = <String>[];
    final suggestedActions = <String>[];
    final practiceCards = <AiGeneratedFlashcardDraft>[];
    final practiceQuizzes = <AiGeneratedQuizDraft>[];

    // Thông báo trung thực: Phản hồi được tổng hợp cục bộ từ ghi chú bài giảng (không phải suy luận từ Cloud AI)
    buffer.writeln(
      '> ⚡ **Chế độ Ngoại tuyến**: Phản hồi được tổng hợp cục bộ từ ghi chú bài giảng (không dùng API Key Cloud AI).\n',
    );

    if (studySet == null) {
      buffer.writeln('Chào bạn! Tôi là **Trợ lý Học tập AI NoteFlow**.');
      buffer.writeln(
        'Hiện tại bạn đang ở chế độ xem tổng quan. Để tôi có thể hỗ trợ giải thích chuyên sâu hoặc sinh câu hỏi trắc nghiệm sát với bài giảng, '
        'bạn hãy mở một **Bộ học liệu cụ thể** nhé!',
      );
      suggestedActions.addAll([
        'Cách học ngắt quãng SM-2 hiệu quả?',
        'Làm sao để cải thiện điểm yếu?',
        'Mẹo ghi nhớ flashcard',
      ]);
    } else {
      final title = studySet.title;
      final cards = studySet.flashcards.where((f) => !f.isDeleted).toList();
      final quizzes =
          studySet.quizQuestions.where((q) => !q.isDeleted).toList();

      if (lowerPrompt.contains('tóm tắt') || lowerPrompt.contains('cốt lõi')) {
        buffer.writeln('### 📌 Tóm tắt Trọng tâm: "$title"');
        if (studySet.summaryMarkdown.isNotEmpty) {
          buffer.writeln(studySet.summaryMarkdown);
          references.add('Bản tóm tắt bài giảng');
        } else if (cards.isNotEmpty) {
          for (int i = 0; i < math.min(4, cards.length); i++) {
            buffer.writeln('* **${cards[i].frontText}**: ${cards[i].backText}');
          }
          references.add('Thẻ ghi nhớ 1-${math.min(4, cards.length)}');
        }
        suggestedActions.addAll([
          'Giải thích khái niệm khó nhất',
          'Tạo 2 câu hỏi trắc nghiệm tự luyện',
          'Ôn tập các thẻ cần củng cố',
        ]);
      } else if (lowerPrompt.contains('câu hỏi') ||
          lowerPrompt.contains('trắc nghiệm') ||
          lowerPrompt.contains('luyện tập') ||
          lowerPrompt.contains('tạo')) {
        buffer.writeln('### 📝 Câu hỏi Tự Luyện cho Bộ Học Liệu: "$title"');
        buffer.writeln(
          'Dưới đây là câu hỏi trắc nghiệm được biên soạn từ các thẻ ghi nhớ của bạn để kiểm tra khả năng ghi nhớ:',
        );

        if (cards.length >= 2) {
          final targetCard = cards.first;
          final wrongCard = cards[1];
          final draftQuiz = AiGeneratedQuizDraft(
            question:
                'Theo nội dung học liệu "$title": "${targetCard.frontText}" có ý nghĩa là gì?',
            options: [
              targetCard.backText,
              wrongCard.backText,
              'Cả hai phương án trên đều không chính xác.',
              'Khái niệm không được đề cập trong bài giảng.',
            ],
            correctIndex: 0,
            explanation:
                'Căn cứ trên thẻ ghi nhớ: ${targetCard.frontText} -> ${targetCard.backText}',
          );
          practiceQuizzes.add(draftQuiz);

          buffer.writeln('\n**Câu hỏi**: ${draftQuiz.question}');
          for (int i = 0; i < draftQuiz.options.length; i++) {
            buffer.writeln(
                '${String.fromCharCode(65 + i)}. ${draftQuiz.options[i]}');
          }
          buffer.writeln('\n*Đáp án đúng*: A');
          buffer.writeln('*Giải thích*: ${draftQuiz.explanation}');
          references.add('Thẻ ghi nhớ: ${targetCard.frontText}');
        } else {
          buffer.writeln(
              'Bộ học liệu cần có ít nhất 2 thẻ ghi nhớ để tạo câu hỏi tự luyện phong phú.');
        }

        suggestedActions.addAll([
          'Giải thích đáp án',
          'Tạo thêm flashcard mới',
          'Tóm tắt lại nội dung',
        ]);
      } else {
        // Tìm kiếm từ khóa trong flashcard
        FlashcardEntity? matchedCard;
        for (final c in cards) {
          final fLower = c.frontText.toLowerCase();
          final bLower = c.backText.toLowerCase();
          final words = lowerPrompt.split(' ').where((w) => w.length > 3);
          for (final w in words) {
            if (fLower.contains(w) || bLower.contains(w)) {
              matchedCard = c;
              break;
            }
          }
          if (matchedCard != null) break;
        }

        if (matchedCard != null) {
          buffer.writeln(
              '### 💡 Giải thích Khái niệm: "${matchedCard.frontText}"');
          buffer.writeln('\n${matchedCard.backText}');
          if (matchedCard.hint != null && matchedCard.hint!.isNotEmpty) {
            buffer
                .writeln('\n*💡 Gợi ý kích hoạt trí nhớ*: ${matchedCard.hint}');
          }
          references.add('Thẻ ghi nhớ: ${matchedCard.frontText}');
        } else {
          buffer.writeln('### 📚 Phản hồi Dựa trên Bộ Học Liệu: "$title"');
          buffer.writeln(
            'Dựa trên tài liệu bạn đã quét, bộ học liệu này hiện có **${cards.length} thẻ ghi nhớ** '
            'và **${quizzes.length} câu hỏi trắc nghiệm**.',
          );
          if (studySet.summaryMarkdown.isNotEmpty) {
            final preview = studySet.summaryMarkdown.length > 250
                ? '${studySet.summaryMarkdown.substring(0, 250)}...'
                : studySet.summaryMarkdown;
            buffer.writeln('\n$preview');
            references.add('Bản tóm tắt bài giảng');
          }
        }

        suggestedActions.addAll([
          'Giải thích điểm khó nhất',
          'Tạo 2 câu hỏi trắc nghiệm tự luyện',
          'Tóm tắt 3 ý cốt lõi',
        ]);
      }
    }

    return StudyAssistantMessage(
      id: _uuid.v4(),
      studySetId: studySet?.id,
      role: StudyAssistantRole.assistant,
      content: buffer.toString(),
      timestamp: DateTime.now(),
      references: references,
      suggestedActions: suggestedActions.take(3).toList(),
      practiceQuizzes: practiceQuizzes,
      practiceFlashcards: practiceCards,
      isOfflineFallback: true,
    );
  }
}
