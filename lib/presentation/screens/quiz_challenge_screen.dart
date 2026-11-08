import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../domain/entities/quiz_question_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../providers/app_providers.dart';

/// Màn hình Thi trắc nghiệm bấm giờ (Quiz Challenge Engine)
/// - Hiển thị thanh đếm ngược thời gian làm bài
/// - Tự động tạm dừng đếm ngược khi học sinh đang đọc giải thích học thuật
/// - Chấm điểm tức thì kèm lời giải thích học thuật chi tiết
/// - Cho phép làm lại Quiz (Retry) ngay lập tức
/// - Ghi nhận kết quả vào bảng study_sessions và hàng đợi đồng bộ Offline-First
class QuizChallengeScreen extends ConsumerStatefulWidget {
  final String studySetId;
  final String title;
  final List<QuizQuestionEntity> questions;

  const QuizChallengeScreen({
    super.key,
    required this.studySetId,
    required this.title,
    required this.questions,
  });

  @override
  ConsumerState<QuizChallengeScreen> createState() => _QuizChallengeScreenState();
}

class _QuizChallengeScreenState extends ConsumerState<QuizChallengeScreen> {
  static const int _secondsPerQuestion = 45;

  late final List<QuizQuestionEntity> _quizList;
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _isAnswered = false;
  int _correctCount = 0;
  late int _remainingSeconds;
  int _elapsedSeconds = 0;
  Timer? _countdownTimer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _quizList = List<QuizQuestionEntity>.from(widget.questions);
    _remainingSeconds = _quizList.length * _secondsPerQuestion;
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isFinished) return;
      // Tạm dừng đếm ngược thời gian làm bài khi học sinh đang đọc phần giải thích đáp án
      if (_isAnswered) return;
      setState(() {
        _elapsedSeconds++;
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _finishQuizSession();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectOption(int index) async {
    if (_isAnswered || _isFinished) return;
    final currentQ = _quizList[_currentIndex];
    final isCorrect = index == currentQ.correctIndex;

    setState(() {
      _selectedOptionIndex = index;
      _isAnswered = true;
      if (isCorrect) _correctCount++;
    });

    await ref.read(studyRepositoryProvider).recordQuizAnswer(
          questionId: currentQ.id,
          isCorrect: isCorrect,
        );
  }

  Future<void> _nextQuestion() async {
    if (_currentIndex + 1 < _quizList.length) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _isAnswered = false;
      });
    } else {
      await _finishQuizSession();
    }
  }

  Future<void> _finishQuizSession() async {
    if (_isFinished) return;
    _countdownTimer?.cancel();
    setState(() {
      _isFinished = true;
    });

    final score = _quizList.isEmpty ? 0.0 : (_correctCount / _quizList.length) * 100.0;
    await ref.read(studyRepositoryProvider).recordStudySession(
          studySetId: widget.studySetId,
          sessionType: StudySessionType.quiz,
          score: score,
          totalItems: _quizList.length,
          durationSeconds: _elapsedSeconds,
        );
  }

  void _retryQuiz() {
    setState(() {
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _isAnswered = false;
      _correctCount = 0;
      _isFinished = false;
      _elapsedSeconds = 0;
      _remainingSeconds = _quizList.length * _secondsPerQuestion;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Quiz: ${widget.title}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (_remainingSeconds < 30
                          ? AppTheme.roseDanger
                          : AppTheme.primarySkyBlue)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 16,
                      color: _remainingSeconds < 30
                          ? AppTheme.roseDanger
                          : AppTheme.primarySkyBlue,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      DateTimeUtils.formatDurationClock(_remainingSeconds),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _remainingSeconds < 30
                            ? AppTheme.roseDanger
                            : AppTheme.primarySkyBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _quizList.isEmpty
            ? const Center(child: Text('Bộ học liệu này chưa có câu hỏi trắc nghiệm.'))
            : _isFinished
                ? _buildQuizResultView(context)
                : _buildActiveQuizView(context),
      ),
    );
  }

  Widget _buildActiveQuizView(BuildContext context) {
    final q = _quizList[_currentIndex];
    final progress = (_currentIndex + 1) / _quizList.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Tiến trình & Điểm số
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Câu hỏi ${_currentIndex + 1} / ${_quizList.length}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              Text(
                'Đúng: $_correctCount câu',
                style: const TextStyle(
                  color: AppTheme.emeraldAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppTheme.primarySkyBlue.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation(AppTheme.primarySkyBlue),
            ),
          ),
          const SizedBox(height: 22),

          // Nội dung câu hỏi
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                q.questionText,
                style: const TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Phương án trả lời A, B, C, D
          ...List.generate(q.options.length, (idx) {
            final isChosen = _selectedOptionIndex == idx;
            final isCorrectOption = idx == q.correctIndex;

            Color borderColor = Colors.grey.withValues(alpha: 0.3);
            Color backgroundColor = Colors.transparent;
            IconData? trailingIcon;

            if (_isAnswered) {
              if (isCorrectOption) {
                borderColor = AppTheme.emeraldAccent;
                backgroundColor = AppTheme.emeraldAccent.withValues(alpha: 0.16);
                trailingIcon = Icons.check_circle_rounded;
              } else if (isChosen && !isCorrectOption) {
                borderColor = AppTheme.roseDanger;
                backgroundColor = AppTheme.roseDanger.withValues(alpha: 0.16);
                trailingIcon = Icons.cancel_rounded;
              }
            } else if (isChosen) {
              borderColor = AppTheme.primarySkyBlue;
              backgroundColor = AppTheme.primarySkyBlue.withValues(alpha: 0.14);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _selectOption(idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 1.6),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: (isChosen
                                ? AppTheme.primarySkyBlue
                                : Colors.grey)
                            .withValues(alpha: 0.2),
                        child: Text(
                          String.fromCharCode(65 + idx),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isChosen ? AppTheme.primarySkyBlue : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          q.options[idx],
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                      if (trailingIcon != null)
                        Icon(
                          trailingIcon,
                          color: isCorrectOption
                              ? AppTheme.emeraldAccent
                              : AppTheme.roseDanger,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_isAnswered) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primarySkyBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primarySkyBlue.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.psychology_rounded,
                          size: 20, color: AppTheme.primarySkyBlue),
                      SizedBox(width: 8),
                      Text(
                        'Giải thích chi tiết:',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primarySkyBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q.explanation,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _nextQuestion,
              icon: Icon(
                _currentIndex + 1 < _quizList.length
                    ? Icons.arrow_forward_rounded
                    : Icons.flag_rounded,
              ),
              label: Text(
                _currentIndex + 1 < _quizList.length
                    ? 'Câu hỏi tiếp theo'
                    : 'Hoàn thành & Xem điểm',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizResultView(BuildContext context) {
    final score = _quizList.isEmpty ? 0.0 : (_correctCount / _quizList.length) * 100.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  score >= 70 ? Icons.emoji_events_rounded : Icons.school_rounded,
                  size: 68,
                  color: score >= 70 ? AppTheme.amberWarning : AppTheme.primarySkyBlue,
                ),
                const SizedBox(height: 14),
                Text(
                  'Điểm số: ${score.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trả lời đúng $_correctCount / ${_quizList.length} câu trong ${DateTimeUtils.formatDurationClock(_elapsedSeconds)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _retryQuiz,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Làm lại Quiz'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Hoàn tất bài kiểm tra'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
