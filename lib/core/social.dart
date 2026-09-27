/// 弹幕与评论的数据模型与本地校验。
///
/// 后端把两者存成同一份 `Entry`（`mediaindex/danmaku.go`）：评论就是「时间点
/// 为 0 的弹幕」。因此这里也只用一个 [SocialEntry] 表达，用 [SocialEntry.type]
/// 区分。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

/// 条目类型，取值与后端 `DanmakuTypeComment / DanmakuTypeDanmaku` 一致。
abstract final class SocialType {
  /// 评论：挂在整部作品上，[SocialEntry.offsetMs] 恒为 0。
  static const int comment = 0;

  /// 弹幕：挂在时间轴的某个时刻上。
  static const int danmaku = 1;
}

/// 单条内容上限（按 Unicode 码点计），与后端保持一致。
///
/// 后端是「追加一行 JSON」的写法，长度上限是并发写安全的前提，不是体验限制；
/// 前端提前拦一下，省掉一次必然失败的往返。
const int maxDanmakuLength = 50;
const int maxCommentLength = 500;

/// 一条弹幕或评论。
class SocialEntry {
  const SocialEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.type,
    required this.offsetMs,
    required this.content,
    required this.createdAt,
    this.parentId = '',
  });

  /// 定长的「毫秒时间戳 + 同毫秒序号」，字典序即时间序。
  final String id;

  final int userId;

  /// 发送那一刻的昵称快照：用户后来改名，历史弹幕仍显示当时的名字。
  final String userName;

  /// 头像快照（预设 key，如 `01`）。
  final String userAvatar;

  final int type;

  /// 毫秒。弹幕为它在时间轴上出现的时刻，评论恒为 0。
  final int offsetMs;

  final String content;

  /// 回复的目标 ID；顶层评论为空。
  final String parentId;

  final DateTime createdAt;

  bool get isDanmaku => type == SocialType.danmaku;
  bool get isComment => type == SocialType.comment;

  /// 该条目是否由 [userId] 发出（用于「只能删自己的」）。
  bool isMine(int userId) => this.userId == userId;

  factory SocialEntry.fromJson(Map<String, dynamic> json) => SocialEntry(
    id: (json['id'] ?? '').toString(),
    userId: (json['user_id'] as num?)?.toInt() ?? 0,
    userName: (json['user_name'] ?? '').toString(),
    userAvatar: (json['user_avatar'] ?? '').toString(),
    type: (json['type'] as num?)?.toInt() ?? SocialType.comment,
    offsetMs: (json['offset'] as num?)?.toInt() ?? 0,
    content: (json['content'] ?? '').toString(),
    parentId: (json['parent_id'] ?? '').toString(),
    createdAt: _parseTime(json['created_at']),
  );

  static DateTime _parseTime(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// 一条顶层评论 + 它的回复（后端只支持一层回复）。
class CommentThread {
  const CommentThread({required this.root, required this.replies});

  final SocialEntry root;
  final List<SocialEntry> replies;

  /// 顶层与回复合计的条数。
  int get count => 1 + replies.length;

  factory CommentThread.fromJson(Map<String, dynamic> json) {
    final list = json['replies'];
    return CommentThread(
      root: SocialEntry.fromJson(json),
      replies: list is List
          ? list
                .whereType<Map>()
                .map((e) => SocialEntry.fromJson(e.cast<String, dynamic>()))
                .toList(growable: false)
          : const [],
    );
  }
}

/// 预校验弹幕文案，返回错误说明；`null` 表示可通过。
///
/// 按 Unicode 码点计数（与后端 `utf8.RuneCountInString` 对齐）——一个 emoji
/// 算一个字，而不是 Dart `String.length` 里的两个 UTF-16 码元。
String? validateDanmaku(String text) {
  final t = text.trim();
  if (t.isEmpty) return '弹幕内容不能为空';
  if (t.runes.length > maxDanmakuLength) {
    return '弹幕最多 $maxDanmakuLength 字，当前 ${t.runes.length} 字';
  }
  return null;
}

/// 预校验评论文案，返回错误说明；`null` 表示可通过。
String? validateComment(String text) {
  final t = text.trim();
  if (t.isEmpty) return '评论内容不能为空';
  if (t.runes.length > maxCommentLength) {
    return '评论最多 $maxCommentLength 字，当前 ${t.runes.length} 字';
  }
  return null;
}

/// 解析 SSE 的一帧，非弹幕帧（心跳等）返回 null。
///
/// 后端帧格式（见 `handlers/danmaku_stream.go`）：
/// ```
/// event: danmaku
/// data: {"id":"...","content":"..."}
///
/// ```
/// 帧之间用空行分隔，因此必须先把字节流攒成帧再解析——直接按行处理会在
/// 中文等多字节内容被 chunk 切断时拿到半截 JSON。
SocialEntry? parseDanmakuFrame(String frame) {
  String? data;
  for (final line in frame.split('\n')) {
    if (line.startsWith('data:')) {
      data = line.substring(5).trimLeft();
    }
  }
  if (data == null || data.isEmpty) return null; // 心跳帧 `: ping` 等
  final decoded = jsonDecode(data);
  if (decoded is! Map) return null;
  return SocialEntry.fromJson(decoded.cast<String, dynamic>());
}

/// 头像底色盘。
///
/// 后端 `/static/avatars/<key>.png` 实际返回的是 SVG，而 Flutter 内置的图片
/// 解码器不支持 SVG，所以这里按 key 在本地生成一枚纯色头像——同样能区分人，
/// 且不引入额外依赖。
const List<Color> avatarPalette = [
  Color(0xFF7FB77E),
  Color(0xFF6FA8DC),
  Color(0xFFC27BA0),
  Color(0xFFF2B880),
  Color(0xFF8E7CC3),
  Color(0xFF5BC0BE),
  Color(0xFFE3A857),
  Color(0xFF9FC5E8),
  Color(0xFFD98C8C),
  Color(0xFF84C7A0),
  Color(0xFFB49BD8),
  Color(0xFF6C9BD1),
];

/// 按头像 key 取一个稳定的底色。
///
/// key 形如 `01`…`12`；解析不出来时退化为按字符串哈希，保证同一个人始终同色。
Color avatarColor(String key) {
  final n = int.tryParse(key);
  final index = n != null
      ? (n - 1) % avatarPalette.length
      : key.runes.fold(0, (a, b) => (a + b) % avatarPalette.length);
  return avatarPalette[index < 0 ? 0 : index];
}

/// 头像上的文字：昵称首个字符，取不到时用 `?`。
String avatarLabel(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first).toUpperCase();
}
