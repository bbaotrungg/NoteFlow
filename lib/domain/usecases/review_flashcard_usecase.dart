import '../entities/flashcard_entity.dart';
import '../repositories/i_study_repository.dart';
import '../services/sm2_spaced_repetition_service.dart';

/// UseCase xử lý nghiệp vụ chấm điểm thẻ nhớ theo thuật toán SuperMemo SM-2
/// và đẩy thay đổi vào cơ sở dữ liệu + hàng đợi đồng bộ.
class ReviewFlashcardUseCase {
  final IStudyRepository _repository;

  const ReviewFlashcardUseCase(this._repository);

  Future<FlashcardEntity> execute({
    required FlashcardEntity flashcard,
    required ReviewRating rating,
  }) {
    return _repository.reviewFlashcard(
      flashcard: flashcard,
      rating: rating,
    );
  }
}
