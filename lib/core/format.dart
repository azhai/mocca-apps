/// 展示层格式化工具。
library;

/// 把毫秒格式化为 `H:MM:SS` 或 `M:SS`。
///
/// 传入负数或 0 时返回 `0:00`；用于播放器进度与列表中的时长展示。
String formatDuration(int milliseconds) {
  if (milliseconds <= 0) return '0:00';
  final total = milliseconds ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 把字节数格式化为人类可读大小。
String formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前 / 具体日期。
String formatRelative(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.year}-${_two(time.month)}-${_two(time.day)}';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 根据文件名后缀粗略判断媒体类型。
///
/// 仅在后端未给出可靠 `type` 时作为兜底；正常情况下应使用后端返回的 `type`。
int guessKindFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 1;
  final ext = name.substring(dot + 1).toLowerCase();
  const videos = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', 'ts', 'flv', 'wmv'};
  const audios = {'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma'};
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif'};
  if (videos.contains(ext)) return 2;
  if (audios.contains(ext)) return 3;
  if (images.contains(ext)) return 5;
  return 1;
}
