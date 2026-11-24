import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/study_assistant_message.dart';
import '../../domain/entities/study_set_entity.dart';
import '../providers/app_providers.dart';

/// Màn hình Trợ lý Học tập AI NoteFlow (AI Study Assistant Screen)
/// - Trả lời câu hỏi được neo chặt chẽ (Grounded) vào tài liệu học tập của sinh viên.
/// - Hiển thị bản tóm tắt, trích dẫn căn cứ, sinh câu hỏi tự luyện an toàn không ghi đè dữ liệu.
/// - Hỗ trợ thao tác chạm chuẩn trợ năng (>= 48x48dp), giao diện Markdown chuyên nghiệp.
class AiStudyAssistantScreen extends ConsumerStatefulWidget {
  final StudySetEntity? initialStudySet;

  const AiStudyAssistantScreen({
    super.key,
    this.initialStudySet,
  });

  @override
  ConsumerState<AiStudyAssistantScreen> createState() =>
      _AiStudyAssistantScreenState();
}

class _AiStudyAssistantScreenState
    extends ConsumerState<AiStudyAssistantScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StudySetEntity? _selectedStudySet;

  static const List<String> _quickPrompts = [
    'Tóm tắt 3 ý cốt lõi nhất',
    'Giải thích điểm khó hiểu nhất',
    'Tạo 2 câu hỏi trắc nghiệm tự luyện',
    'Kiểm tra kiến thức của tôi',
  ];

  @override
  void initState() {
    super.initState();
    _selectedStudySet = widget.initialStudySet;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedStudySet != null) {
        ref
            .read(studyAssistantNotifierProvider.notifier)
            .setStudySetContext(_selectedStudySet!.id);
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendPrompt([String? explicitText]) async {
    final text = explicitText ?? _promptController.text.trim();
    if (text.isEmpty) return;

    if (explicitText == null) {
      _promptController.clear();
    }

    await ref.read(studyAssistantNotifierProvider.notifier).sendMessage(
          text,
          explicitStudySet: _selectedStudySet,
        );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final assistantState = ref.watch(studyAssistantNotifierProvider);
    final allStudySets = ref.watch(studySetsStreamProvider).valueOrNull ?? [];

    // Lắng nghe cuộn khi có tin nhắn mới
    ref.listen<StudyAssistantState>(studyAssistantNotifierProvider,
        (prev, next) {
      if (prev?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primarySkyBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.primarySkyBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Trợ lý Học tập AI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _selectedStudySet != null
                        ? 'Neo trên: ${_selectedStudySet!.title}'
                        : 'Toàn bộ học liệu NoteFlow',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Nút chọn bộ học liệu để neo ngữ cảnh
          PopupMenuButton<String?>(
            tooltip: 'Chọn ngữ cảnh bộ học liệu',
            icon: const Icon(Icons.tune_rounded),
            onSelected: (setId) {
              setState(() {
                if (setId == null) {
                  _selectedStudySet = null;
                } else {
                  _selectedStudySet =
                      allStudySets.firstWhere((s) => s.id == setId);
                }
              });
              ref
                  .read(studyAssistantNotifierProvider.notifier)
                  .setStudySetContext(setId);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('🌐 Tổng quan (Tất cả môn)'),
              ),
              ...allStudySets.map(
                (s) => PopupMenuItem<String?>(
                  value: s.id,
                  child: Text('📚 ${s.title}', overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Xóa lịch sử hội thoại',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              ref
                  .read(studyAssistantNotifierProvider.notifier)
                  .clearConversation();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner thông tin Context Grounding
          _buildContextBanner(context),

          // Danh sách tin nhắn hội thoại
          Expanded(
            child: assistantState.messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: assistantState.messages.length +
                        (assistantState.isGenerating ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == assistantState.messages.length) {
                        return _buildGeneratingSkeleton(context);
                      }
                      final msg = assistantState.messages[index];
                      return _buildMessageItem(context, msg);
                    },
                  ),
          ),

          // Thanh gợi ý câu hỏi nhanh (Quick prompt chips)
          if (!assistantState.isGenerating) _buildQuickPromptsRow(context),

          // Ô nhập liệu và nút gửi
          _buildInputArea(context, assistantState.isGenerating),
        ],
      ),
    );
  }

  Widget _buildContextBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _selectedStudySet != null
                ? Icons.lock_outline_rounded
                : Icons.public_rounded,
            size: 15,
            color: AppTheme.primarySkyBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedStudySet != null
                  ? 'Trợ lý đang bám sát nội dung: "${_selectedStudySet!.title}" (${_selectedStudySet!.flashcards.length} thẻ, ${_selectedStudySet!.quizQuestions.length} câu quiz).'
                  : 'Chưa neo vào bộ học liệu cụ thể. Bấm nút Tùy chọn trên AppBar để chọn bài giảng.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.primarySkyBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: AppTheme.primarySkyBlue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hỏi đáp cùng Trợ lý Học tập AI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Trợ lý NoteFlow trả lời dựa trên bài giảng của bạn, trích dẫn căn cứ cụ thể và sinh câu hỏi tự luyện.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Text(
              'Bắt đầu nhanh với các gợi ý bên dưới:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickPrompts.map((p) {
                return ActionChip(
                  label: Text(p, style: const TextStyle(fontSize: 12.5)),
                  avatar: const Icon(Icons.flash_on_rounded,
                      size: 14, color: AppTheme.amberWarning),
                  onPressed: () => _handleSendPrompt(p),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primarySkyBlue.withValues(alpha: 0.2),
            child: const Icon(Icons.auto_awesome,
                size: 16, color: AppTheme.primarySkyBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Trợ lý đang phân tích học liệu...',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, StudyAssistantMessage msg) {
    final isUser = msg.isUser;
    final theme = Theme.of(context);

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppTheme.primarySkyBlue,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  msg.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant message bubble
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: msg.isError
                ? AppTheme.roseDanger.withValues(alpha: 0.2)
                : AppTheme.primarySkyBlue.withValues(alpha: 0.2),
            child: Icon(
              msg.isError
                  ? Icons.error_outline_rounded
                  : Icons.auto_awesome_rounded,
              size: 16,
              color:
                  msg.isError ? AppTheme.roseDanger : AppTheme.primarySkyBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: msg.isError
                        ? Border.all(
                            color: AppTheme.roseDanger.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(
                        data: msg.content,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ),

                      // Căn cứ trích dẫn học liệu (Grounding references)
                      if (msg.references.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: msg.references.map((r) {
                            return Chip(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: -2),
                              avatar: const Icon(Icons.bookmark_outline_rounded,
                                  size: 12, color: AppTheme.primarySkyBlue),
                              label: Text(
                                r,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primarySkyBlue),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // Danh sách câu hỏi tự luyện nháp (Practice generation)
                      if (msg.practiceQuizzes.isNotEmpty ||
                          msg.practiceFlashcards.isNotEmpty)
                        _buildDraftPracticeReview(context, msg),

                      // Hàng nút hành động: Sao chép & Thử lại khi lỗi
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Sao chép nội dung',
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: msg.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Đã sao chép phản hồi vào bộ nhớ tạm'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          if (msg.isError)
                            TextButton.icon(
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Thử lại',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                ref
                                    .read(
                                        studyAssistantNotifierProvider.notifier)
                                    .retryLast(
                                        explicitStudySet: _selectedStudySet);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Gợi ý hành động tiếp theo
                if (msg.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: msg.suggestedActions.map((act) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        label:
                            Text(act, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () => _handleSendPrompt(act),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftPracticeReview(
      BuildContext context, StudyAssistantMessage msg) {
    final hasCards = msg.practiceFlashcards.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.emeraldAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.emeraldAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_check_rounded,
                  color: AppTheme.emeraldAccent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Câu hỏi Tự luyện được sinh bởi AI',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.emeraldAccent,
                  ),
                ),
              ),
              if (_selectedStudySet != null && hasCards)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label:
                      const Text('Lưu vào Thẻ', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final success = await ref
                        .read(studyAssistantNotifierProvider.notifier)
                        .appendDraftFlashcards(
                          studySet: _selectedStudySet!,
                          drafts: msg.practiceFlashcards,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Đã thêm ${msg.practiceFlashcards.length} thẻ flashcard vào "${_selectedStudySet!.title}"!'
                                : 'Không thể lưu thẻ. Vui lòng thử lại.',
                          ),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bản nháp câu hỏi đã được tạo an toàn. Dữ liệu học tập gốc của bạn không bị ghi đè.',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPromptsRow(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _quickPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final p = _quickPrompts[i];
          return ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(p, style: const TextStyle(fontSize: 11.5)),
            onPressed: () => _handleSendPrompt(p),
          );
        },
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, bool isGenerating) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promptController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: isGenerating ? null : (_) => _handleSendPrompt(),
                decoration: InputDecoration(
                  hintText: _selectedStudySet != null
                      ? 'Hỏi về "${_selectedStudySet!.title}"...'
                      : 'Hỏi bất kỳ kiến thức nào...',
                  hintStyle: const TextStyle(fontSize: 13.5),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Nút gửi đáp ứng diện tích chạm >= 48x48dp
            Semantics(
              button: true,
              label: 'Gửi câu hỏi',
              child: SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filled(
                  tooltip: 'Gửi câu hỏi',
                  icon: isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  onPressed: isGenerating ? null : () => _handleSendPrompt(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
