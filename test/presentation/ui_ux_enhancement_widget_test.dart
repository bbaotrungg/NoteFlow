import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/core/theme/app_theme.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/presentation/screens/quiz_challenge_screen.dart';
import 'package:noteflow_ai/presentation/widgets/charts/subject_donut_painter.dart';
import 'package:noteflow_ai/presentation/widgets/charts/weekly_activity_bar_painter.dart';
import 'package:noteflow_ai/presentation/widgets/flashcard/interactive_3d_flashcard.dart';

void main() {
  group('UI/UX Enhancement: Design System & Tokens', () {
    test('AppTheme enforces minimum touch target size of 48x48dp (WCAG 2.5.5)',
        () {
      expect(AppTheme.minTouchTarget, 48.0);
      final lightBtn = AppTheme.lightTheme.filledButtonTheme.style;
      expect(lightBtn?.minimumSize?.resolve({}), const Size(48.0, 48.0));

      final darkBtn = AppTheme.darkTheme.filledButtonTheme.style;
      expect(darkBtn?.minimumSize?.resolve({}), const Size(48.0, 48.0));
    });

    test('AppTheme defines accessible muted text colors with WCAG AA contrast',
        () {
      expect(AppTheme.lightMutedText, const Color(0xFF64748B));
      expect(AppTheme.darkMutedText, const Color(0xFF94A3B8));
    });
  });

  group('UI/UX Enhancement: Interactive 3D Flashcard Face Distinction', () {
    final testCard = FlashcardEntity(
      id: 'fc-test-01',
      studySetId: 'set-test-01',
      frontText: 'Khái niệm Event Loop trong Dart là gì?',
      backText: 'Cơ chế xử lý bất đồng bộ tuần tự các sự kiện trong hàng đợi.',
      hint: 'Liên quan đến Microtask và Event Queue',
      easeFactor: 2.5,
      intervalDays: 1,
      repetitionCount: 0,
      nextReviewAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets(
        'Renders front face with question badge, hint button and accessibility semantics',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Interactive3DFlashcard(
              flashcard: testCard,
              onRated: (_) {},
            ),
          ),
        ),
      );

      // Verify question badge and text
      expect(find.text('MẶT TRƯỚC (CÂU HỎI)'), findsOneWidget);
      expect(find.text(testCard.frontText), findsOneWidget);
      expect(find.text('Xem gợi ý (Hint)'), findsOneWidget);

      // Verify accessibility semantics
      expect(
        find.bySemanticsLabel(
            RegExp(r'Mặt trước thẻ ghi nhớ: Khái niệm Event Loop')),
        findsOneWidget,
      );

      // Tap hint button to reveal hint
      await tester.tap(find.text('Xem gợi ý (Hint)'));
      await tester.pumpAndSettle();
      expect(find.text('Gợi ý: ${testCard.hint}'), findsOneWidget);
    });
  });

  group('UI/UX Enhancement: Quiz Sticky Action Bar & Option Semantics', () {
    final testQuestions = [
      QuizQuestionEntity(
        id: 'q-test-01',
        studySetId: 'set-test-01',
        questionText:
            'Trong Dart 3, từ khóa nào dùng để định nghĩa Sealed Class?',
        options: ['sealed', 'final', 'interface', 'abstract'],
        correctIndex: 0,
        explanation:
            'Từ khóa sealed giúp compiler kiểm tra exhaustive pattern matching.',
        updatedAt: DateTime.now(),
      ),
    ];

    testWidgets(
        'Selecting an option reveals explanation and displays sticky bottom next button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: QuizChallengeScreen(
              studySetId: 'set-test-01',
              title: 'Dart 3 Mastery',
              questions: testQuestions,
            ),
          ),
        ),
      );

      // Verify initial state
      expect(find.text('Câu hỏi 1 / 1'), findsOneWidget);
      expect(find.text('sealed'), findsOneWidget);

      // Bottom bar is not yet visible before answering
      expect(find.text('Hoàn thành & Xem điểm'), findsNothing);

      // Tap the correct option (index 0)
      await tester.tap(find.text('sealed'));
      await tester.pumpAndSettle();

      // Explanation is displayed
      expect(find.text('Giải thích chi tiết:'), findsOneWidget);
      expect(
          find.textContaining('exhaustive pattern matching'), findsOneWidget);

      // Sticky Bottom Navigation Bar appears with next/finish button
      expect(find.text('Hoàn thành & Xem điểm'), findsOneWidget);
    });
  });

  group('UI/UX Enhancement: Charts Empty State Gracefulness', () {
    testWidgets('SubjectStudyDonutChart renders friendly empty illustration',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SubjectStudyDonutChart(subjects: []),
          ),
        ),
      );

      expect(find.text('Chưa có dữ liệu học tập theo môn'), findsOneWidget);
      expect(find.byIcon(Icons.pie_chart_outline_rounded), findsOneWidget);
    });

    testWidgets(
        'WeeklyActivityBarChart renders without crashing on empty sessions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: WeeklyActivityBarChart(sessions: []),
          ),
        ),
      );

      expect(find.byType(WeeklyActivityBarChart), findsOneWidget);
    });
  });
}
