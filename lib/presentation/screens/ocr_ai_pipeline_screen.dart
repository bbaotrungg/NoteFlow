import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/ai_generated_study_content.dart';
import '../../domain/entities/subject_entity.dart';
import '../providers/app_providers.dart';

/// Màn hình Pipeline Phân hệ 2:
/// 1. Chụp/Chọn ảnh tài liệu & Cắt phối cảnh (ImageCropper UCropActivity)
/// 2. Nhận diện On-Device ML Kit OCR kèm Spatial Row Clustering & cho phép sinh viên chỉnh sửa văn bản OCR
/// 3. Gọi Gemini 1.5 Flash sinh Structured JSON (Summary, Flashcards, Quiz)
/// 4. Kiểm duyệt / Chỉnh sửa trọn vẹn nội dung AI sinh ra trước khi lưu vào Drift SQLite & Sync Queue
class OcrAiPipelineScreen extends ConsumerStatefulWidget {
  final List<SubjectEntity> subjects;

  const OcrAiPipelineScreen({
    super.key,
    required this.subjects,
  });

  @override
  ConsumerState<OcrAiPipelineScreen> createState() => _OcrAiPipelineScreenState();
}

class _OcrAiPipelineScreenState extends ConsumerState<OcrAiPipelineScreen> {
  final TextEditingController _titleController = TextEditingController(
    text: 'Bài giảng Chương 5: Xử lý Đa luồng & Bất đồng bộ trong Dart 3',
  );
  final TextEditingController _ocrTextController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();

  late List<SubjectEntity> _availableSubjects;
  String? _selectedSubjectId;
  List<AiGeneratedFlashcardDraft> _editableFlashcards = [];
  List<AiGeneratedQuizDraft> _editableQuizzes = [];

