import 'package:drift/drift.dart';

/// 1. BẢNG SUBJECTS (Môn học)
class Subjects extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get code => text()();
  TextColumn get colorHex => text().named('color_hex').withDefault(const Constant('#0284C7'))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. BẢNG DOCUMENTS (Tài liệu học tập)
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId => text().named('subject_id').references(Subjects, #id)();
  TextColumn get title => text()();
  TextColumn get fileType => text().named('file_type')(); // IMAGE / PDF / TEXT
  TextColumn get localFilePath => text().named('local_file_path')();
  TextColumn get rawExtractedText => text().named('raw_extracted_text')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 3. BẢNG STUDY_SETS (Bộ nội dung học tập được AI sinh ra)
class StudySets extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text().named('document_id').references(Documents, #id)();
  TextColumn get title => text()();
  TextColumn get summaryMarkdown => text().named('summary_markdown')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 4. BẢNG FLASHCARDS (Thẻ ghi nhớ với tham số SuperMemo SM-2)
class Flashcards extends Table {
  TextColumn get id => text()();
  TextColumn get studySetId => text().named('study_set_id').references(StudySets, #id)();
  TextColumn get frontText => text().named('front_text')();
  TextColumn get backText => text().named('back_text')();
  TextColumn get hint => text().nullable()();
  RealColumn get easeFactor => real().named('ease_factor').withDefault(const Constant(2.5))();
  IntColumn get intervalDays => integer().named('interval_days').withDefault(const Constant(0))();
  IntColumn get repetitionCount => integer().named('repetition_count').withDefault(const Constant(0))();
  DateTimeColumn get nextReviewAt => dateTime().named('next_review_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 5. BẢNG QUIZ_QUESTIONS (Câu hỏi trắc nghiệm)
class QuizQuestions extends Table {
  TextColumn get id => text()();
  TextColumn get studySetId => text().named('study_set_id').references(StudySets, #id)();
  TextColumn get questionText => text().named('question_text')();
  TextColumn get optionsJson => text().named('options_json')();
  IntColumn get correctIndex => integer().named('correct_index')();
  TextColumn get explanation => text()();
  IntColumn get timesAnswered => integer().named('times_answered').withDefault(const Constant(0))();
  IntColumn get timesCorrect => integer().named('times_correct').withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 6. BẢNG STUDY_SESSIONS (Lịch sử ôn tập)
class StudySessions extends Table {
  TextColumn get id => text()();
  TextColumn get studySetId => text().named('study_set_id').references(StudySets, #id)();
  TextColumn get sessionType => text().named('session_type')(); // FLASHCARD / QUIZ
  RealColumn get score => real().nullable()();
  IntColumn get totalItems => integer().named('total_items')();
  IntColumn get durationSeconds => integer().named('duration_seconds')();
  DateTimeColumn get completedAt => dateTime().named('completed_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// 7. BẢNG SYNC_QUEUE (Hàng đợi đồng bộ Offline-First)
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get tableNameField => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get operation => text()(); // INSERT / UPDATE / DELETE
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  IntColumn get retryCount => integer().named('retry_count').withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
