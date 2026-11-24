import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/study_session_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/domain/entities/subject_entity.dart';
import 'package:noteflow_ai/domain/entities/weakness_analysis_result.dart';
import 'package:noteflow_ai/domain/services/weakness_detection_service.dart';

void main() {
  group('WeaknessDetectionService - Deterministic Mathematical Analysis Tests',
      () {
    const service = WeaknessDetectionService();
    final now = DateTime(2026, 11, 24, 10, 0);

    test('Returns empty result when no study sets exist', () {
      final result = service.analyze(
        studySets: [],
        subjects: [],
        recentSessions: [],
      );

      expect(result.totalTopicsAnalyzed, 0);
      expect(result.weakTopicsCount, 0);
      expect(result.overallMasteryScore, 100.0);
      expect(result.topics, isEmpty);
      expect(result.topWeakItems, isEmpty);
    });

    test(
        'Guard: Sets with < 3 interactions return MasteryLevel.insufficientData',
        () {
      final studySet = StudySetEntity(
        id: 'set_new',
        documentId: 'doc_1',
        title: 'Cấu trúc Dữ liệu & Giải thuật',
        summaryMarkdown: 'Tóm tắt danh sách liên kết và cây nhị phân',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_1',
            studySetId: 'set_new',
            frontText: 'Cây AVL là gì?',
            backText: 'Cây nhị phân tìm kiếm tự cân bằng',
            easeFactor: 2.5,
            intervalDays: 0,
            repetitionCount: 0, // Chưa học
            nextReviewAt: now,
            updatedAt: now,
          ),
        ],
        quizQuestions: [],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      expect(result.totalTopicsAnalyzed, 1);
      final topic = result.topics.first;
      expect(topic.masteryLevel, MasteryLevel.insufficientData);
      expect(topic.recommendations.first, contains('Chưa đủ dữ liệu ôn tập'));
    });

    test(
        'Correctly classifies study set with low Ease Factor (< 2.0) as MasteryLevel.weak',
        () {
      final studySet = StudySetEntity(
        id: 'set_weak',
        documentId: 'doc_2',
        title: 'Hệ điều hành & Đa luồng',
        summaryMarkdown: 'Deadlock, Semaphore, Mutex',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_low_ef_1',
            studySetId: 'set_weak',
            frontText: 'Hiện tượng Deadlock xảy ra khi nào?',
            backText: 'Khi có 4 điều kiện Coffman xảy ra đồng thời',
            easeFactor: 1.5, // Rất thấp (< 2.0)
            intervalDays: 1,
            repetitionCount: 4,
            nextReviewAt: now,
            updatedAt: now,
          ),
          FlashcardEntity(
            id: 'card_low_ef_2',
            studySetId: 'set_weak',
            frontText: 'Khác biệt giữa Mutex và Semaphore?',
            backText:
                'Mutex là binary lock có ownership, Semaphore là signaling',
            easeFactor: 1.7, // Thấp (< 2.0)
            intervalDays: 2,
            repetitionCount: 3,
            nextReviewAt: now,
            updatedAt: now,
          ),
          FlashcardEntity(
            id: 'card_normal',
            studySetId: 'set_weak',
            frontText: 'Thread pool là gì?',
            backText: 'Tập hợp các thread được tạo sẵn để tái sử dụng',
            easeFactor: 2.3,
            intervalDays: 6,
            repetitionCount: 2,
            nextReviewAt: now.add(const Duration(days: 4)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [
          QuizQuestionEntity(
            id: 'quiz_1',
            studySetId: 'set_weak',
            questionText: 'Điều kiện nào KHÔNG thuộc 4 điều kiện Coffman?',
            options: [
              'Mutual Exclusion',
              'Hold and Wait',
              'Preemption',
              'Circular Wait'
            ],
            correctIndex: 2,
            explanation: 'Điều kiện đúng là No Preemption',
            timesAnswered: 5,
            timesCorrect: 1, // 20% accuracy (< 60%)
            updatedAt: now,
          ),
        ],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [
          SubjectEntity(
            id: 'sub_1',
            title: 'Hệ Điều Hành',
            code: 'CS201',
            colorHex: '#0284C7',
            updatedAt: now,
          ),
        ],
        recentSessions: [
          StudySessionEntity(
            id: 'sess_1',
            studySetId: 'set_weak',
            sessionType: StudySessionType.quiz,
            score: 0.20,
            totalItems: 5,
            durationSeconds: 120,
            completedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      );

      expect(result.weakTopicsCount, 1);
      final topic = result.topics.first;
      expect(topic.masteryLevel, MasteryLevel.weak);
      expect(topic.weakCardsCount, 2);
      expect(topic.isWeak, isTrue);
      expect(topic.needsAttention, isTrue);

      // Kiểm tra danh sách top weak items
      expect(result.topWeakItems.isNotEmpty, isTrue);
      final hasWeakCard = result.topWeakItems.any(
        (item) => item.type == WeakItemType.flashcard && item.easeFactor == 1.5,
      );
      expect(hasWeakCard, isTrue);

      // Kiểm tra quiz question bị đánh dấu yếu
      final weakQuiz =
          topic.weakItems.firstWhere((w) => w.type == WeakItemType.quiz);
      expect(weakQuiz.accuracyRate, 0.20);
      expect(weakQuiz.reason, contains('20%'));
    });

    test('Correctly classifies high performing topic as MasteryLevel.strong',
        () {
      final studySet = StudySetEntity(
        id: 'set_strong',
        documentId: 'doc_3',
        title: 'Mạng Máy Tính & TCP/IP',
        summaryMarkdown: 'Mô hình OSI 7 tầng và TCP/IP',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_s1',
            studySetId: 'set_strong',
            frontText: 'TCP thuộc tầng nào trong OSI?',
            backText: 'Transport Layer (Tầng giao vận)',
            easeFactor: 2.6,
            intervalDays: 15,
            repetitionCount: 4,
            nextReviewAt: now.add(const Duration(days: 10)),
            updatedAt: now,
          ),
          FlashcardEntity(
            id: 'card_s2',
            studySetId: 'set_strong',
            frontText: 'Địa chỉ IPv4 có độ dài bao nhiêu bit?',
            backText: '32 bits (4 octets)',
            easeFactor: 2.5,
            intervalDays: 12,
            repetitionCount: 3,
            nextReviewAt: now.add(const Duration(days: 8)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [
          QuizQuestionEntity(
            id: 'quiz_s1',
            studySetId: 'set_strong',
            questionText: 'Giao thức nào cung cấp kết nối tin cậy?',
            options: ['UDP', 'TCP', 'IP', 'ICMP'],
            correctIndex: 1,
            explanation: 'TCP có cơ chế bắt tay 3 bước và truyền lại gói tin',
            timesAnswered: 6,
            timesCorrect: 6, // 100% accuracy
            updatedAt: now,
          ),
        ],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      expect(result.strongTopicsCount, 1);
      final topic = result.topics.first;
      expect(topic.masteryLevel, MasteryLevel.strong);
      expect(topic.weakCardsCount, 0);
      expect(topic.masteryScore, greaterThanOrEqualTo(80.0));
      expect(topic.recommendations.first, contains('rất vững chắc'));
    });

    test(
        'Case A & C - Flashcard-Only / No Quiz History: Score is not dragged to zero',
        () {
      final studySet = StudySetEntity(
        id: 'set_no_quiz',
        documentId: 'doc_nq',
        title: 'Lý thuyết Đồ thị',
        summaryMarkdown: 'Euler & Hamilton',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'c1',
            studySetId: 'set_no_quiz',
            frontText: 'Chu trình Euler',
            backText: 'Đi qua mỗi cạnh đúng 1 lần',
            easeFactor: 2.5,
            intervalDays: 6,
            repetitionCount: 2,
            nextReviewAt: now.add(const Duration(days: 4)),
            updatedAt: now,
          ),
          FlashcardEntity(
            id: 'c2',
            studySetId: 'set_no_quiz',
            frontText: 'Đường đi Hamilton',
            backText: 'Đi qua mỗi đỉnh đúng 1 lần',
            easeFactor: 2.4,
            intervalDays: 5,
            repetitionCount: 2,
            nextReviewAt: now.add(const Duration(days: 3)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [], // Không có câu hỏi quiz nào
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      final topic = result.topics.first;
      expect(topic.hasQuizData, isFalse);
      // Điểm số phải phản ánh đúng 100% năng lực Flashcard (~96%), không bị kéo về 0 do thiếu Quiz
      expect(topic.masteryScore, greaterThan(85.0));
      expect(topic.masteryLevel, MasteryLevel.strong);
    });

    test(
        'Case B - Very Small Sample Size: Single failed quiz gives cautious explanation',
        () {
      final studySet = StudySetEntity(
        id: 'set_single_quiz',
        documentId: 'doc_sq',
        title: 'Cơ sở Dữ liệu NoSQL',
        summaryMarkdown: 'MongoDB & Redis',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'c_nosql_1',
            studySetId: 'set_single_quiz',
            frontText: 'CAP theorem gồm 3 yếu tố nào?',
            backText: 'Consistency, Availability, Partition tolerance',
            easeFactor: 2.5,
            intervalDays: 6,
            repetitionCount: 2,
            nextReviewAt: now.add(const Duration(days: 4)),
            updatedAt: now,
          ),
          FlashcardEntity(
            id: 'c_nosql_2',
            studySetId: 'set_single_quiz',
            frontText: 'Redis là loại CSDL gì?',
            backText: 'In-memory Key-Value store',
            easeFactor: 2.5,
            intervalDays: 6,
            repetitionCount: 2,
            nextReviewAt: now.add(const Duration(days: 4)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [
          QuizQuestionEntity(
            id: 'q_single',
            studySetId: 'set_single_quiz',
            questionText: 'MongoDB lưu dữ liệu dưới định dạng nào?',
            options: ['XML', 'BSON', 'CSV', 'YAML'],
            correctIndex: 1,
            explanation: 'MongoDB sử dụng Binary JSON (BSON)',
            timesAnswered: 1, // Chỉ mới thử 1 lần
            timesCorrect: 0, // Sai 1 lần
            updatedAt: now,
          ),
        ],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      final topic = result.topics.first;
      // Do chỉ mới thử 1 lần, lý do cảnh báo phải thận trọng
      final weakQuiz =
          topic.weakItems.firstWhere((w) => w.type == WeakItemType.quiz);
      expect(
          weakQuiz.reason, contains('cần thêm lượt làm để đánh giá chính xác'));
      // Không để 1 câu sai duy nhất biến cả chủ đề 2 thẻ vững chắc thành MasteryLevel.weak
      expect(topic.masteryLevel, isNot(MasteryLevel.weak));
    });

    test(
        'Case D - Quiz-Only Learning: Score is driven purely by Quiz without unreviewed flashcard bias',
        () {
      final studySet = StudySetEntity(
        id: 'set_quiz_only',
        documentId: 'doc_qo',
        title: 'Kiểm thử Phần mềm',
        summaryMarkdown: 'Unit, Integration, E2E Test',
        updatedAt: now,
        flashcards: [
          // Thẻ chưa hề được ôn tập (reviewedCardsCount = 0)
          FlashcardEntity(
            id: 'c_unreviewed',
            studySetId: 'set_quiz_only',
            frontText: 'Mock là gì?',
            backText: 'Đối tượng giả lập hành vi',
            easeFactor: 2.5,
            intervalDays: 0,
            repetitionCount: 0,
            nextReviewAt: now,
            updatedAt: now,
          ),
        ],
        quizQuestions: [
          QuizQuestionEntity(
            id: 'q_test_1',
            studySetId: 'set_quiz_only',
            questionText: 'Test nào chạy nhanh nhất?',
            options: [
              'Unit Test',
              'Integration Test',
              'E2E Test',
              'Manual Test'
            ],
            correctIndex: 0,
            explanation: 'Unit test chạy cô lập trong bộ nhớ',
            timesAnswered: 5,
            timesCorrect: 2, // 40% accuracy
            updatedAt: now,
          ),
        ],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      final topic = result.topics.first;
      expect(topic.hasQuizData, isTrue);
      // Điểm số phải bám sát năng lực Quiz (40%), không bị thẻ chưa học kéo lên 100% giả tạo
      expect(topic.masteryScore, 40.0);
      expect(topic.masteryLevel, MasteryLevel.weak);
    });

    test(
        'Case E - Insufficient Data: Exactly 2 interactions triggers insufficientData',
        () {
      final studySet = StudySetEntity(
        id: 'set_two_interactions',
        documentId: 'doc_ti',
        title: 'An toàn Mạng',
        summaryMarkdown: 'Firewall & IDS',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'c_ti_1',
            studySetId: 'set_two_interactions',
            frontText: 'Firewall là gì?',
            backText: 'Hệ thống rào chắn kiểm soát lưu lượng',
            easeFactor: 2.5,
            intervalDays: 1,
            repetitionCount: 1, // 1 interaction
            nextReviewAt: now.add(const Duration(days: 1)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [
          QuizQuestionEntity(
            id: 'q_ti_1',
            studySetId: 'set_two_interactions',
            questionText: 'IDS viết tắt của từ gì?',
            options: [
              'Intrusion Detection System',
              'Internet Domain Server',
              'Internal Data Storage',
              'IP Domain System'
            ],
            correctIndex: 0,
            explanation: 'Intrusion Detection System',
            timesAnswered: 1, // 1 interaction -> Total = 2 < 3
            timesCorrect: 1,
            updatedAt: now,
          ),
        ],
      );

      final result = service.analyze(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
      );

      final topic = result.topics.first;
      expect(topic.masteryLevel, MasteryLevel.insufficientData);
      expect(topic.recommendations.first, contains('Chưa đủ dữ liệu ôn tập'));
    });
  });
}
