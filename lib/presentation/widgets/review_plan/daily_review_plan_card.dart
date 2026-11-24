import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/review_plan_entity.dart';
import '../../providers/app_providers.dart';
import '../../screens/flashcard_study_screen.dart';
import '../../screens/quiz_challenge_screen.dart';

/// Thẻ Kế hoạch Ôn tập Cá nhân hóa Hàng ngày (Daily Personalized Review Plan Card)
/// - Hiển thị tiến độ hoàn thành các nhiệm vụ ôn tập trong ngày.
/// - Phân loại thứ tự ưu tiên: Khẩn cấp (Overdue cards) -> Quan trọng (Weakness drill) -> Tiêu chuẩn (Quiz).
/// - Tự động cập nhật tức thời khi sinh viên hoàn thành một phiên ôn tập.
class DailyReviewPlanCard extends ConsumerWidget {
  const DailyReviewPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewPlan = ref.watch(dailyReviewPlanProvider);
    final allStudySets = ref.watch(studySetsStreamProvider).valueOrNull ?? [];

    if (reviewPlan.tasks.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppTheme.emeraldAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hôm nay không có thẻ đến hạn!',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tất cả học liệu đã được ôn tập đúng chu kỳ SM-2. Hãy quét thêm bài giảng mới hoặc nghỉ ngơi nhé!',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalTasks = reviewPlan.totalTaskCount;
    final completedTasks = reviewPlan.completedTaskCount;
    final progress = reviewPlan.completionRate;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề & Tiến độ tổng thể
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySkyBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event_note_rounded,
                    color: AppTheme.primarySkyBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kế Hoạch Ôn Tập Hôm Nay',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '$totalTasks nhiệm vụ • Ước tính ${reviewPlan.totalEstimatedMinutes} phút',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: reviewPlan.isAllCompleted
                        ? AppTheme.emeraldAccent.withValues(alpha: 0.15)
                        : AppTheme.primarySkyBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$completedTasks / $totalTasks hoàn thành',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: reviewPlan.isAllCompleted
                          ? AppTheme.emeraldAccent
                          : AppTheme.primarySkyBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Thanh tiến trình
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  reviewPlan.isAllCompleted
                      ? AppTheme.emeraldAccent
                      : AppTheme.primarySkyBlue,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Danh sách các nhiệm vụ ưu tiên
            ...reviewPlan.tasks.take(4).map((task) {
              return _buildTaskItem(context, task, allStudySets);
            }),

            if (totalTasks > 4) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '+ Còn ${totalTasks - 4} nhiệm vụ ôn tập khác',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(
    BuildContext context,
    ReviewPlanTaskEntity task,
    List<dynamic> allStudySets,
  ) {
    final isDone = task.isCompleted;
    Color priorityColor;
    switch (task.priority) {
      case ReviewTaskPriority.urgent:
        priorityColor = AppTheme.roseDanger;
        break;
      case ReviewTaskPriority.high:
        priorityColor = AppTheme.amberWarning;
        break;
      case ReviewTaskPriority.normal:
        priorityColor = AppTheme.primarySkyBlue;
        break;
      case ReviewTaskPriority.maintenance:
        priorityColor = AppTheme.emeraldAccent;
        break;
    }

    IconData typeIcon;
    switch (task.taskType) {
      case ReviewTaskType.flashcardReview:
        typeIcon = Icons.flip_rounded;
        break;
      case ReviewTaskType.weaknessDrill:
        typeIcon = Icons.fitness_center_rounded;
        break;
      case ReviewTaskType.quizReinforcement:
        typeIcon = Icons.quiz_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDone
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? Colors.transparent
              : priorityColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : typeIcon,
            color: isDone ? AppTheme.emeraldAccent : priorityColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.studySetTitle,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                          color: isDone
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.priority.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: priorityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  task.reason,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Nút hành động trực tiếp (>= 48x48dp target)
          if (!isDone)
            Semantics(
              button: true,
              label: 'Bắt đầu ôn tập ${task.studySetTitle}',
              child: SizedBox(
                height: 38,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    _launchTaskScreen(context, task, allStudySets);
                  },
                  child: Text(
                    task.taskType == ReviewTaskType.quizReinforcement
                        ? 'Làm Quiz'
                        : 'Ôn Ngay',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            )
          else
            const Icon(Icons.done_all_rounded,
                size: 18, color: AppTheme.emeraldAccent),
        ],
      ),
    );
  }

  void _launchTaskScreen(
    BuildContext context,
    ReviewPlanTaskEntity task,
    List<dynamic> allStudySets,
  ) {
    final matchedSet = allStudySets.cast<dynamic>().firstWhere(
          (s) => s.id == task.studySetId,
          orElse: () => null,
        );

    if (matchedSet == null) return;

    if (task.taskType == ReviewTaskType.quizReinforcement) {
      if (matchedSet.quizQuestions.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizChallengeScreen(
            title: matchedSet.title,
            studySetId: matchedSet.id,
            questions: matchedSet.quizQuestions,
          ),
        ),
      );
    } else {
      if (matchedSet.flashcards.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FlashcardStudyScreen(
            title: matchedSet.title,
            studySetId: matchedSet.id,
            initialCards: matchedSet.flashcards,
          ),
        ),
      );
    }
  }
}
