// Small date and time helpers for walk history. Kept local to avoid adding
// the intl package for a few labels.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// "Nov 9, 2026"
String formatWalkDate(DateTime time) =>
    '${_months[time.month - 1]} ${time.day}, ${time.year}';

// "3:05 PM"
String formatWalkTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

// "35 min" or "1 hr 5 min"
String formatWalkDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} hr' : '${minutes ~/ 60} hr $rest min';
}
