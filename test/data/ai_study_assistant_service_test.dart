import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/core/constants/app_constants.dart';
import 'package:noteflow_ai/data/services/ai_study_assistant_service.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';

void main() {
  group('AiStudyAssistantService - Grounding & Offline Synthesis Tests', () {
    // Không truyền API Key để kiểm thử chế độ Offline Grounding an toàn
    final assistant = AiStudyAssistantService(apiKey: '');
    final now = DateTime(2026, 11, 24, 10, 0);

    final mockStudySet = StudySetEntity(
      id: 'set_oop',
      documentId: 'doc_oop',
      title: 'Lập trình Hướng đối tượng Java',
      summaryMarkdown:
          '### 4 Trụ cột OOP:\n1. Đóng gói (Encapsulation)\n2. Kế thừa (Inheritance)\n3. Đa hình (Polymorphism)\n4. Trừu tượng (Abstraction)',
      updatedAt: now,
      flashcards: [
        FlashcardEntity(
          id: 'card_poly',
          studySetId: 'set_oop',
          frontText: 'Tính Đa hình (Polymorphism) là gì?',
          backText:
              'Khả năng cho phép các đối tượng khác nhau phản ứng với cùng một thông điệp theo các cách khác nhau.',
          hint: 'Gồm Overloading và Overriding',
          easeFactor: 2.5,
          intervalDays: 1,
          repetitionCount: 1,
          nextReviewAt: now,
          updatedAt: now,
        ),
        FlashcardEntity(
          id: 'card_encap',
          studySetId: 'set_oop',
          frontText: 'Tính Đóng gói (Encapsulation) là gì?',
          backText:
              'Che giấu trạng thái bên trong của đối tượng và chỉ cho phép tương tác qua getter/setter.',
          hint: 'Sử dụng private và public methods',
          easeFactor: 2.5,
          intervalDays: 2,
          repetitionCount: 1,
          nextReviewAt: now,
          updatedAt: now,
        ),
      ],
      quizQuestions: [
        QuizQuestionEntity(
          id: 'quiz_oop_1',
          studySetId: 'set_oop',
          questionText: 'Từ khóa nào dùng để kế thừa lớp trong Java?',
          options: ['implements', 'extends', 'inherits', 'super'],
          correctIndex: 1,
          explanation:
              'Java dùng "extends" để kế thừa class và "implements" cho interface.',
          timesAnswered: 3,
          timesCorrect: 3,
          updatedAt: now,
        ),
      ],
    );

    test('buildGroundedContext creates structured text bounded by max chars',
        () {
      final contextText = assistant.buildGroundedContext(
        studySet: mockStudySet,
        subjectName: 'Lập Trình Java Nâng Cao',
      );

      expect(contextText,
          contains('=== BỘ HỌC LIỆU: "Lập trình Hướng đối tượng Java" ==='));
      expect(contextText, contains('Môn học: Lập Trình Java Nâng Cao'));
      expect(contextText, contains('Tính Đa hình'));
      expect(contextText, contains('Tính Đóng gói'));
      expect(contextText, contains('implements'));
      expect(contextText.length,
          lessThanOrEqualTo(AiStudyAssistantService.maxGroundedContextChars));
    });

    test(
        'askAssistant without API Key responds with grounded concept explanation',
        () async {
      final reply = await assistant.askAssistant(
        userPrompt: 'Giải thích tính Đa hình',
        studySet: mockStudySet,
      );

      expect(reply.isAssistant, isTrue);
      expect(reply.isError, isFalse);
      expect(reply.content, contains('Đa hình'));
      expect(reply.references,
          contains('Thẻ ghi nhớ: Tính Đa hình (Polymorphism) là gì?'));
      expect(reply.suggestedActions.isNotEmpty, isTrue);
    });

    test(
        'askAssistant for practice generates quiz questions without overwriting database',
        () async {
      final reply = await assistant.askAssistant(
        userPrompt: 'Tạo 1 câu hỏi trắc nghiệm tự luyện về bài này',
        studySet: mockStudySet,
      );

      expect(reply.isAssistant, isTrue);
      expect(reply.practiceQuizzes.isNotEmpty, isTrue);
      final draftQuiz = reply.practiceQuizzes.first;
      expect(draftQuiz.options.length, 4);
      expect(draftQuiz.question, contains('Lập trình Hướng đối tượng Java'));
      // Dữ liệu học tập gốc vẫn nguyên vẹn
      expect(mockStudySet.quizQuestions.length, 1);
    });

    test(
        'askAssistant with summary request provides structured markdown preview',
        () async {
      final reply = await assistant.askAssistant(
        userPrompt: 'Tóm tắt 3 ý cốt lõi của tài liệu này',
        studySet: mockStudySet,
      );

      expect(reply.content, contains('Tóm tắt Trọng tâm'));
      expect(reply.references, contains('Bản tóm tắt bài giảng'));
    });

    test(
        'Offline synthesis honestly discloses local heuristic mode and sets isOfflineFallback',
        () async {
      final reply = await assistant.askAssistant(
        userPrompt: 'Giải thích tính Đóng gói',
        studySet: mockStudySet,
      );

      expect(reply.isOfflineFallback, isTrue);
      expect(reply.content, contains('Chế độ Ngoại tuyến'));
      expect(reply.content, contains('không dùng API Key Cloud AI'));
    });

    test(
        'Citation validation rejects fabricated references not present in the study set',
        () {
      final rawCitations = [
        'Bản tóm tắt bài giảng', // Hợp lệ
        'Thẻ ghi nhớ 1', // Hợp lệ (có 2 thẻ)
        'Thẻ ghi nhớ 99', // Bịa đặt! Không tồn tại
        'Sách Giáo trình Java trang 250', // Bịa đặt! Không tồn tại
        'Tính Đa hình', // Hợp lệ (nằm trong thẻ 1)
      ];

      final validated =
          assistant.validateGroundedCitations(rawCitations, mockStudySet);

      expect(validated, contains('Bản tóm tắt bài giảng'));
      expect(validated, contains('Thẻ ghi nhớ 1'));
      expect(validated, contains('Tính Đa hình'));
      expect(validated, isNot(contains('Thẻ ghi nhớ 99')));
      expect(validated, isNot(contains('Sách Giáo trình Java trang 250')));
    });

    test(
        'AppConstants release guard and edge function configuration are defined',
        () {
      expect(AppConstants.geminiEdgeFunctionName, 'gemini-study-assistant');
      // In test environment without key, it is safe for public distribution
      expect(AppConstants.isSafeForPublicDistribution, isTrue);
    });
  });
}
