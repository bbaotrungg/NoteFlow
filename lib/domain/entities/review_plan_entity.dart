/// Mức độ ưu tiên của nhiệm vụ ôn tập
enum ReviewTaskPriority {
  urgent('Khẩn cấp', 0xFFF43F5E),
  high('Quan trọng', 0xFFF59E0B),
  normal('Tiêu chuẩn', 0xFF0284C7),
  maintenance('Duy trì', 0xFF10B981);

  final String label;
  final int colorHex;
  const ReviewTaskPriority(this.label, this.colorHex);
}

/// Loại nhiệm vụ ôn tập trong kế hoạch học tập cá nhân hóa
enum ReviewTaskType {
  flashcardReview('Ôn tập Flashcard SM-2'),
  weaknessDrill('Luyện tập củng cố điểm yếu'),
  quizReinforcement('Trắc nghiệm đánh giá kiến thức');

  final String label;
  const ReviewTaskType(this.label);
}

/// Chi tiết một nhiệm vụ trong Kế hoạch Ôn tập Hàng ngày
class ReviewPlanTaskEntity {
  final String id;
  final String studySetId;
  final String studySetTitle;
  final String subjectTitle;
  final ReviewTaskType taskType;
  final ReviewTaskPriority priority;
  final int estimatedMinutes;
  final int itemCount;
  final String reason;
  final bool isCompleted;

  const ReviewPlanTaskEntity({
    required this.id,
    required this.studySetId,
    required this.studySetTitle,
    required this.subjectTitle,
    required this.taskType,
    required this.priority,
    required this.estimatedMinutes,
    required this.itemCount,
    required this.reason,
    this.isCompleted = false,
  });

  ReviewPlanTaskEntity copyWith({
    String? id,
    String? studySetId,
    String? studySetTitle,
    String? subjectTitle,
    ReviewTaskType? taskType,
    ReviewTaskPriority? priority,
    int? estimatedMinutes,
    int? itemCount,
    String? reason,
    bool? isCompleted,
  }) {
    return ReviewPlanTaskEntity(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      studySetTitle: studySetTitle ?? this.studySetTitle,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      taskType: taskType ?? this.taskType,
      priority: priority ?? this.priority,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      itemCount: itemCount ?? this.itemCount,
      reason: reason ?? this.reason,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

/// Kế hoạch Ôn tập Hàng ngày (Daily Personalized Review Plan)
class DailyReviewPlan {
  final DateTime date;
  final List<ReviewPlanTaskEntity> tasks;
  final int totalEstimatedMinutes;
  final int completedTaskCount;

  const DailyReviewPlan({
    required this.date,
    required this.tasks,
    required this.totalEstimatedMinutes,
    required this.completedTaskCount,
  });

  int get totalTaskCount => tasks.length;

  double get completionRate =>
      totalTaskCount == 0 ? 1.0 : completedTaskCount / totalTaskCount;

  bool get isAllCompleted =>
      totalTaskCount > 0 && completedTaskCount == totalTaskCount;

  factory DailyReviewPlan.empty() => DailyReviewPlan(
        date: DateTime.now(),
        tasks: const [],
        totalEstimatedMinutes: 0,
        completedTaskCount: 0,
      );
}
