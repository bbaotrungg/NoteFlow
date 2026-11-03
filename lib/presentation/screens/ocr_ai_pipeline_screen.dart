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
/// 4. Kiểm duyệt / Chỉnh sửa nội dung trước khi lưu vào Drift SQLite & Sync Queue
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

  String? _selectedSubjectId;
  List<AiGeneratedFlashcardDraft> _editableFlashcards = [];
  List<AiGeneratedQuizDraft> _editableQuizzes = [];

  @override
  void initState() {
    super.initState();
    if (widget.subjects.isNotEmpty) {
      _selectedSubjectId = widget.subjects.first.id;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ocrTextController.dispose();
    _summaryController.dispose();
    super.dispose();
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

  Future<void> _handleCommitToDatabase() async {
    final subjectId = _selectedSubjectId;
    if (subjectId == null) return;

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
                      DropdownButtonFormField<String>(
                        value: _selectedSubjectId,
                        decoration: const InputDecoration(
                          labelText: 'Thuộc Môn học (VKU)',
                          prefixIcon: Icon(Icons.folder_special_rounded),
                        ),
                        items: widget.subjects.map((s) {
                          return DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.code} - ${s.title}'),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedSubjectId = val),
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
                            color: AppTheme.emeraldAccent.withOpacity(0.14),
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
                    color: AppTheme.roseDanger.withOpacity(0.15),
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
                          'Bản tóm tắt Markdown:',
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
                        const SizedBox(height: 16),
                        Text(
                          'Danh sách Thẻ ghi nhớ Flashcards (${_editableFlashcards.length} thẻ):',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_editableFlashcards.length, (idx) {
                          final fc = _editableFlashcards[idx];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primarySkyBlue.withOpacity(0.2),
                              child: Text('${idx + 1}', style: const TextStyle(fontSize: 12)),
                            ),
                            title: Text(fc.front,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            subtitle: Text(fc.back, style: const TextStyle(fontSize: 12.5)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () {
                                setState(() => _editableFlashcards.removeAt(idx));
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        Text(
                          'Danh sách Câu hỏi Trắc nghiệm Quiz (${_editableQuizzes.length} câu):',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_editableQuizzes.length, (idx) {
                          final qz = _editableQuizzes[idx];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.emeraldAccent.withOpacity(0.2),
                              child: Text('Q${idx + 1}', style: const TextStyle(fontSize: 11)),
                            ),
                            title: Text(qz.question,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            subtitle: Text(
                              'Đáp án đúng: ${qz.options[qz.correctIndex]}',
                              style: const TextStyle(
                                color: AppTheme.emeraldAccent,
                                fontSize: 12.5,
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
