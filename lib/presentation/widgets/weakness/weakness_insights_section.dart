import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/weakness_analysis_result.dart';
import '../../providers/app_providers.dart';
import '../../screens/ai_study_assistant_screen.dart';
import '../../screens/flashcard_study_screen.dart';

/// Phần Phân tích Điểm yếu Học tập Thông minh (Smart Weakness Insights Section)
/// - Phản ánh trực quan mức độ thông thạo kiến thức (Mastery Levels) dựa trên SM-2 Ease Factor và Quiz Accuracy.
/// - Cung cấp danh sách các thẻ ghi nhớ và câu hỏi trắc nghiệm yếu nhất cùng lý do giải thích minh bạch.
/// - Hỗ trợ một chạm để chuyển thẳng tới Trợ lý AI hoặc khởi chạy ôn tập củng cố.
class WeaknessInsightsSection extends ConsumerWidget {
  final bool compactMode;

  const WeaknessInsightsSection({
    super.key,
    this.compactMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weakness = ref.watch(weaknessAnalysisProvider);
    final allStudySets = ref.watch(studySetsStreamProvider).valueOrNull ?? [];

    if (weakness.totalTopicsAnalyzed == 0) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  size: 28, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chưa có dữ liệu phân tích năng lực. Hãy hoàn thành các phiên ôn tập flashcard để kích hoạt đánh giá điểm yếu!',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Khối tổng quan chỉ số thông thạo
        Card(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.amberWarning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.psychology_rounded,
                            color: AppTheme.amberWarning,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Chẩn Đoán Năng Lực Học Tập',
                          style: TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getMasteryColor(weakness.overallMasteryScore)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${weakness.overallMasteryScore}% Thông thạo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _getMasteryColor(weakness.overallMasteryScore),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3 Thẻ thống kê nhanh
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        context,
                        title: 'Cần Củng Cố',
                        value: '${weakness.weakTopicsCount}',
                        color: AppTheme.roseDanger,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        context,
                        title: 'Trung Bình',
                        value: '${weakness.moderateTopicsCount}',
                        color: AppTheme.amberWarning,
                        icon: Icons.hourglass_top_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        context,
                        title: 'Vững Chắc',
                        value: '${weakness.strongTopicsCount}',
                        color: AppTheme.emeraldAccent,
                        icon: Icons.verified_rounded,
                      ),
                    ),
                  ],
                ),

                // Lời khuyên hệ thống
                if (weakness.generalAdvice.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tips_and_updates_rounded,
                            size: 16, color: AppTheme.primarySkyBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            weakness.generalAdvice.first,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Danh sách Top điểm yếu cụ thể (Top weak items)
        if (weakness.topWeakItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nội Dung Cần Củng Cố Nhất',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              Text(
                '${weakness.topWeakItems.length} mục cảnh báo',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...weakness.topWeakItems.take(compactMode ? 3 : 5).map((item) {
            return _buildWeakItemCard(context, item, allStudySets);
          }),
        ],

        // Danh sách chủ đề theo mức độ thông thạo (nếu không ở compactMode)
        if (!compactMode && weakness.topics.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Phân Tích Theo Bộ Học Liệu',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...weakness.topics.map((topic) {
            return _buildTopicRow(context, topic, allStudySets);
          }),
        ],
      ],
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWeakItemCard(
    BuildContext context,
    WeakItemEntity item,
    List<dynamic> allStudySets,
  ) {
    final isCard = item.type == WeakItemType.flashcard;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.roseDanger.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (isCard ? AppTheme.primarySkyBlue : AppTheme.amberWarning)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.type.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isCard
                        ? AppTheme.primarySkyBlue
                        : AppTheme.amberWarning,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bộ học liệu: ${item.studySetTitle}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            item.reason,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.roseDanger,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.psychology_outlined, size: 15),
                label: const Text('Hỏi AI giải thích',
                    style: TextStyle(fontSize: 11.5)),
                onPressed: () {
                  final targetSet = allStudySets.cast<dynamic>().firstWhere(
                        (s) => s.id == item.studySetId,
                        orElse: () => null,
                      );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AiStudyAssistantScreen(
                        initialStudySet: targetSet,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () {
                  final targetSet = allStudySets.cast<dynamic>().firstWhere(
                        (s) => s.id == item.studySetId,
                        orElse: () => null,
                      );
                  if (targetSet != null && targetSet.flashcards.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FlashcardStudyScreen(
                          title: targetSet.title,
                          studySetId: targetSet.id,
                          initialCards: targetSet.flashcards,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Luyện tập ngay',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopicRow(
    BuildContext context,
    TopicWeaknessEntity topic,
    List<dynamic> allStudySets,
  ) {
    Color badgeColor;
    switch (topic.masteryLevel) {
      case MasteryLevel.strong:
        badgeColor = AppTheme.emeraldAccent;
        break;
      case MasteryLevel.moderate:
        badgeColor = AppTheme.amberWarning;
        break;
      case MasteryLevel.weak:
        badgeColor = AppTheme.roseDanger;
        break;
      case MasteryLevel.insufficientData:
        badgeColor = Colors.grey;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  topic.studySetTitle,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  topic.masteryLevel.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Điểm: ${topic.masteryScore}% • EF TB: ${topic.averageEaseFactor} • ${topic.totalCards} thẻ (${topic.weakCardsCount} thẻ khó)',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (topic.recommendations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '💡 ${topic.recommendations.first}',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getMasteryColor(double score) {
    if (score >= 80.0) return AppTheme.emeraldAccent;
    if (score >= 60.0) return AppTheme.amberWarning;
    return AppTheme.roseDanger;
  }
}
