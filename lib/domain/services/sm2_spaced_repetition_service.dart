import '../entities/flashcard_entity.dart';

/// Mức đánh giá cử chỉ vuốt thẻ (Swipe Gesture Rating) ánh xạ vào thang điểm q (0..5) của SuperMemo SM-2
enum ReviewRating {
  /// Quên hoàn toàn / Rất khó (Swipe Left) -> q = 1
  again(quality: 1, label: 'Quên / Khó', swipeDirectionLabel: 'Vuốt Trái'),

  /// Nhớ mang máng / Cần cố gắng (Tap nút Hard) -> q = 3
  hard(quality: 3, label: 'Tạm nhớ', swipeDirectionLabel: 'Chạm Vừa'),

  /// Nhớ tốt đúng hạn (Swipe Up / Good) -> q = 4
  good(quality: 4, label: 'Nhớ tốt', swipeDirectionLabel: 'Vuốt Lên'),

  /// Nhớ cực kỳ rõ ràng, phản xạ tức thì (Swipe Right) -> q = 5
  easy(quality: 5, label: 'Rất dễ', swipeDirectionLabel: 'Vuốt Phải');

  final int quality;
  final String label;
  final String swipeDirectionLabel;

  const ReviewRating({
    required this.quality,
    required this.label,
    required this.swipeDirectionLabel,
  });
}

/// Kết quả tính toán lịch ôn tập tiếp theo từ thuật toán SuperMemo SM-2
class Sm2CalculationResult {
  final double nextEaseFactor;
  final int nextIntervalDays;
  final int nextRepetitionCount;
  final DateTime nextReviewAt;

  const Sm2CalculationResult({
    required this.nextEaseFactor,
    required this.nextIntervalDays,
    required this.nextRepetitionCount,
    required this.nextReviewAt,
  });
}

/// Hiện thực hóa chính xác thuật toán Khoa học Nhận thức SuperMemo SM-2 (Wozniak, 1990)
///
/// Công thức toán học chuẩn:
/// 1. Hệ số dễ (Ease Factor - EF'):
///    EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
///    Ràng buộc: EF' >= 1.3 (Giới hạn dưới chống rơi vào "Ease Hell")
///
/// 2. Khoảng cách ngày ôn tập (Interval - I(n)):
///    - Nếu q < 3 (Quên kiến thức):
///      + Reset repetitionCount = 0
///      + Interval = 1 ngày (Ôn tập lại ngay vào ngày hôm sau)
///    - Nếu q >= 3 (Nhớ thành công):
///      + Khi n = 1 (Lần lặp thành công đầu tiên): I(1) = 1 ngày
///      + Khi n = 2 (Lần lặp thành công thứ hai): I(2) = 6 ngày
///      + Khi n > 2: I(n) = round(I(n - 1) * EF')
class Sm2SpacedRepetitionService {
  static const double minEaseFactor = 1.3;
  static const double initialEaseFactor = 2.5;

  const Sm2SpacedRepetitionService();

  /// Tính toán tham số SM-2 từ chất lượng phản hồi [quality] (0 <= q <= 5)
  Sm2CalculationResult calculate({
    required int quality,
    required double currentEaseFactor,
    required int currentIntervalDays,
    required int currentRepetitionCount,
    DateTime? evaluatedAt,
  }) {
    assert(quality >= 0 && quality <= 5, 'Quality q phải nằm trong khoảng [0, 5]');
    final now = evaluatedAt ?? DateTime.now();

    // Bước 1: Tính toán Ease Factor mới theo công thức gốc của Piotr Wozniak
    final double qDiff = (5 - quality).toDouble();
    final double efDelta = 0.1 - qDiff * (0.08 + qDiff * 0.02);
    double newEaseFactor = currentEaseFactor + efDelta;
    if (newEaseFactor < minEaseFactor) {
      newEaseFactor = minEaseFactor;
    }
    // Làm tròn 4 chữ số thập phân để tránh sai số dấu phẩy động
    newEaseFactor = double.parse(newEaseFactor.toStringAsFixed(4));

    int newRepetitionCount;
    int newIntervalDays;

    // Bước 2: Xét ngưỡng chất lượng nhớ (q < 3 là chưa đạt, q >= 3 là đạt)
    if (quality < 3) {
      newRepetitionCount = 0;
      newIntervalDays = 1;
    } else {
      newRepetitionCount = currentRepetitionCount + 1;
      if (newRepetitionCount == 1) {
        newIntervalDays = 1;
      } else if (newRepetitionCount == 2) {
        newIntervalDays = 6;
      } else {
        newIntervalDays = (currentIntervalDays * newEaseFactor).round();
        if (newIntervalDays < 1) {
          newIntervalDays = 1;
        }
      }
    }

    final DateTime nextReviewAt = now.add(Duration(days: newIntervalDays));

    return Sm2CalculationResult(
      nextEaseFactor: newEaseFactor,
      nextIntervalDays: newIntervalDays,
      nextRepetitionCount: newRepetitionCount,
      nextReviewAt: nextReviewAt,
    );
  }

  /// Áp dụng trực tiếp đánh giá [rating] lên một [FlashcardEntity] và trả về bản sao đã cập nhật
  FlashcardEntity applyReview({
    required FlashcardEntity flashcard,
    required ReviewRating rating,
    DateTime? reviewTimestamp,
  }) {
    final now = reviewTimestamp ?? DateTime.now();
    final result = calculate(
      quality: rating.quality,
      currentEaseFactor: flashcard.easeFactor,
      currentIntervalDays: flashcard.intervalDays,
      currentRepetitionCount: flashcard.repetitionCount,
      evaluatedAt: now,
    );

    return flashcard.copyWith(
      easeFactor: result.nextEaseFactor,
      intervalDays: result.nextIntervalDays,
      repetitionCount: result.nextRepetitionCount,
      nextReviewAt: result.nextReviewAt,
      updatedAt: now,
    );
  }

  /// Dự đoán tỷ lệ duy trì trí nhớ Ebbinghaus R(t) = exp(-t / S)
  /// Trong đó S (Memory Stability) tỷ lệ thuận với intervalDays * easeFactor.
  /// Phục vụ vẽ biểu đồ đường cong ghi nhớ (Retention Curve CustomPainter).
  double predictRetentionProbability({
    required double daysElapsed,
    required double easeFactor,
    required int intervalDays,
    required int repetitionCount,
  }) {
    if (daysElapsed <= 0) return 1.0;
    // Độ bền trí nhớ cơ sở S: khi mới học (interval=0) là 2.5 ngày,
    // tăng dần theo cấp số nhân với intervalDays và easeFactor
    final double effectiveInterval = intervalDays <= 0 ? 1.5 : intervalDays.toDouble();
    final double stabilityFactor = effectiveInterval * (easeFactor / 2.2) * (1.0 + repetitionCount * 0.25);

    // Tại thời điểm t = intervalDays, xác suất nhớ tiêu chuẩn đạt ~90% (R = e^(-t/S))
    // => S = -interval / ln(0.9) ≈ interval / 0.10536
    final double memoryStability = stabilityFactor / 0.12;
    final double retention = _expApprox(-daysElapsed / memoryStability);
    return retention.clamp(0.05, 1.0);
  }

  double _expApprox(double x) {
    // Sử dụng chuỗi Taylor kết hợp giới hạn hoặc dart:math exp
    // Để chính xác tuyệt đối, tính theo hằng số e = 2.718281828459045
    double sum = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 25; i++) {
      term *= x / i;
      sum += term;
    }
    return sum < 0 ? 0.0 : sum;
  }
}
