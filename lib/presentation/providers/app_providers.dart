import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

import '../../data/local/database/app_database.dart';
import '../../data/repositories/study_repository_impl.dart';
import '../../data/services/ai_study_assistant_service.dart';
import '../../data/services/gemini_ai_service.dart';
import '../../data/services/ocr_spatial_clustering_service.dart';
import '../../data/sync/offline_sync_engine.dart';
import '../../domain/entities/ai_generated_study_content.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/ocr_result_entity.dart';
import '../../domain/entities/review_plan_entity.dart';
import '../../domain/entities/study_assistant_message.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/entities/study_set_entity.dart';
import '../../domain/entities/subject_entity.dart';
import '../../domain/entities/weakness_analysis_result.dart';
import '../../domain/repositories/i_study_repository.dart';
import '../../domain/services/review_planner_service.dart';
import '../../domain/services/sm2_spaced_repetition_service.dart';
import '../../domain/services/weakness_detection_service.dart';
import '../../domain/usecases/generate_study_set_usecase.dart';
import '../../domain/usecases/review_flashcard_usecase.dart';

// ============================================================================
// CORE DEPENDENCY INJECTION PROVIDERS (RIVERPOD 2)
// ============================================================================

final authStateStreamProvider = StreamProvider<AuthState?>((ref) {
  if (!AppConstants.isSupabaseInitialized) {
    return const Stream.empty();
  }
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  if (!AppConstants.isSupabaseInitialized) return null;
  final authState = ref.watch(authStateStreamProvider).valueOrNull;
  if (authState != null) {
    return authState.session?.user;
  }
  try {
    return Supabase.instance.client.auth.currentUser;
  } catch (_) {
    return null;
  }
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final user = ref.watch(currentUserProvider);
  final db = AppDatabase.forUser(user?.id);
  ref.onDispose(db.close);
  return db;
});

final sm2ServiceProvider = Provider<Sm2SpacedRepetitionService>((ref) {
  return const Sm2SpacedRepetitionService();
});

final ocrServiceProvider = Provider<OcrSpatialClusteringService>((ref) {
  return OcrSpatialClusteringService();
});

final geminiAiServiceProvider = Provider<GeminiAiService>((ref) {
  SupabaseClient? client;
  if (AppConstants.isSupabaseInitialized) {
    try {
      client = Supabase.instance.client;
    } catch (_) {}
  }
  return GeminiAiService(supabaseClient: client);
});

final offlineSyncEngineProvider = Provider<OfflineSyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  SupabaseClient? client;
  if (AppConstants.isSupabaseInitialized) {
    try {
      client = Supabase.instance.client;
    } catch (_) {}
  }
  return OfflineSyncEngine(db: db, supabaseClient: client);
});

final studyRepositoryProvider = Provider<IStudyRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final sm2 = ref.watch(sm2ServiceProvider);
  final syncEngine = ref.watch(offlineSyncEngineProvider);
  return StudyRepositoryImpl(
    db: db,
    sm2Service: sm2,
    syncEngine: syncEngine,
  );
});

final reviewFlashcardUseCaseProvider = Provider<ReviewFlashcardUseCase>((ref) {
  return ReviewFlashcardUseCase(ref.watch(studyRepositoryProvider));
});

final saveVerifiedStudySetUseCaseProvider =
    Provider<SaveVerifiedStudySetUseCase>((ref) {
  return SaveVerifiedStudySetUseCase(ref.watch(studyRepositoryProvider));
});

// ============================================================================
// REACTIVE STREAM PROVIDERS (TỰ ĐỘNG CẬP NHẬT UI TỪ DRIFT SQLITE)
// ============================================================================

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

final subjectsStreamProvider = StreamProvider<List<SubjectEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchAllSubjects();
});

final studySetsStreamProvider = StreamProvider<List<StudySetEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchAllStudySets();
});

final studySetDetailStreamProvider =
    StreamProvider.family<StudySetEntity?, String>((ref, studySetId) {
  return ref.watch(studyRepositoryProvider).watchStudySetDetail(studySetId);
});

final dueFlashcardsStreamProvider =
    StreamProvider<List<FlashcardEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchDueFlashcards();
});

final allActiveFlashcardsStreamProvider =
    StreamProvider<List<FlashcardEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchAllActiveFlashcards();
});

final recentSessionsStreamProvider =
    StreamProvider<List<StudySessionEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchRecentSessions(days: 7);
});

final pendingSyncCountStreamProvider = StreamProvider<int>((ref) {
  return ref.watch(studyRepositoryProvider).watchPendingSyncCount();
});

