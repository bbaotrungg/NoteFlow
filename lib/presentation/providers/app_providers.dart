import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local/database/app_database.dart';
import '../../data/repositories/study_repository_impl.dart';
import '../../data/services/gemini_ai_service.dart';
import '../../data/services/ocr_spatial_clustering_service.dart';
import '../../data/sync/offline_sync_engine.dart';
import '../../domain/entities/ai_generated_study_content.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/ocr_result_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/entities/study_set_entity.dart';
import '../../domain/entities/subject_entity.dart';
import '../../domain/repositories/i_study_repository.dart';
import '../../domain/services/sm2_spaced_repetition_service.dart';
import '../../domain/usecases/generate_study_set_usecase.dart';
import '../../domain/usecases/review_flashcard_usecase.dart';

// ============================================================================
// CORE DEPENDENCY INJECTION PROVIDERS (RIVERPOD 2)
// ============================================================================

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
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
  return GeminiAiService();
});

final offlineSyncEngineProvider = Provider<OfflineSyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return OfflineSyncEngine(db: db);
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

final saveVerifiedStudySetUseCaseProvider = Provider<SaveVerifiedStudySetUseCase>((ref) {
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

final dueFlashcardsStreamProvider = StreamProvider<List<FlashcardEntity>>((ref) {
  return ref.watch(studyRepositoryProvider).watchDueFlashcards();
});

final recentSessionsStreamProvider = StreamProvider<List<StudySessionEntity>>((ref) {
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
