import 'package:drift/drift.dart';

import '../../../domain/entities/subject_entity.dart';
import '../database/app_database.dart';

/// DAO quản lý truy vấn Reactive Streams & CRUD cho bảng SUBJECTS
class SubjectDao {
  final AppDatabase _db;

  SubjectDao(this._db);

  /// Stream tự động phát dữ liệu mới mỗi khi subjects, documents, flashcards hoặc study_sessions thay đổi
  Stream<List<SubjectEntity>> watchAllActiveSubjects() {
    const sql = '''
      SELECT 
        s.id,
        s.title,
        s.code,
        s.color_hex,
        s.updated_at,
        s.is_deleted,
        (
          SELECT COUNT(*) FROM documents d 
          WHERE d.subject_id = s.id AND d.is_deleted = 0
        ) AS doc_count,
        (
          SELECT COUNT(*) FROM flashcards f
          INNER JOIN study_sets st ON f.study_set_id = st.id
          INNER JOIN documents d2 ON st.document_id = d2.id
          WHERE d2.subject_id = s.id 
            AND f.is_deleted = 0 
            AND st.is_deleted = 0
            AND d2.is_deleted = 0
            AND f.next_review_at <= ?1
        ) AS due_count,
        (
          SELECT COALESCE(SUM(ss.duration_seconds), 0) FROM study_sessions ss
          INNER JOIN study_sets st2 ON ss.study_set_id = st2.id
          INNER JOIN documents d3 ON st2.document_id = d3.id
          WHERE d3.subject_id = s.id
        ) AS total_seconds
      FROM subjects s
      WHERE s.is_deleted = 0
      ORDER BY s.updated_at DESC
    ''';

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return _db.customSelect(
      sql,
      variables: [Variable<int>(nowMs)],
      readsFrom: {
        _db.subjectsTable,
        _db.documentsTable,
        _db.studySetsTable,
        _db.flashcardsTable,
        _db.studySessionsTable,
      },
    ).watch().map((rows) {
      return rows.map((row) {
        final totalSec = row.readNullable<int>('total_seconds') ?? 0;
        return SubjectEntity(
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          code: row.read<String>('code'),
          colorHex: row.read<String>('color_hex'),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
          isDeleted: row.read<int>('is_deleted') == 1,
          documentCount: row.readNullable<int>('doc_count') ?? 0,
          dueFlashcardCount: row.readNullable<int>('due_count') ?? 0,
          totalStudyMinutes: (totalSec / 60).ceil(),
        );
      }).toList();
    });
  }

  Future<SubjectEntity?> getSubjectById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM subjects WHERE id = ?1 LIMIT 1',
      variables: [Variable<String>(id)],
      readsFrom: {_db.subjectsTable},
    ).get();

    if (rows.isEmpty) return null;
    final row = rows.first;
    return SubjectEntity(
      id: row.read<String>('id'),
      title: row.read<String>('title'),
      code: row.read<String>('code'),
      colorHex: row.read<String>('color_hex'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      isDeleted: row.read<int>('is_deleted') == 1,
    );
  }

  Future<void> upsertSubjectRaw({
    required String id,
    required String title,
    required String code,
    required String colorHex,
    required DateTime updatedAt,
    bool isDeleted = false,
  }) async {
    await _db.customInsert(
      '''
      INSERT INTO subjects (id, title, code, color_hex, updated_at, is_deleted)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        code = excluded.code,
        color_hex = excluded.color_hex,
        updated_at = excluded.updated_at,
        is_deleted = excluded.is_deleted
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(title),
        Variable<String>(code),
        Variable<String>(colorHex),
        Variable<int>(updatedAt.millisecondsSinceEpoch),
        Variable<int>(isDeleted ? 1 : 0),
      ],
      updates: {_db.subjectsTable},
    );
  }

  /// Tombstone Soft-Delete (is_deleted = true) chuẩn Offline-First
  Future<void> tombstoneDeleteSubject(String id, DateTime deletedAt) async {
    await _db.customUpdate(
      'UPDATE subjects SET is_deleted = 1, updated_at = ?1 WHERE id = ?2',
      variables: [
        Variable<int>(deletedAt.millisecondsSinceEpoch),
        Variable<String>(id),
      ],
      updates: {_db.subjectsTable},
      updateKind: UpdateKind.update,
    );
  }
}
