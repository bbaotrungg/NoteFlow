import 'package:intl/intl.dart';

class DateTimeUtils {
  DateTimeUtils._();

  static String formatVietnameseDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }

  static String formatDateTimeShort(DateTime date) {
    return DateFormat('HH:mm - dd/MM/yyyy').format(date.toLocal());
  }

  static String formatRelativeReview(DateTime nextReviewAt, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = nextReviewAt.difference(current);

    if (diff.isNegative || diff.inMinutes <= 5) {
      return 'Cần ôn ngay';
    } else if (diff.inHours < 24) {
      return 'Sau ${diff.inHours} giờ';
    } else if (diff.inDays == 1) {
      return 'Ngày mai';
    } else if (diff.inDays < 30) {
      return 'Sau ${diff.inDays} ngày';
    } else {
      final months = (diff.inDays / 30).floor();
      return 'Sau $months tháng';
    }
  }

  static String formatDurationClock(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
