import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../daos/study_dao.dart';
import '../daos/subject_dao.dart';
import '../daos/sync_dao.dart';
import '../tables/noteflow_tables.dart';

part 'app_database.g.dart';

/// Cơ sở dữ liệu SQLite cục bộ chuẩn Type-Safe thông qua Drift ORM
/// Tích hợp Reactive Streams, Schema Migrations an toàn, Foreign Keys và dữ liệu mẫu VKU.
@DriftDatabase(
  tables: [
    Subjects,
    Documents,
    StudySets,
    Flashcards,
    QuizQuestions,
    StudySessions,
    SyncQueue,
  ],
  daos: [
    SubjectDao,
    StudyDao,
    SyncDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  late final SubjectDao subjectDao = SubjectDao(this);
  late final StudyDao studyDao = StudyDao(this);
  late final SyncDao syncDao = SyncDao(this);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await _createSchemaAndIndexes();
          await _seedInitialVkuData();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          await _createSchemaAndIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createSchemaAndIndexes() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS subjects (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        code TEXT NOT NULL,
        color_hex TEXT NOT NULL DEFAULT '#0284C7',
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY NOT NULL,
        subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        file_type TEXT NOT NULL,
        local_file_path TEXT NOT NULL,
        raw_extracted_text TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS study_sets (
        id TEXT PRIMARY KEY NOT NULL,
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        summary_markdown TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS flashcards (
        id TEXT PRIMARY KEY NOT NULL,
        study_set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
        front_text TEXT NOT NULL,
        back_text TEXT NOT NULL,
        hint TEXT,
        ease_factor REAL NOT NULL DEFAULT 2.5,
        interval_days INTEGER NOT NULL DEFAULT 0,
        repetition_count INTEGER NOT NULL DEFAULT 0,
        next_review_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS quiz_questions (
        id TEXT PRIMARY KEY NOT NULL,
        study_set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
        question_text TEXT NOT NULL,
        options_json TEXT NOT NULL,
        correct_index INTEGER NOT NULL,
        explanation TEXT NOT NULL,
        times_answered INTEGER NOT NULL DEFAULT 0,
        times_correct INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS study_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        study_set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
        session_type TEXT NOT NULL,
        score REAL,
        total_items INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        completed_at INTEGER NOT NULL
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');

    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_flashcards_review ON flashcards (is_deleted, next_review_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue (status, created_at);',
    );
  }

  /// Khởi tạo dữ liệu học thuật mẫu chuẩn Khoa KHMT - VKU phục vụ kiểm thử & Demo
  Future<void> _seedInitialVkuData() async {
    final now = DateTime.now();

    await subjectDao.upsertSubjectRaw(
      id: 'sub-vku-mobile-01',
      title: 'Phát triển Ứng dụng Di động Đa nền tảng',
      code: 'IT4409',
      colorHex: '#0284C7',
      updatedAt: now.subtract(const Duration(days: 5)),
    );
    await subjectDao.upsertSubjectRaw(
      id: 'sub-vku-ai-02',
      title: 'Trí tuệ Nhân tạo & Học sâu',
      code: 'IT3160',
      colorHex: '#7C3AED',
      updatedAt: now.subtract(const Duration(days: 4)),
    );
    await subjectDao.upsertSubjectRaw(
      id: 'sub-vku-db-03',
      title: 'Hệ Quản trị Cơ sở Dữ liệu Phân tán',
      code: 'IT3080',
      colorHex: '#059669',
      updatedAt: now.subtract(const Duration(days: 3)),
    );

    await studyDao.upsertDocumentRaw(
      id: 'doc-vku-clean-arch-01',
      subjectId: 'sub-vku-mobile-01',
      title: 'Chương 4: Clean Architecture, Riverpod 2 & Offline-First Sync',
      fileType: 'IMAGE',
      localFilePath: 'assets/sample/lecture_slide_ch4.png',
      rawExtractedText: '''
BÀI GIẢNG: KIẾN TRÚC PHẦN MỀM DI ĐỘNG HIỆN ĐẠI (VKU)
1. Clean Architecture chia ứng dụng thành 3 tầng độc lập:
- Domain Layer: Chứa Entities, UseCases, Repository Interfaces và thuật toán cốt lõi (như SuperMemo SM-2). Hoàn toàn độc lập với Flutter UI và thư viện bên thứ ba.
- Data Layer: Chứa Drift SQLite DAOs, Supabase Remote DataSource, Offline-First Sync Engine và các Repository Implementations.
- Presentation Layer: Chứa giao diện Material 3, CustomPainter 60 FPS và Riverpod 2 Notifiers.
2. Đồng bộ Offline-First với Last-Write-Wins (LWW):
- Mọi thao tác CRUD đều ghi trực tiếp vào SQLite cục bộ và thêm bản ghi vào bảng sync_queue.
- Khi xoá dữ liệu, sử dụng Tombstone Soft-Delete (is_deleted = true) thay vì xoá vật lý ngay để các thiết bị khác nhận biết được trạng thái xoá.
''',
      updatedAt: now.subtract(const Duration(days: 2)),
    );

    await studyDao.upsertStudySetRaw(
      id: 'set-vku-clean-arch-01',
      documentId: 'doc-vku-clean-arch-01',
      title: 'Tổng hợp Kiến trúc Clean Architecture & Đồng bộ Offline-First',
      summaryMarkdown: '''
### 📌 Tóm tắt Trọng tâm Học phần (AI Generated)

* **Clean Architecture 3 lớp:** Đảm bảo nguyên lý **Dependency Rule** — mọi sự phụ thuộc hướng vào bên trong (**Domain Layer**). Lớp Domain chỉ chứa quy tắc nghiệp vụ thuần túy (Entities, Use Cases, thuật toán **SuperMemo SM-2**) và không phụ thuộc vào cơ sở dữ liệu hay UI.
* **Quản lý trạng thái với Riverpod 2:** Sử dụng `AsyncNotifier` và `StreamProvider` kết nối trực tiếp với dòng dữ liệu phản ứng (**Reactive Streams**) từ **Drift SQLite ORM**, giúp giao diện tự động vẽ lại với độ trễ cực thấp mà không cần gọi `setState` thủ công.
* **Đồng bộ hai chiều Offline-First:**
  1. **Outbox Pattern (`sync_queue`):** Ghi nhận mọi biến đổi `INSERT`, `UPDATE`, `DELETE` khi mất mạng.
  2. **Tombstone Soft-Delete (`is_deleted = true`):** Đánh dấu xóa mềm để lan truyền trạng thái xóa lên **Supabase PostgreSQL**.
  3. **Last-Write-Wins (`updated_at`):** So sánh nhãn thời gian UTC để tự động phân xử xung đột giữa Local và Cloud.
''',
      updatedAt: now.subtract(const Duration(days: 2)),
    );

    await studyDao.upsertFlashcardRaw(
      id: 'fc-vku-01',
      studySetId: 'set-vku-clean-arch-01',
      frontText: 'Nguyên tắc Dependency Rule trong Clean Architecture phát biểu như thế nào?',
      backText: 'Mã nguồn chỉ được phép phụ thuộc hướng vào bên trong. Lớp Domain nằm ở tâm và hoàn toàn không biết gì về Data Layer (SQLite/Supabase) hay Presentation Layer (Flutter UI).',
      hint: 'Hãy nhớ chiều mũi tên giữa 3 vòng tròn kiến trúc.',
      easeFactor: 2.6,
      intervalDays: 1,
      repetitionCount: 1,
      nextReviewAt: now.subtract(const Duration(hours: 3)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    await studyDao.upsertFlashcardRaw(
      id: 'fc-vku-02',
      studySetId: 'set-vku-clean-arch-01',
      frontText: "Công thức cập nhật hệ số dễ (Ease Factor - EF') trong thuật toán SuperMemo SM-2 là gì?",
      backText: "EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)), trong đó q là điểm đánh giá từ 0..5 và EF' luôn được giới hạn tối thiểu >= 1.3.",
      hint: 'Hàm bậc hai theo độ lệch (5 - q).',
      easeFactor: 2.5,
      intervalDays: 0,
      repetitionCount: 0,
      nextReviewAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    await studyDao.upsertFlashcardRaw(
      id: 'fc-vku-03',
      studySetId: 'set-vku-clean-arch-01',
      frontText: 'Tại sao phải dùng cơ chế Tombstone Soft-Delete (is_deleted = true) trong hệ thống Offline-First?',
      backText: 'Vì nếu xóa cứng (Hard Delete) bản ghi khi đang offline, thiết bị sẽ mất dấu vết để báo cho Cloud xóa theo, hoặc bị Cloud ghi đè ngược lại bản ghi cũ khi đồng bộ.',
      hint: 'Vấn đề "bản ghi sống dậy" (Zombie Record) khi đồng bộ đa thiết bị.',
      easeFactor: 2.5,
      intervalDays: 0,
      repetitionCount: 0,
      nextReviewAt: now,
      updatedAt: now.subtract(const Duration(hours: 12)),
    );

    await studyDao.upsertFlashcardRaw(
      id: 'fc-vku-04',
      studySetId: 'set-vku-clean-arch-01',
      frontText: 'Thuật toán Spatial Row Clustering giải quyết hạn chế gì của Google ML Kit OCR?',
      backText: 'ML Kit trả về các TextBlock rời rạc không theo thứ tự dòng trên tài liệu đa cột. Spatial Row Clustering dùng tọa độ hình học boundingBox để phân cụm cột và sắp xếp đúng thứ tự đọc từ trái sang phải, trên xuống dưới.',
      hint: 'Xử lý tài liệu chia 2 cột hoặc bảng biểu.',
      easeFactor: 2.7,
      intervalDays: 6,
      repetitionCount: 2,
      nextReviewAt: now.add(const Duration(days: 4)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );

    await studyDao.upsertQuizQuestionRaw(
      id: 'qz-vku-01',
      studySetId: 'set-vku-clean-arch-01',
      questionText: 'Trong thuật toán lặp lại ngắt quãng SuperMemo SM-2, nếu người học đánh giá thẻ ở mức q = 2 (nhỏ hơn 3), khoảng cách ôn tập tiếp theo (Interval) sẽ được tính như thế nào?',
      optionsJson: jsonEncode([
        'Reset số lần lặp về 0 và đặt lịch ôn tập lại sau 1 ngày (I = 1)',
        'Giữ nguyên số lần lặp và nhân Interval cũ với hệ số EF mới',
        'Tăng Interval lên 6 ngày để người học có thêm thời gian suy ngẫm',
        'Xóa thẻ khỏi danh sách ưu tiên trong 7 ngày',
      ]),
      correctIndex: 0,
      explanation: 'Theo đặc tả SM-2, bất kỳ phản hồi nào có chất lượng q < 3 đều được coi là quên kiến thức: repetition_count bị đưa về 0 và interval_days quay lại mốc 1 ngày.',
      timesAnswered: 4,
      timesCorrect: 3,
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    await studyDao.upsertQuizQuestionRaw(
      id: 'qz-vku-02',
      studySetId: 'set-vku-clean-arch-01',
      questionText: 'Chiến lược giải quyết xung đột Last-Write-Wins (LWW) giữa Drift SQLite và Supabase PostgreSQL dựa trên trường dữ liệu nào?',
      optionsJson: jsonEncode([
        'Trường nhãn thời gian chuẩn hóa UTC updated_at của bản ghi',
        'Số thứ tự tự tăng (Auto-increment ID) trong bảng SQLite',
        'Kích thước chuỗi JSON payload_json trong hàng đợi',
        'Trạng thái kết nối Wi-Fi tại thời điểm mở ứng dụng',
      ]),
      correctIndex: 0,
      explanation: 'Last-Write-Wins so sánh trực tiếp trường updated_at (chuẩn hóa UTC) giữa bản ghi Local và bản ghi Remote để giữ lại phiên bản mới nhất.',
      timesAnswered: 3,
      timesCorrect: 3,
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    await studyDao.upsertQuizQuestionRaw(
      id: 'qz-vku-03',
      studySetId: 'set-vku-clean-arch-01',
      questionText: 'Để đảm bảo mỗi sinh viên chỉ có thể truy vấn và chỉnh sửa tài liệu của chính mình trên Supabase PostgreSQL, cơ chế bảo mật nào cần được kích hoạt?',
      optionsJson: jsonEncode([
        'Row-Level Security (RLS) kiểm tra điều kiện auth.uid() = user_id',
        'Mã hóa Base64 toàn bộ cột title trước khi lưu',
        'Chặn toàn bộ truy vấn SELECT từ ứng dụng di động',
        'Tắt khóa ngoại (Foreign Keys) trên bảng documents',
      ]),
      correctIndex: 0,
      explanation: 'Row-Level Security (RLS) trên PostgreSQL kiểm tra trực tiếp JWT token thông qua hàm auth.uid() = user_id ở cấp độ từng dòng dữ liệu.',
      timesAnswered: 5,
      timesCorrect: 4,
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      await studyDao.insertStudySessionRaw(
        id: 'sess-seed-fc-$i',
        studySetId: 'set-vku-clean-arch-01',
        sessionType: 'FLASHCARD',
        score: 82.0 + (i % 3) * 6.0,
        totalItems: 12 + (6 - i) * 3,
        durationSeconds: 420 + (6 - i) * 65,
        completedAt: day,
      );
      if (i % 2 == 0) {
        await studyDao.insertStudySessionRaw(
          id: 'sess-seed-qz-$i',
          studySetId: 'set-vku-clean-arch-01',
          sessionType: 'QUIZ',
          score: 85.0 + i * 2.0,
          totalItems: 10,
          durationSeconds: 310 + i * 30,
          completedAt: day.add(const Duration(hours: 2)),
        );
      }
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'noteflow_ai_vku.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
