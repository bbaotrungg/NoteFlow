import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/entities/study_set_entity.dart';
import '../../domain/entities/subject_entity.dart';
import '../providers/app_providers.dart';
import '../widgets/charts/retention_curve_painter.dart';
import '../widgets/charts/subject_donut_painter.dart';
import '../widgets/charts/weekly_activity_bar_painter.dart';
import 'flashcard_study_screen.dart';
import 'ocr_ai_pipeline_screen.dart';
import 'study_set_detail_screen.dart';

/// Màn hình chính của NoteFlow AI (Responsive Adaptive Layout cho cả Điện thoại dọc & Tablet xoay ngang)
/// Tích hợp 4 phân khu:
/// 1. Tổng quan & Ôn tập nhanh SuperMemo SM-2
/// 2. Quản lý Môn học & Bộ học liệu (CRUD + Tombstone Soft-Delete)
/// 3. Phân tích Khoa học Nhận thức với 3 biểu đồ CustomPainter 60 FPS thuần Canvas
/// 4. Trạng thái Đồng bộ Offline-First (Sync Queue & Last-Write-Wins)
class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  int _selectedNavIndex = 0;

  Future<void> _showCreateSubjectDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String selectedColor = '#0284C7';
    const palette = ['#0284C7', '#7C3AED', '#059669', '#D97706', '#E11D48'];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Thêm Môn Học Mới (VKU)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã học phần (VD: IT4409)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên học phần',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: palette.map((hex) {
                      final color = AppTheme.parseHexColor(hex);
                      final isChosen = hex == selectedColor;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = hex),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: color,
                          child: isChosen
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
                    await ref.read(studyRepositoryProvider).createSubject(
                          title: titleCtrl.text.trim(),
                          code: codeCtrl.text.trim(),
                          colorHex: selectedColor,
                        );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Lưu Môn Học'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(subjectsStreamProvider);
    final studySetsAsync = ref.watch(studySetsStreamProvider);
    final dueCardsAsync = ref.watch(dueFlashcardsStreamProvider);
    final recentSessionsAsync = ref.watch(recentSessionsStreamProvider);
    final pendingSyncAsync = ref.watch(pendingSyncCountStreamProvider);
    final syncState = ref.watch(syncControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    final subjects = subjectsAsync.valueOrNull ?? const <SubjectEntity>[];
    final studySets = studySetsAsync.valueOrNull ?? const <StudySetEntity>[];
    final dueCards = dueCardsAsync.valueOrNull ?? const <FlashcardEntity>[];
    final sessions = recentSessionsAsync.valueOrNull ?? const <StudySessionEntity>[];
    final pendingSyncCount = pendingSyncAsync.valueOrNull ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTabletOrLandscape = constraints.maxWidth >= 820;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySkyBlue.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppTheme.primarySkyBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConstants.appName),
                      Text(
                        AppConstants.universityDepartment,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Nút Đồng bộ Offline-First 2 chiều kèm số lượng hàng đợi Sync Queue
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: syncState.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          pendingSyncCount > 0
                              ? Icons.cloud_upload_rounded
                              : Icons.cloud_done_rounded,
                          size: 18,
                          color: pendingSyncCount > 0
                              ? AppTheme.amberWarning
                              : AppTheme.emeraldAccent,
                        ),
                  label: Text(
                    pendingSyncCount > 0 ? 'Sync Queue ($pendingSyncCount)' : 'Đã đồng bộ',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    final synced =
                        await ref.read(syncControllerProvider.notifier).triggerManualSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đồng bộ Offline-First (LWW) hoàn tất: Đã đẩy $synced bản ghi lên Cloud!',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              IconButton(
                tooltip: 'Chuyển đổi Dark / Light Mode',
                onPressed: () {
                  ref.read(themeModeProvider.notifier).state =
                      themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OcrAiPipelineScreen(subjects: subjects),
                ),
              );
            },
            backgroundColor: AppTheme.primarySkyBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.document_scanner_rounded),
            label: const Text('Quét OCR & Sinh AI'),
          ),
          bottomNavigationBar: isTabletOrLandscape
              ? null
              : NavigationBar(
                  selectedIndex: _selectedNavIndex,
                  onDestinationSelected: (idx) => setState(() => _selectedNavIndex = idx),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard_rounded),
                      label: 'Tổng quan',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books_rounded),
                      label: 'Học liệu AI',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: 'Thống kê 60FPS',
                    ),
                  ],
                ),
          body: Row(
            children: [
              if (isTabletOrLandscape)
                NavigationRail(
                  selectedIndex: _selectedNavIndex,
                  onDestinationSelected: (idx) => setState(() => _selectedNavIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard_rounded),
                      label: Text('Tổng quan'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books_rounded),
                      label: Text('Học liệu AI'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: Text('Thống kê 60FPS'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedNavIndex,
                  children: [
                    _buildOverviewTab(
                      context,
                      subjects: subjects,
                      studySets: studySets,
                      dueCards: dueCards,
                      pendingSyncCount: pendingSyncCount,
                    ),
                    _buildStudySetsTab(context, subjects: subjects, studySets: studySets),
                    _buildAnalyticsTab(
                      context,
                      subjects: subjects,
                      dueCards: dueCards,
                      sessions: sessions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewTab(
    BuildContext context, {
    required List<SubjectEntity> subjects,
    required List<StudySetEntity> studySets,
    required List<FlashcardEntity> dueCards,
    required int pendingSyncCount,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Ôn tập thông minh theo thuật toán SuperMemo SM-2
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'SUPERMEMO SM-2 ENGINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Sync Queue: $pendingSyncCount mục',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Bạn có ${dueCards.length} thẻ Flashcard đến hạn ôn tập hôm nay',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Thuật toán lặp lại ngắt quãng SM-2 tự động ưu tiên các thẻ có hệ số dễ (Ease Factor) thấp để tối ưu hóa độ bền trí nhớ dài hạn.',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  onPressed: dueCards.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FlashcardStudyScreen(
                                title: 'Ôn tập Hàng ngày (SM-2 Queue)',
                                initialCards: dueCards,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Bắt đầu Lật thẻ 3D ngay'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Danh sách Môn học (CRUD + Tombstone Soft-Delete)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Học phần đang theo học',
                style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800),
              ),
              TextButton.icon(
                onPressed: () => _showCreateSubjectDialog(context),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Thêm môn học'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...subjects.map((sub) {
            final color = AppTheme.parseHexColor(sub.colorHex);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.18),
                  child: Text(
                    sub.code.substring(0, sub.code.length.clamp(0, 2)),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(
                  '${sub.code} • ${sub.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${sub.documentCount} tài liệu • ${sub.dueFlashcardCount} thẻ cần ôn • ${sub.totalStudyMinutes} phút học',
                  style: const TextStyle(fontSize: 12.5),
                ),
                trailing: IconButton(
                  tooltip: 'Xóa mềm (Tombstone Soft-Delete)',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () async {
                    await ref.read(studyRepositoryProvider).softDeleteSubject(sub.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã đánh dấu Tombstone (is_deleted=true) cho môn ${sub.code} và đẩy vào Sync Queue.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStudySetsTab(
    BuildContext context, {
    required List<SubjectEntity> subjects,
    required List<StudySetEntity> studySets,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: studySets.length,
      itemBuilder: (context, index) {
        final set = studySets[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudySetDetailScreen(studySetId: set.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppTheme.primarySkyBlue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          set.title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _buildTag('${set.flashcards.length} Flashcards', AppTheme.primarySkyBlue),
                      _buildTag('${set.quizQuestions.length} Quiz', AppTheme.emeraldAccent),
                      _buildTag(
                        '${set.dueFlashcardsCount} thẻ đến hạn SM-2',
                        AppTheme.amberWarning,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsTab(
    BuildContext context, {
    required List<SubjectEntity> subjects,
    required List<FlashcardEntity> dueCards,
    required List<StudySessionEntity> sessions,
  }) {
    double avgEf = 2.5;
    double avgInterval = 2.0;
    int avgRep = 1;

    if (dueCards.isNotEmpty) {
      avgEf = dueCards.fold<double>(0.0, (s, c) => s + c.easeFactor) / dueCards.length;
      avgInterval =
          dueCards.fold<int>(0, (s, c) => s + c.intervalDays) / dueCards.length;
      avgRep = (dueCards.fold<int>(0, (s, c) => s + c.repetitionCount) / dueCards.length)
          .round();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Biểu đồ 1: Đường cong ghi nhớ Ebbinghaus & SuperMemo SM-2
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Đường cong Ghi nhớ Ebbinghaus (RetentionCurvePainter)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đường xanh: Duy trì trí nhớ với SM-2 (EF TB: ${avgEf.toStringAsFixed(2)}) • Đường đỏ: Suy giảm tự nhiên không ôn tập',
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  RetentionCurveChart(
                    averageEaseFactor: avgEf,
                    averageIntervalDays: avgInterval,
                    averageRepetitionCount: avgRep,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Biểu đồ 2: Phân bổ thời gian học theo môn (SubjectDonutPainter)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '2. Phân bổ Thời lượng Học tập (SubjectDonutPainter)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Chạm trực tiếp vào từng cung tròn trên Canvas để xem chi tiết môn học',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  SubjectStudyDonutChart(subjects: subjects),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Biểu đồ 3: Hoạt động 7 ngày gần nhất (WeeklyActivityBarPainter)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '3. Hoạt động Ôn tập 7 Ngày qua (WeeklyActivityBarPainter)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cột Xanh dương: Thẻ Flashcards đã ôn • Cột Xanh lá: Câu hỏi Quiz đã hoàn thành',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  WeeklyActivityBarChart(sessions: sessions),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
