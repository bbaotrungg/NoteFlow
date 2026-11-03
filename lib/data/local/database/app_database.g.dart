// GENERATED CODE - HAND-CRAFTED DRIFT PART FILE FOR IMMEDIATE COMPILATION
part of 'app_database.dart';

// ignore_for_file: type=lint, unused_element

class _TableHandle extends TableInfo<Table, dynamic> {
  final GeneratedDatabase _db;
  @override
  final String actualTableName;

  _TableHandle(this._db, this.actualTableName);

  @override
  DatabaseConnectionUser get attachedDatabase => _db;

  @override
  List<GeneratedColumn> get $columns => const [];

  @override
  String get aliasedName => actualTableName;

  @override
  TableInfo<Table, dynamic> createAlias(String alias) => _TableHandle(_db, alias);

  @override
  Future<dynamic> map(Map<String, dynamic> data, {String? tablePrefix}) async => data;

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(super.e);

  late final TableInfo<Table, dynamic> subjectsTable = _TableHandle(this, 'subjects');
  late final TableInfo<Table, dynamic> documentsTable = _TableHandle(this, 'documents');
  late final TableInfo<Table, dynamic> studySetsTable = _TableHandle(this, 'study_sets');
  late final TableInfo<Table, dynamic> flashcardsTable = _TableHandle(this, 'flashcards');
  late final TableInfo<Table, dynamic> quizQuestionsTable = _TableHandle(this, 'quiz_questions');
  late final TableInfo<Table, dynamic> studySessionsTable = _TableHandle(this, 'study_sessions');
  late final TableInfo<Table, dynamic> syncQueueTable = _TableHandle(this, 'sync_queue');

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => [
        subjectsTable,
        documentsTable,
        studySetsTable,
        flashcardsTable,
        quizQuestionsTable,
        studySessionsTable,
        syncQueueTable,
      ];

  void notifyTablesUpdated(Iterable<TableInfo<Table, dynamic>> tables) {
    markTablesUpdated(tables);
  }
}