// ============================================================================
// ASYNC NOTIFIER CONTROLLERS (RIVERPOD 2 STATE MANAGEMENT)
// ============================================================================

/// Trạng thái của Pipeline Quét OCR + Sinh học liệu Gemini AI
class DocumentPipelineState {
  final File? selectedImageFile;
  final OcrExtractionResult? ocrResult;
  final AiGeneratedStudyContent? generatedContent;
  final bool isProcessingOcr;
  final bool isGeneratingAi;
  final bool isSaving;
  final String? errorMessage;

  const DocumentPipelineState({
    this.selectedImageFile,
    this.ocrResult,
    this.generatedContent,
    this.isProcessingOcr = false,
    this.isGeneratingAi = false,
    this.isSaving = false,
    this.errorMessage,
  });

  DocumentPipelineState copyWith({
    File? selectedImageFile,
    OcrExtractionResult? ocrResult,
    AiGeneratedStudyContent? generatedContent,
    bool? isProcessingOcr,
    bool? isGeneratingAi,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentPipelineState(
      selectedImageFile: selectedImageFile ?? this.selectedImageFile,
      ocrResult: ocrResult ?? this.ocrResult,
      generatedContent: generatedContent ?? this.generatedContent,
      isProcessingOcr: isProcessingOcr ?? this.isProcessingOcr,
      isGeneratingAi: isGeneratingAi ?? this.isGeneratingAi,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DocumentPipelineNotifier extends Notifier<DocumentPipelineState> {
  @override
  DocumentPipelineState build() => const DocumentPipelineState();

  /// Bước 1: Chụp/Chọn ảnh + Crop + Chạy On-Device ML Kit OCR kèm Spatial Row Clustering
  Future<void> scanAndExtractText(ImageSource source) async {
    state = state.copyWith(isProcessingOcr: true, clearError: true);
    try {
      final ocrService = ref.read(ocrServiceProvider);
      final file = await ocrService.pickAndCropDocumentImage(source: source);
      if (file == null) {
        state = state.copyWith(isProcessingOcr: false);
        return;
      }

      final ocrResult = await ocrService.extractTextFromFile(file);
      state = state.copyWith(
        selectedImageFile: file,
        ocrResult: ocrResult,
        isProcessingOcr: false,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessingOcr: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Mô phỏng nạp văn bản bài giảng đa cột chuẩn (dùng khi chạy trên máy ảo không có camera thật)
  void loadSampleMultiColumnLectureForOcrDemo() {
    final ocrService = ref.read(ocrServiceProvider);
    final simulatedElements = <SpatialTextElement>[
      // Cột trái
      const SpatialTextElement(
        text: '1. Kiến trúc Clean Architecture:',
        boundingBox: Rect.fromLTWH(20, 40, 210, 28),
      ),
      const SpatialTextElement(
        text: 'Tách biệt hoàn toàn Domain, Data và Presentation.',
        boundingBox: Rect.fromLTWH(20, 78, 215, 28),
      ),
      const SpatialTextElement(
        text: '2. Thuật toán SuperMemo SM-2:',
        boundingBox: Rect.fromLTWH(20, 125, 210, 28),
      ),
      const SpatialTextElement(
        text: 'Tối ưu khoảng cách ngày ôn tập dựa trên hệ số dễ EF.',
        boundingBox: Rect.fromLTWH(20, 162, 215, 28),
      ),
      // Cột phải
      const SpatialTextElement(
        text: '3. Đồng bộ Offline-First (LWW):',
        boundingBox: Rect.fromLTWH(310, 42, 220, 28),
      ),
      const SpatialTextElement(
        text: 'Sử dụng bảng sync_queue và cờ Tombstone is_deleted.',
        boundingBox: Rect.fromLTWH(310, 80, 220, 28),
      ),
      const SpatialTextElement(
        text: '4. Bảo mật Supabase RLS:',
        boundingBox: Rect.fromLTWH(310, 126, 210, 28),
      ),
      const SpatialTextElement(
        text: 'Kiểm soát quyền truy cập từng dòng với auth.uid().',
        boundingBox: Rect.fromLTWH(310, 164, 220, 28),
      ),
    ];

    final result = ocrService.clusterSpatialElements(
      elements: simulatedElements,
      processingTimeMs: 38,
    );

    state = state.copyWith(
      ocrResult: result,
      clearError: true,
    );
  }

  /// Bước 2: Gửi văn bản OCR đã kiểm duyệt lên Gemini 1.5 Flash để sinh Summary, Flashcards, Quiz
  Future<void> generateAiStudyMaterials({
    required String documentTitle,
    required String verifiedOcrText,
  }) async {
    state = state.copyWith(isGeneratingAi: true, clearError: true);
    try {
      final gemini = ref.read(geminiAiServiceProvider);
      final content = await gemini.generateStudyContentFromText(
        documentTitle: documentTitle,
        extractedText: verifiedOcrText,
      );
      state = state.copyWith(
        generatedContent: content,
        isGeneratingAi: false,
      );
    } catch (e) {
      state = state.copyWith(
        isGeneratingAi: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Bước 3: Lưu bộ học liệu đã chỉnh sửa/duyệt vào Drift SQLite + Hàng đợi đồng bộ
  Future<StudySetEntity?> commitVerifiedStudySet({
    required String subjectId,
    required String documentTitle,
    required String rawExtractedText,
    required AiGeneratedStudyContent verifiedContent,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final useCase = ref.read(saveVerifiedStudySetUseCaseProvider);
      final savedSet = await useCase.execute(
        subjectId: subjectId,
        documentTitle: documentTitle,
        fileType: state.selectedImageFile != null
            ? DocumentFileType.image
            : DocumentFileType.text,
        localFilePath: state.selectedImageFile?.path ?? '',
        rawExtractedText: rawExtractedText,
        verifiedContent: verifiedContent,
      );
      state = const DocumentPipelineState();
      return savedSet;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void resetPipeline() {
    state = const DocumentPipelineState();
  }
}

final documentPipelineProvider =
    NotifierProvider<DocumentPipelineNotifier, DocumentPipelineState>(
  DocumentPipelineNotifier.new,
);

/// Controller quản lý đồng bộ hai chiều Offline-First (Drift <-> Supabase)
class SyncControllerNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async => 0;

  Future<int> triggerManualSync() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref.read(studyRepositoryProvider).synchronizeWithCloud();
    });
    return state.valueOrNull ?? 0;
  }
}

final syncControllerProvider =
    AsyncNotifierProvider<SyncControllerNotifier, int>(
  SyncControllerNotifier.new,
);

// ============================================================================
// PHASE 4: INTELLIGENT AI FEATURES (RIVERPOD 2 DEPENDENCY INJECTION)
// ============================================================================

final aiStudyAssistantServiceProvider =
    Provider<AiStudyAssistantService>((ref) {
  SupabaseClient? client;
  if (AppConstants.isSupabaseInitialized) {
    try {
      client = Supabase.instance.client;
    } catch (_) {}
  }
  return AiStudyAssistantService(supabaseClient: client);
});

final weaknessDetectionServiceProvider =
    Provider<WeaknessDetectionService>((ref) {
  return const WeaknessDetectionService();
});

final reviewPlannerServiceProvider = Provider<ReviewPlannerService>((ref) {
  return const ReviewPlannerService();
});

/// Phân tích Điểm yếu Học tập (Smart Weakness Analysis) - Phản ứng thời gian thực
final weaknessAnalysisProvider = Provider<WeaknessAnalysisResult>((ref) {
  final studySets = ref.watch(studySetsStreamProvider).valueOrNull ?? [];
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? [];
  final sessions = ref.watch(recentSessionsStreamProvider).valueOrNull ?? [];
  final service = ref.watch(weaknessDetectionServiceProvider);

  return service.analyze(
    studySets: studySets,
    subjects: subjects,
    recentSessions: sessions,
  );
});

/// Kế hoạch Ôn tập Cá nhân hóa Hàng ngày (Personalized Daily Review Plan)
final dailyReviewPlanProvider = Provider<DailyReviewPlan>((ref) {
  final studySets = ref.watch(studySetsStreamProvider).valueOrNull ?? [];
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? [];
  final sessions = ref.watch(recentSessionsStreamProvider).valueOrNull ?? [];
  final weaknessAnalysis = ref.watch(weaknessAnalysisProvider);
  final service = ref.watch(reviewPlannerServiceProvider);

  return service.generateDailyPlan(
    studySets: studySets,
    subjects: subjects,
    recentSessions: sessions,
    weaknessAnalysis: weaknessAnalysis,
  );
});

// ============================================================================
// AI STUDY ASSISTANT CONTROLLER (RIVERPOD 2)
// ============================================================================

class StudyAssistantState {
  final List<StudyAssistantMessage> messages;
  final bool isGenerating;
  final String? activeStudySetId;
  final String? error;
  final String? lastUserPrompt;

  const StudyAssistantState({
    this.messages = const [],
    this.isGenerating = false,
    this.activeStudySetId,
    this.error,
    this.lastUserPrompt,
  });

  StudyAssistantState copyWith({
    List<StudyAssistantMessage>? messages,
    bool? isGenerating,
    String? activeStudySetId,
    String? error,
    bool clearError = false,
    String? lastUserPrompt,
  }) {
    return StudyAssistantState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      activeStudySetId: activeStudySetId ?? this.activeStudySetId,
      error: clearError ? null : (error ?? this.error),
      lastUserPrompt: lastUserPrompt ?? this.lastUserPrompt,
    );
  }
}

class StudyAssistantNotifier extends StateNotifier<StudyAssistantState> {
  final Ref _ref;
  final Uuid _uuid = const Uuid();

  StudyAssistantNotifier(this._ref) : super(const StudyAssistantState());

  void setStudySetContext(String? studySetId) {
    if (state.activeStudySetId == studySetId) return;
    state = state.copyWith(activeStudySetId: studySetId);
  }

  Future<void> sendMessage(String userPrompt,
      {StudySetEntity? explicitStudySet}) async {
    final cleanPrompt = userPrompt.trim();
    if (cleanPrompt.isEmpty) return;

    final targetStudySet = explicitStudySet ?? _findCurrentStudySet();

    final userMessage = StudyAssistantMessage(
      id: _uuid.v4(),
      studySetId: targetStudySet?.id ?? state.activeStudySetId,
      role: StudyAssistantRole.user,
      content: cleanPrompt,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isGenerating: true,
      clearError: true,
      lastUserPrompt: cleanPrompt,
    );

    try {
      final assistantService = _ref.read(aiStudyAssistantServiceProvider);
      final reply = await assistantService.askAssistant(
        userPrompt: cleanPrompt,
        studySet: targetStudySet,
        conversationHistory: state.messages,
      );

      state = state.copyWith(
        messages: [...state.messages, reply],
        isGenerating: false,
      );
    } catch (e) {
      final errorMessage = StudyAssistantMessage(
        id: _uuid.v4(),
        studySetId: targetStudySet?.id ?? state.activeStudySetId,
        role: StudyAssistantRole.assistant,
        content: 'Đã có lỗi xảy ra khi xử lý phản hồi từ AI: $e',
        timestamp: DateTime.now(),
        isError: true,
        errorMessage: e.toString(),
      );

      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isGenerating: false,
        error: e.toString(),
      );
    }
  }

  Future<void> retryLast({StudySetEntity? explicitStudySet}) async {
    final lastPrompt = state.lastUserPrompt;
    if (lastPrompt == null || lastPrompt.isEmpty) return;

    // Xóa tin nhắn lỗi cuối cùng nếu có
    final updatedMessages = List<StudyAssistantMessage>.from(state.messages);
    if (updatedMessages.isNotEmpty && updatedMessages.last.isError) {
      updatedMessages.removeLast();
    }
    // Nếu tin nhắn ngay trước là user prompt thì không cần gửi lại tin nhắn user
    if (updatedMessages.isNotEmpty && updatedMessages.last.isUser) {
      updatedMessages.removeLast();
    }
    state = state.copyWith(messages: updatedMessages);

    await sendMessage(lastPrompt, explicitStudySet: explicitStudySet);
  }

  /// Thêm thẻ flashcard nháp do AI sinh vào bộ học liệu người dùng (phải có xác nhận người dùng)
  Future<bool> appendDraftFlashcards({
    required StudySetEntity studySet,
    required List<AiGeneratedFlashcardDraft> drafts,
  }) async {
    if (drafts.isEmpty) return false;
    try {
      final repo = _ref.read(studyRepositoryProvider);
      final now = DateTime.now();

      final newCards = drafts.map((d) {
        return FlashcardEntity(
          id: _uuid.v4(),
          studySetId: studySet.id,
          frontText: d.front,
          backText: d.back,
          hint: d.hint,
          easeFactor: 2.5,
          intervalDays: 0,
          repetitionCount: 0,
          nextReviewAt: now,
          updatedAt: now,
        );
      }).toList();

      final combinedCards = [...studySet.flashcards, ...newCards];
      await repo.updateStudySetContent(
        studySet: studySet,
        flashcards: combinedCards,
        quizQuestions: studySet.quizQuestions,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearConversation() {
    state = state.copyWith(messages: [], clearError: true);
  }

  StudySetEntity? _findCurrentStudySet() {
    if (state.activeStudySetId == null) return null;
    final allSets = _ref.read(studySetsStreamProvider).valueOrNull ?? [];
    for (final s in allSets) {
      if (s.id == state.activeStudySetId) return s;
    }
    return null;
  }
}

final studyAssistantNotifierProvider =
    StateNotifierProvider<StudyAssistantNotifier, StudyAssistantState>((ref) {
  return StudyAssistantNotifier(ref);
});