  @override
  void initState() {
    super.initState();
    _availableSubjects = List<SubjectEntity>.from(widget.subjects);
    if (_availableSubjects.isNotEmpty) {
      _selectedSubjectId = _availableSubjects.first.id;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ocrTextController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

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
              title: const Text('Thêm Môn Học Mới'),
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
                    final created = await ref.read(studyRepositoryProvider).createSubject(
                          title: titleCtrl.text.trim(),
                          code: codeCtrl.text.trim(),
                          colorHex: selectedColor,
                        );
                    if (mounted) {
                      setState(() {
                        _availableSubjects.add(created);
                        _selectedSubjectId = created.id;
                      });
                    }
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

  Future<void> _handleScanImage(ImageSource source) async {
    await ref.read(documentPipelineProvider.notifier).scanAndExtractText(source);
    final ocrResult = ref.read(documentPipelineProvider).ocrResult;
    if (ocrResult != null) {
      setState(() {
        _ocrTextController.text = ocrResult.structuredText;
      });
    }
  }

  void _handleLoadMultiColumnSimulation() {
    ref.read(documentPipelineProvider.notifier).loadSampleMultiColumnLectureForOcrDemo();
    final ocrResult = ref.read(documentPipelineProvider).ocrResult;
    if (ocrResult != null) {
      setState(() {
        _ocrTextController.text = ocrResult.structuredText;
      });
    }
  }

  Future<void> _handleGenerateWithGemini() async {
    if (_ocrTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng quét ảnh OCR hoặc nhập văn bản bài giảng trước!')),
      );
      return;
    }

    await ref.read(documentPipelineProvider.notifier).generateAiStudyMaterials(
          documentTitle: _titleController.text.trim(),
          verifiedOcrText: _ocrTextController.text.trim(),
        );

    final generated = ref.read(documentPipelineProvider).generatedContent;
    if (generated != null) {
      setState(() {
        _summaryController.text = generated.summaryMarkdown;
        _editableFlashcards = List.from(generated.flashcards);
        _editableQuizzes = List.from(generated.quiz);
      });
    }
  }

  Future<void> _showFlashcardEditorDialog({int? index}) async {
    final isNew = index == null;
    final existing = isNew ? null : _editableFlashcards[index];
    final frontCtrl = TextEditingController(text: existing?.front ?? '');
    final backCtrl = TextEditingController(text: existing?.back ?? '');
    final hintCtrl = TextEditingController(text: existing?.hint ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isNew ? 'Thêm Thẻ Ghi Nhớ' : 'Chỉnh Sửa Thẻ Ghi Nhớ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: frontCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mặt trước (Câu hỏi / Khái niệm)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: backCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mặt sau (Định nghĩa / Giải thích)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gợi ý (Tùy chọn)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (frontCtrl.text.trim().isEmpty || backCtrl.text.trim().isEmpty) return;
                final updated = AiGeneratedFlashcardDraft(
                  front: frontCtrl.text.trim(),
                  back: backCtrl.text.trim(),
                  hint: hintCtrl.text.trim().isEmpty ? null : hintCtrl.text.trim(),
                );
                setState(() {
                  if (isNew) {
                    _editableFlashcards.add(updated);
                  } else {
                    _editableFlashcards[index] = updated;
                  }
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu Thẻ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showQuizEditorDialog({int? index}) async {
    final isNew = index == null;
    final existing = isNew ? null : _editableQuizzes[index];
    final questionCtrl = TextEditingController(text: existing?.question ?? '');
    final optionCtrls = List.generate(4, (i) {
      return TextEditingController(
        text: existing != null && i < existing.options.length ? existing.options[i] : '',
      );
    });
    int correctIndex = existing?.correctIndex ?? 0;
    final explanationCtrl = TextEditingController(text: existing?.explanation ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isNew ? 'Thêm Câu Hỏi Quiz' : 'Chỉnh Sửa Câu Hỏi Quiz'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: questionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nội dung câu hỏi',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 14),
                    const Text('4 Phương án trả lời (Chọn radio để đặt đáp án đúng):',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...List.generate(4, (optIdx) {
                      return Row(
                        children: [
                          // ignore: deprecated_member_use
                          Radio<int>(
                            value: optIdx,
                            // ignore: deprecated_member_use
                            groupValue: correctIndex,
                            // ignore: deprecated_member_use
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => correctIndex = val);
                              }
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: optionCtrls[optIdx],
                              decoration: InputDecoration(
                                hintText: 'Lựa chọn ${String.fromCharCode(65 + optIdx)}',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    TextField(
                      controller: explanationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Giải thích chi tiết tại sao đúng',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final qText = questionCtrl.text.trim();
                    final options = optionCtrls.map((c) => c.text.trim()).toList();
                    if (qText.isEmpty || options.any((o) => o.isEmpty)) return;
                    final updated = AiGeneratedQuizDraft(
                      question: qText,
                      options: options,
                      correctIndex: correctIndex,
                      explanation: explanationCtrl.text.trim().isEmpty
                          ? 'Đáp án chính xác theo tài liệu.'
                          : explanationCtrl.text.trim(),
                    );
                    setState(() {
                      if (isNew) {
                        _editableQuizzes.add(updated);
                      } else {
                        _editableQuizzes[index] = updated;
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Lưu Câu Hỏi'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleCommitToDatabase() async {
    final subjectId = _selectedSubjectId;
    if (subjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.roseDanger,
          content: Text('Vui lòng chọn hoặc thêm một môn học trước khi lưu bộ học liệu!'),
        ),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.roseDanger,
          content: Text('Vui lòng nhập tiêu đề cho bộ học liệu!'),
        ),
      );
      return;
    }

    final verifiedContent = AiGeneratedStudyContent(
      summaryMarkdown: _summaryController.text.trim(),
      flashcards: _editableFlashcards,
      quiz: _editableQuizzes,
    );

    final saved = await ref.read(documentPipelineProvider.notifier).commitVerifiedStudySet(
          subjectId: subjectId,
          documentTitle: _titleController.text.trim(),
          rawExtractedText: _ocrTextController.text.trim(),
          verifiedContent: verifiedContent,
        );

    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.emeraldAccent,
          content: Text('Đã lưu Bộ học liệu vào SQLite và đưa vào hàng đợi đồng bộ Offline-First!'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pipelineState = ref.watch(documentPipelineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét OCR & Sinh Học Liệu Gemini AI'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bước 1: Chọn môn học & Tiêu đề tài liệu
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bước 1: Thông tin Tài liệu & Nguồn ảnh OCR',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedSubjectId,
                              decoration: const InputDecoration(
                                labelText: 'Thuộc Môn học (VKU)',
                                prefixIcon: Icon(Icons.folder_special_rounded),
                              ),
                              items: _availableSubjects.map((s) {
                                return DropdownMenuItem(
                                  value: s.id,
                                  child: Text('${s.code} - ${s.title}', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedSubjectId = val),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Thêm môn học mới',
                            onPressed: () => _showCreateSubjectDialog(context),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Tiêu đề bài giảng / tài liệu',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: pipelineState.isProcessingOcr
                                ? null
                                : () => _handleScanImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_rounded),
                            label: const Text('Chụp Camera + Crop'),
                          ),
                          OutlinedButton.icon(
                            onPressed: pipelineState.isProcessingOcr
                                ? null
                                : () => _handleScanImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text('Chọn Ảnh Thư Viện'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _handleLoadMultiColumnSimulation,
                            icon: const Icon(Icons.auto_awesome_mosaic_rounded),
                            label: const Text('Nạp Mẫu OCR Đa Cột (Spatial Clustering)'),
                          ),
                        ],
                      ),
                      if (pipelineState.ocrResult != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.emeraldAccent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '⚡ On-Device ML Kit OCR hoàn tất trong ${pipelineState.ocrResult!.processingTimeMs}ms • '
                            'Phát hiện ${pipelineState.ocrResult!.detectedColumnsCount} cột • '
                            'Gom thành công ${pipelineState.ocrResult!.clusteredRows.length} dòng văn bản.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.emeraldAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bước 2: Kiểm duyệt văn bản OCR trước khi gửi cho Gemini
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Bước 2: Kiểm duyệt Văn bản OCR (Trước khi gửi Gemini 1.5 Flash)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ocrTextController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText:
                              'Văn bản sau khi gom dòng không gian (Spatial Row Clustering) sẽ hiển thị tại đây. Bạn có thể chỉnh sửa trước khi gửi AI...',
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: pipelineState.isGeneratingAi ? null : _handleGenerateWithGemini,
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.violetAi),
                        icon: pipelineState.isGeneratingAi
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          pipelineState.isGeneratingAi
                              ? 'Đang phân tích với Gemini 1.5 Flash (Structured JSON)...'
                              : 'Sinh Tóm tắt, Flashcards & Quiz bằng Gemini 1.5 Flash',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (pipelineState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.roseDanger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.roseDanger),
                  ),
                  child: Text(
                    pipelineState.errorMessage!,
                    style: const TextStyle(color: AppTheme.roseDanger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              // Bước 3: Màn hình chỉnh sửa / duyệt nội dung AI sinh ra trước khi Commit
              if (_summaryController.text.isNotEmpty || _editableFlashcards.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Bước 3: Duyệt & Chỉnh sửa Kết quả AI trước khi Lưu',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Bản tóm tắt Markdown (chỉnh sửa trực tiếp):',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _summaryController,
                          maxLines: 5,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: MarkdownBody(data: _summaryController.text),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thẻ ghi nhớ Flashcards (${_editableFlashcards.length} thẻ):',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            TextButton.icon(
                              onPressed: () => _showFlashcardEditorDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Thêm thẻ'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_editableFlashcards.length, (idx) {
                          final fc = _editableFlashcards[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.primarySkyBlue.withValues(alpha: 0.2),
                                child: Text('${idx + 1}', style: const TextStyle(fontSize: 12)),
                              ),
                              title: Text(fc.front,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              subtitle: Text(
                                fc.back,
                                style: const TextStyle(fontSize: 12.5),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _showFlashcardEditorDialog(index: idx),
                                    tooltip: 'Sửa nội dung thẻ',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () {
                                      setState(() => _editableFlashcards.removeAt(idx));
                                    },
                                    tooltip: 'Xóa thẻ này',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Câu hỏi Trắc nghiệm Quiz (${_editableQuizzes.length} câu):',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            TextButton.icon(
                              onPressed: () => _showQuizEditorDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Thêm câu hỏi'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_editableQuizzes.length, (idx) {
                          final qz = _editableQuizzes[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.emeraldAccent.withValues(alpha: 0.2),
                                child: Text('Q${idx + 1}', style: const TextStyle(fontSize: 11)),
                              ),
                              title: Text(qz.question,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              subtitle: Text(
                                'Đáp án đúng: ${qz.options.isNotEmpty && qz.correctIndex < qz.options.length ? qz.options[qz.correctIndex] : "Chưa chọn"}',
                                style: const TextStyle(
                                  color: AppTheme.emeraldAccent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _showQuizEditorDialog(index: idx),
                                    tooltip: 'Sửa câu hỏi & đáp án',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () {
                                      setState(() => _editableQuizzes.removeAt(idx));
                                    },
                                    tooltip: 'Xóa câu hỏi này',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: pipelineState.isSaving ? null : _handleCommitToDatabase,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text(
                            'Xác nhận & Lưu vào Drift SQLite + Đồng bộ Cloud',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
