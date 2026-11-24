import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/domain/entities/subject_entity.dart';
import 'package:noteflow_ai/presentation/providers/app_providers.dart';
import 'package:noteflow_ai/presentation/widgets/review_plan/daily_review_plan_card.dart';
import 'package:noteflow_ai/presentation/widgets/weakness/weakness_insights_section.dart';

void main() {
  final now = DateTime(2026, 11, 24, 10, 0);

  final mockSubject = SubjectEntity(
    id: 'sub_test',
    title: 'An toàn Thông tin',
    code: 'SEC101',
    colorHex: '#0284C7',
    updatedAt: now,
  );

  final mockStudySet = StudySetEntity(
    id: 'set_sec_test',
    documentId: 'doc_sec_test',
    title: 'Mã Hóa Đối Xứng & Bất Đối Xứng',
    summaryMarkdown: 'AES, RSA, ECC, Diffie-Hellman',
    updatedAt: now,
    flashcards: [
      FlashcardEntity(
        id: 'card_aes',
        studySetId: 'set_sec_test',
        frontText: 'AES sử dụng kích thước khối bao nhiêu?',
        backText: '128 bits với độ dài khóa 128, 192 hoặc 256 bits',
        easeFactor: 1.6, // Thấp (< 2.0) để kích hoạt điểm yếu
        intervalDays: 1,
        repetitionCount: 3,
        nextReviewAt: now.subtract(const Duration(days: 1)), // Quá hạn
        updatedAt: now,
      ),
      FlashcardEntity(
        id: 'card_rsa',
        studySetId: 'set_sec_test',
        frontText: 'Hệ mật RSA dựa trên bài toán khó nào?',
        backText: 'Bài toán phân tích thừa số nguyên tố các số cực lớn',
        easeFactor: 2.5,
        intervalDays: 4,
        repetitionCount: 2,
        nextReviewAt: now.add(const Duration(days: 2)),
        updatedAt: now,
      ),
    ],
    quizQuestions: [
      QuizQuestionEntity(
        id: 'quiz_sec_1',
        studySetId: 'set_sec_test',
        questionText: 'Khóa công khai dùng để làm gì trong mã hóa RSA?',
        options: [
          'Giải mã dữ liệu',
          'Mã hóa dữ liệu',
          'Ký số',
          'Lưu trữ bí mật'
        ],
        correctIndex: 1,
        explanation:
            'Khóa công khai dùng để mã hóa, khóa bí mật dùng để giải mã',
        timesAnswered: 4,
        timesCorrect: 1, // 25% accuracy (< 60%)
        updatedAt: now,
      ),
    ],
  );

  testWidgets(
      'DailyReviewPlanCard displays urgent tasks and progress correctly',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studySetsStreamProvider
              .overrideWith((ref) => Stream.value([mockStudySet])),
          subjectsStreamProvider
              .overrideWith((ref) => Stream.value([mockSubject])),
          recentSessionsStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DailyReviewPlanCard(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kế Hoạch Ôn Tập Hôm Nay'), findsOneWidget);
    expect(
        find.text('Mã Hóa Đối Xứng & Bất Đối Xứng'), findsAtLeastNWidgets(1));
    expect(find.text('Khẩn cấp'), findsOneWidget);
    expect(find.text('Ôn Ngay'), findsAtLeastNWidgets(1));
  });

  testWidgets(
      'WeaknessInsightsSection in compact mode renders diagnosis and top weak items',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studySetsStreamProvider
              .overrideWith((ref) => Stream.value([mockStudySet])),
          subjectsStreamProvider
              .overrideWith((ref) => Stream.value([mockSubject])),
          recentSessionsStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeaknessInsightsSection(compactMode: true),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Chẩn Đoán Năng Lực Học Tập'), findsOneWidget);
    expect(find.text('Cần Củng Cố'), findsOneWidget);
    expect(find.text('Nội Dung Cần Củng Cố Nhất'), findsOneWidget);
    expect(find.textContaining('AES sử dụng kích thước khối bao nhiêu?'),
        findsOneWidget);
    expect(find.text('Hỏi AI giải thích'), findsAtLeastNWidgets(1));
    expect(find.text('Luyện tập ngay'), findsAtLeastNWidgets(1));
  });
}
