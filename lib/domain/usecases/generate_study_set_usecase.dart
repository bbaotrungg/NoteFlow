import '../entities/ai_generated_study_content.dart';
import '../entities/document_entity.dart';
import '../entities/study_set_entity.dart';
import '../repositories/i_study_repository.dart';

/// UseCase lưu trữ trọn vẹn Tài liệu OCR cùng Bộ học liệu (Tóm tắt, Flashcards, Quiz)
/// trong một giao dịch (Transaction) nguyên tử và ghi nhận vào Sync Queue.
class SaveVerifiedStudySetUseCase {
  final IStudyRepository _repository;

  const SaveVerifiedStudySetUseCase(this._repository);

  Future<StudySetEntity> execute({
    required String subjectId,
    required String documentTitle,
    required DocumentFileType fileType,
    required String localFilePath,
    required String rawExtractedText,
    required AiGeneratedStudyContent verifiedContent,
  }) {
    return _repository.saveDocumentAndStudySet(
      subjectId: subjectId,
      documentTitle: documentTitle,
      fileType: fileType,
      localFilePath: localFilePath,
      rawExtractedText: rawExtractedText,
      generatedContent: verifiedContent,
    );
  }
}
