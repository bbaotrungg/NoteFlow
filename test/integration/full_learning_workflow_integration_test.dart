import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/local/database/app_database.dart';
import 'package:noteflow_ai/data/repositories/study_repository_impl.dart';
import 'package:noteflow_ai/data/services/gemini_ai_service.dart';
import 'package:noteflow_ai/data/services/ocr_spatial_clustering_service.dart';
import 'package:noteflow_ai/data/sync/offline_sync_engine.dart';
import 'package:noteflow_ai/domain/entities/document_entity.dart';
import 'package:noteflow_ai/domain/entities/ocr_result_entity.dart';
import 'package:noteflow_ai/domain/entities/study_session_entity.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';
import 'package:noteflow_ai/domain/usecases/generate_study_set_usecase.dart';
import 'package:noteflow_ai/domain/usecases/review_flashcard_usecase.dart';

class _FakeOnlineConnectivity extends Fake implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

void main() {
  late AppDatabase db;
  late OfflineSyncEngine syncEngine;
  late StudyRepositoryImpl repository;
  late ReviewFlashcardUseCase reviewFlashcardUseCase;
  late SaveVerifiedStudySetUseCase saveVerifiedStudySetUseCase;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncEngine = OfflineSyncEngine(
      db: db,
      connectivity: _FakeOnlineConnectivity(),
    );
    repository = StudyRepositoryImpl(
      db: db,
      sm2Service: const Sm2SpacedRepetitionService(),
      syncEngine: syncEngine,
    );
    reviewFlashcardUseCase = ReviewFlashcardUseCase(repository);
    saveVerifiedStudySetUseCase = SaveVerifiedStudySetUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'Full Integrated Learning Workflow: OCR -> AI Generation -> Save -> Flashcard Review (SM-2) -> Quiz -> Dashboard Analytics -> Sync',
      () async {
    // ------------------------------------------------------------------------
    // Step 1: User creates a Subject
    // ------------------------------------------------------------------------
    final subject = await repository.createSubject(
      title: 'Công Nghệ Phần Mềm',
      code: 'SE202',
      colorHex: '#0284C7',
    );
    expect(subject.id, isNotEmpty);
    expect(subject.code, 'SE202');

    // ------------------------------------------------------------------------
    // Step 2: OCR extracts raw text with Spatial Row Clustering
    // ------------------------------------------------------------------------
    final ocrService = OcrSpatialClusteringService();
    final ocrElements = [
      const SpatialTextElement(
        text: 'Kiến Trúc Microservices trong Điện Toán Đám Mây',
        boundingBox: Rect.fromLTWH(20, 20, 460, 28),
      ),
      const SpatialTextElement(
        text: 'Dịch vụ: Độc lập và tự trị.',
        boundingBox: Rect.fromLTWH(20, 70, 180, 24),
      ),
      const SpatialTextElement(
        text: 'Giao tiếp: REST API hoặc gRPC.',
        boundingBox: Rect.fromLTWH(300, 70, 180, 24),
      ),
    ];

    final ocrResult = ocrService.clusterSpatialElements(elements: ocrElements);
    expect(ocrResult.structuredText, isNotEmpty);
    expect(
        ocrResult.structuredText.contains('Kiến Trúc Microservices'), isTrue);

    // ------------------------------------------------------------------------
    // Step 3: AI Service generates Study Set (Deterministic Academic Synthesis)
    // ------------------------------------------------------------------------
    final aiService =
        GeminiAiService(apiKey: ''); // Offline academic synthesis mode
    final aiContent = await aiService.generateStudyContentFromText(
      documentTitle: 'Bài giảng Microservices',
      extractedText: ocrResult.structuredText,
    );

    expect(aiContent.summaryMarkdown, isNotEmpty);
    expect(aiContent.flashcards, isNotEmpty);
    expect(aiContent.quiz, isNotEmpty);

    // ------------------------------------------------------------------------
    // Step 4: Save Verified Document & Study Set atomically into SQLite
    // ------------------------------------------------------------------------
    final savedStudySet = await saveVerifiedStudySetUseCase.execute(
      subjectId: subject.id,
      documentTitle: 'Tài liệu Microservices 101',
      fileType: DocumentFileType.text,
      localFilePath: '',
      rawExtractedText: ocrResult.structuredText,
      verifiedContent: aiContent,
    );

    expect(savedStudySet.id, isNotEmpty);
    expect(savedStudySet.flashcards.length, aiContent.flashcards.length);
    expect(savedStudySet.quizQuestions.length, aiContent.quiz.length);

    // ------------------------------------------------------------------------
    // Step 5: Student reviews a Flashcard with SM-2 Cognitive Engine
    // ------------------------------------------------------------------------
    final cardToReview = savedStudySet.flashcards.first;
    expect(cardToReview.intervalDays, 0);
    expect(cardToReview.repetitionCount, 0);

    final reviewedCard = await reviewFlashcardUseCase.execute(
      flashcard: cardToReview,
      rating: ReviewRating.good, // q = 4 -> next interval = 1 day, n = 1
    );

    expect(reviewedCard.intervalDays, 1);
    expect(reviewedCard.repetitionCount, 1);
    expect(reviewedCard.easeFactor, 2.5); // q=4 keeps EF at 2.5
    expect(reviewedCard.nextReviewAt.isAfter(DateTime.now()), isTrue);

    // ------------------------------------------------------------------------
    // Step 6: Student answers a Quiz Question
    // ------------------------------------------------------------------------
    final quizToAnswer = savedStudySet.quizQuestions.first;
    expect(quizToAnswer.timesAnswered, 0);

    await repository.recordQuizAnswer(
      questionId: quizToAnswer.id,
      isCorrect: true,
    );

    final updatedQuiz = await db.studyDao.getQuizQuestionById(quizToAnswer.id);
    expect(updatedQuiz, isNotNull);
    expect(updatedQuiz!.timesAnswered, 1);
    expect(updatedQuiz.timesCorrect, 1);

    // ------------------------------------------------------------------------
    // Step 7: Record Study Session
    // ------------------------------------------------------------------------
    final session = await repository.recordStudySession(
      studySetId: savedStudySet.id,
      sessionType: StudySessionType.flashcard,
      score: 100.0,
      totalItems: 1,
      durationSeconds: 150, // 2.5 minutes
    );

    expect(session.id, isNotEmpty);
    expect(session.durationSeconds, 150);

    // ------------------------------------------------------------------------
    // Step 8: Dashboard & Learning Analytics reflects real-time metrics
    // ------------------------------------------------------------------------
    final subjects = await repository.watchAllSubjects().first;
    final subjectMetrics = subjects.firstWhere((s) => s.id == subject.id);
    expect(subjectMetrics.documentCount, 1);
    expect(subjectMetrics.totalStudyMinutes, (150 / 60).ceil()); // 3 minutes

    final recentSessions = await repository.watchRecentSessions(days: 7).first;
    expect(recentSessions.any((s) => s.id == session.id), isTrue);

    final pendingSync = await repository.watchPendingSyncCount().first;
    expect(pendingSync > 0, isTrue);

    // ------------------------------------------------------------------------
    // Step 9: Offline Synchronization processes queue items
    // ------------------------------------------------------------------------
    final syncedRecords = await repository.synchronizeWithCloud();
    expect(syncedRecords > 0, isTrue);

    // All pending queue mutations should be processed
    final remainingSync = await repository.watchPendingSyncCount().first;
    expect(remainingSync, 0);
  });
}
