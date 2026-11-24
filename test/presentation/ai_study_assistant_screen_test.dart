import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/presentation/providers/app_providers.dart';
import 'package:noteflow_ai/presentation/screens/ai_study_assistant_screen.dart';

void main() {
  final now = DateTime(2026, 11, 24, 10, 0);

  final mockStudySet = StudySetEntity(
    id: 'set_ai_test',
    documentId: 'doc_ai_test',
    title: 'Học Máy Cơ Bản',
    summaryMarkdown: 'Giới thiệu Linear Regression và Gradient Descent',
    updatedAt: now,
    flashcards: [
      FlashcardEntity(
        id: 'card_gd',
        studySetId: 'set_ai_test',
        frontText: 'Gradient Descent là gì?',
        backText: 'Thuật toán tối ưu hóa tìm cực tiểu của hàm mất mát',
        easeFactor: 2.5,
        intervalDays: 1,
        repetitionCount: 1,
        nextReviewAt: now,
        updatedAt: now,
      ),
    ],
    quizQuestions: [
      QuizQuestionEntity(
        id: 'quiz_gd',
        studySetId: 'set_ai_test',
        questionText: 'Learning rate quá lớn sẽ gây ra điều gì?',
        options: [
          'Hội tụ nhanh',
          'Không hội tụ / Phân kỳ',
          'Mô hình bị underfit',
          'Không ảnh hưởng'
        ],
        correctIndex: 1,
        explanation:
            'Learning rate quá lớn làm thuật toán nhảy qua điểm cực tiểu',
        timesAnswered: 2,
        timesCorrect: 2,
        updatedAt: now,
      ),
    ],
  );

  Widget createWidgetUnderTest({StudySetEntity? initialStudySet}) {
    return ProviderScope(
      overrides: [
        if (initialStudySet != null)
          studySetsStreamProvider
              .overrideWith((ref) => Stream.value([initialStudySet])),
      ],
      child: MaterialApp(
        home: AiStudyAssistantScreen(
          initialStudySet: initialStudySet,
        ),
      ),
    );
  }

  testWidgets(
      'AiStudyAssistantScreen renders initial empty state and quick chips',
      (tester) async {
    await tester
        .pumpWidget(createWidgetUnderTest(initialStudySet: mockStudySet));
    await tester.pumpAndSettle();

    expect(find.text('Trợ lý Học tập AI'), findsOneWidget);
    expect(find.textContaining('Học Máy Cơ Bản'), findsAtLeastNWidgets(1));
    expect(find.text('Hỏi đáp cùng Trợ lý Học tập AI'), findsOneWidget);
    expect(find.text('Tóm tắt 3 ý cốt lõi nhất'), findsWidgets);
    expect(find.text('Giải thích điểm khó hiểu nhất'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
      'Submitting prompt triggers response bubble and reference citations',
      (tester) async {
    await tester
        .pumpWidget(createWidgetUnderTest(initialStudySet: mockStudySet));
    await tester.pumpAndSettle();

    // Nhập câu hỏi vào TextField
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Tóm tắt 3 ý cốt lõi');
    await tester.pump();

    // Nhấn nút gửi
    final sendButton = find.byIcon(Icons.send_rounded);
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    // Kiểm tra câu trả lời của trợ lý xuất hiện
    expect(find.textContaining('Bản tóm tắt bài giảng'), findsOneWidget);

    // Cuộn lên để thấy tin nhắn của user (do auto-scroll xuống dưới cùng)
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();

    // Kiểm tra tin nhắn người dùng xuất hiện
    expect(find.text('Tóm tắt 3 ý cốt lõi'), findsOneWidget);
  });
}
