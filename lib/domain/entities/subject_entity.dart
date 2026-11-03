/// Thực thể Môn học (SUBJECTS) trong Domain Layer
class SubjectEntity {
  final String id;
  final String title;
  final String code;
  final String colorHex;
  final DateTime updatedAt;
  final bool isDeleted;

  // Thống kê tổng hợp phục vụ UI & CustomPainter
  final int documentCount;
  final int dueFlashcardCount;
  final int totalStudyMinutes;

  const SubjectEntity({
    required this.id,
    required this.title,
    required this.code,
    required this.colorHex,
    required this.updatedAt,
    this.isDeleted = false,
    this.documentCount = 0,
    this.dueFlashcardCount = 0,
    this.totalStudyMinutes = 0,
  });

  SubjectEntity copyWith({
    String? id,
    String? title,
    String? code,
    String? colorHex,
    DateTime? updatedAt,
    bool? isDeleted,
    int? documentCount,
    int? dueFlashcardCount,
    int? totalStudyMinutes,
  }) {
    return SubjectEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      code: code ?? this.code,
      colorHex: colorHex ?? this.colorHex,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      documentCount: documentCount ?? this.documentCount,
      dueFlashcardCount: dueFlashcardCount ?? this.dueFlashcardCount,
      totalStudyMinutes: totalStudyMinutes ?? this.totalStudyMinutes,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'title': title,
        'code': code,
        'color_hex': colorHex,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  factory SubjectEntity.fromSyncJson(Map<String, dynamic> json) => SubjectEntity(
        id: json['id'] as String,
        title: json['title'] as String,
        code: json['code'] as String,
        colorHex: (json['color_hex'] as String?) ?? '#0284C7',
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        isDeleted: (json['is_deleted'] as bool?) ?? false,
      );
}
