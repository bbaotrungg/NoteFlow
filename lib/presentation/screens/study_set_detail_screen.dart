import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../domain/entities/study_set_entity.dart';
import '../providers/app_providers.dart';
import 'flashcard_study_screen.dart';
import 'quiz_challenge_screen.dart';

/// Màn hình Chi tiết Bộ học liệu (Study Set Detail)
/// Cho phép xem bản tóm tắt Markdown, danh sách Flashcards kèm lịch ôn tập SM-2,
/// xóa bộ học liệu (Tombstone Soft-Delete), và khởi chạy phiên học Flashcard 3D hoặc Quiz bấm giờ.
class StudySetDetailScreen extends ConsumerWidget {
  final String studySetId;

  const StudySetDetailScreen({
    super.key,
    required this.studySetId,
  });

  Future<void> _confirmDeleteStudySet(BuildContext context, WidgetRef ref, StudySetEntity studySet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa bộ học liệu'),
        content: Text(
          'Bạn có chắc chắn muốn xóa bộ học liệu "${studySet.title}"?\n'
          'Bộ học liệu cùng các thẻ ghi nhớ và câu hỏi quiz sẽ được đánh dấu xóa (Tombstone) và đồng bộ Cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.roseDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa Bộ Học Liệu'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(studyRepositoryProvider).softDeleteStudySet(studySet.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa bộ học liệu "${studySet.title}"'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(studySetDetailStreamProvider(studySetId));

    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Chi tiết Bộ Học Liệu AI')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Chi tiết Bộ Học Liệu AI')),
        body: Center(child: Text('Lỗi tải bộ học liệu: $err')),
      ),
      data: (studySet) {
        if (studySet == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chi tiết Bộ Học Liệu AI')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Không tìm thấy bộ học liệu này',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Bộ học liệu có thể đã bị xóa hoặc chưa được đồng bộ.',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Quay lại Bảng điều khiển'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Chi tiết Bộ Học Liệu AI'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Tùy chọn',
                onSelected: (val) {
                  if (val == 'delete') {
                    _confirmDeleteStudySet(context, ref, studySet);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: AppTheme.roseDanger, size: 20),
                        SizedBox(width: 8),
                        Text('Xóa bộ học liệu', style: TextStyle(color: AppTheme.roseDanger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _buildContent(context, studySet),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, StudySetEntity studySet) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card với 2 nút hành động nhanh: Ôn Flashcards 3D & Thi Quiz bấm giờ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studySet.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cập nhật: ${DateTimeUtils.formatDateTimeShort(studySet.updatedAt)} • '
                    '${studySet.flashcards.length} Flashcards (${studySet.dueFlashcardsCount} cần ôn) • '
                    '${studySet.quizQuestions.length} câu Quiz',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: studySet.flashcards.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FlashcardStudyScreen(
                                      studySetId: studySet.id,
                                      title: studySet.title,
                                      initialCards: studySet.flashcards,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.style_rounded),
                        label: Text('Ôn tập 3D Flashcards (${studySet.flashcards.length})'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.emeraldAccent),
                        onPressed: studySet.quizQuestions.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => QuizChallengeScreen(
                                      studySetId: studySet.id,
                                      title: studySet.title,
                                      questions: studySet.quizQuestions,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.quiz_rounded),
                        label: Text('Thi Trắc nghiệm Bấm giờ (${studySet.quizQuestions.length})'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bản tóm tắt học thuật Markdown
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_stories_rounded, color: AppTheme.primarySkyBlue),
                      SizedBox(width: 8),
                      Text(
                        'Bản Tóm Tắt Học Thuật (Markdown)',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  MarkdownBody(
                    data: studySet.summaryMarkdown,
                    selectable: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Danh sách thẻ Flashcards kèm chỉ số SM-2
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Danh sách Thẻ nhớ & Lịch trình SuperMemo SM-2',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  ...studySet.flashcards.map((card) {
                    final isDue = card.isDue();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDue
                              ? AppTheme.amberWarning.withValues(alpha: 0.55)
                              : Colors.grey.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isDue
                                          ? AppTheme.amberWarning
                                          : AppTheme.emeraldAccent)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  DateTimeUtils.formatRelativeReview(card.nextReviewAt),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDue
                                        ? AppTheme.amberWarning
                                        : AppTheme.emeraldAccent,
                                  ),
                                ),
                              ),
                              Text(
                                'EF: ${card.easeFactor.toStringAsFixed(2)} • I: ${card.intervalDays}d • n=${card.repetitionCount}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            card.frontText,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            card.backText,
                            style: const TextStyle(fontSize: 13.5, height: 1.35),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
