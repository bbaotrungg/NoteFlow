enum DocumentFileType {
  image('IMAGE'),
  pdf('PDF'),
  text('TEXT');

  final String dbValue;
  const DocumentFileType(this.dbValue);

  static DocumentFileType fromString(String value) {
    return DocumentFileType.values.firstWhere(
      (e) => e.dbValue.toUpperCase() == value.toUpperCase(),
      orElse: () => DocumentFileType.text,
    );
  }
}

/// Thực thể Tài liệu học tập (DOCUMENTS)
class DocumentEntity {
  final String id;
  final String subjectId;
  final String title;
  final DocumentFileType fileType;
  final String localFilePath;
  final String rawExtractedText;
  final DateTime updatedAt;
  final bool isDeleted;

  const DocumentEntity({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.fileType,
    required this.localFilePath,
    required this.rawExtractedText,
    required this.updatedAt,
    this.isDeleted = false,
  });

  DocumentEntity copyWith({
    String? id,
    String? subjectId,
    String? title,
    DocumentFileType? fileType,
    String? localFilePath,
    String? rawExtractedText,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return DocumentEntity(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      fileType: fileType ?? this.fileType,
      localFilePath: localFilePath ?? this.localFilePath,
      rawExtractedText: rawExtractedText ?? this.rawExtractedText,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'file_type': fileType.dbValue,
        'local_file_path': localFilePath,
        'raw_extracted_text': rawExtractedText,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  factory DocumentEntity.fromSyncJson(Map<String, dynamic> json) => DocumentEntity(
        id: json['id'] as String,
        subjectId: json['subject_id'] as String,
        title: json['title'] as String,
        fileType: DocumentFileType.fromString(json['file_type'] as String? ?? 'TEXT'),
        localFilePath: (json['local_file_path'] as String?) ?? '',
        rawExtractedText: (json['raw_extracted_text'] as String?) ?? '',
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        isDeleted: (json['is_deleted'] as bool?) ?? false,
      );
}
