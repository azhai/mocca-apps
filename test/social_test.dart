import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/social.dart';

void main() {
  final now = DateTime.parse('2026-09-26T10:00:00Z');

  SocialEntry entry({
    String id = '00001720000000000001',
    int userId = 7,
    String name = 'cm',
    String avatar = '01',
    int type = SocialType.danmaku,
    int offset = 30000,
    String content = '前方高能',
    String parentId = '',
  }) => SocialEntry(
    id: id,
    userId: userId,
    userName: name,
    userAvatar: avatar,
    type: type,
    offsetMs: offset,
    content: content,
    parentId: parentId,
    createdAt: now,
  );

  group('条目解析', () {
    test('按后端字段名逐项解析', () {
      final e = SocialEntry.fromJson({
        'id': '00001720000000000001',
        'user_id': 7,
        'user_name': 'cm',
        'user_avatar': '01',
        'type': 1,
        'offset': 30000,
        'content': '前方高能',
        'created_at': '2026-09-26T10:00:00Z',
      });
      expect(e.id, '00001720000000000001');
      expect(e.userId, 7);
      expect(e.userName, 'cm');
      expect(e.userAvatar, '01');
      expect(e.isDanmaku, isTrue);
      expect(e.isComment, isFalse);
      expect(e.offsetMs, 30000);
      expect(e.content, '前方高能');
      expect(e.parentId, '');
      expect(e.createdAt, now);
    });

    test('字段缺失时回退到安全值，不抛异常', () {
      final e = SocialEntry.fromJson({});
      expect(e.id, '');
      expect(e.userId, 0);
      expect(e.type, SocialType.comment);
      expect(e.isDanmaku, isFalse);
      expect(e.offsetMs, 0);
      expect(e.parentId, '');
    });

    test('created_at 非法时不崩，落到 epoch', () {
      final e = SocialEntry.fromJson({'created_at': 'not-a-time'});
      expect(e.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('isMine 用于判断是否可删', () {
      expect(entry(userId: 7).isMine(7), isTrue);
      expect(entry(userId: 7).isMine(8), isFalse);
    });
  });

  group('评论线程', () {
    test('顶层评论带回复，count 含回复', () {
      final t = CommentThread.fromJson({
        ...{
          'id': 'top',
          'user_name': 'a',
          'type': 0,
          'content': '好看',
          'created_at': '2026-09-26T10:00:00Z',
        },
        'replies': [
          {
            'id': 'r1',
            'user_name': 'b',
            'type': 0,
            'content': '同感',
            'parent_id': 'top',
            'created_at': '2026-09-26T10:01:00Z',
          },
        ],
      });
      expect(t.root.id, 'top');
      expect(t.replies.length, 1);
      expect(t.replies.first.parentId, 'top');
      expect(t.count, 2);
    });

    test('没有 replies 字段时为空列表', () {
      final t = CommentThread.fromJson({'id': 'top', 'type': 0});
      expect(t.replies, isEmpty);
      expect(t.count, 1);
    });
  });

  group('长度校验（按码点）', () {
    test('弹幕上限 50', () {
      expect(validateDanmaku('a' * 50), isNull);
      expect(validateDanmaku('a' * 51), isNotNull);
      expect(validateDanmaku('   '), isNotNull);
      expect(validateDanmaku(' ' * 10 + 'x' * 50), isNull, reason: 'trim 后再计数');
    });

    test('评论上限 500', () {
      expect(validateComment('字' * 500), isNull);
      expect(validateComment('字' * 501), isNotNull);
      expect(validateComment(''), isNotNull);
    });

    test('emoji 按一个字算，与后端 RuneCount 对齐', () {
      // Dart 的 String.length 会算成 2（UTF-16 代理对），这里必须是 1
      expect('👍'.length, 2);
      expect(validateDanmaku('👍' * 50), isNull);
      expect(validateDanmaku('👍' * 51), isNotNull);
    });
  });

  group('SSE 帧解析', () {
    test('解析 event + data 两行', () {
      final e = parseDanmakuFrame(
        'event: danmaku\n'
        'data: {"id":"1","user_name":"cm","type":1,"offset":5000,"content":"hi"}',
      );
      expect(e, isNotNull);
      expect(e!.id, '1');
      expect(e.isDanmaku, isTrue);
      expect(e.offsetMs, 5000);
      expect(e.content, 'hi');
    });

    test('心跳等无 data 的帧返回 null', () {
      expect(parseDanmakuFrame(': ping'), isNull);
      expect(parseDanmakuFrame('event: danmaku'), isNull);
    });

    test('data 里的多字节内容不会被截断', () {
      final e = parseDanmakuFrame('data: {"content":"中文弹幕","type":1}');
      expect(e?.content, '中文弹幕');
    });

    test('data 不是 JSON 对象时返回 null', () {
      expect(parseDanmakuFrame('data: [1,2,3]'), isNull);
    });
  });

  group('头像', () {
    test('同一个 key 始终同色，且取色在盘内', () {
      expect(avatarColor('01'), avatarColor('01'));
      for (final key in ['01', '07', '12', 'unknown']) {
        expect(avatarPalette, contains(avatarColor(key)));
      }
    });

    test('取昵称首个字符，空名回退', () {
      expect(avatarLabel('cm'), 'C');
      expect(avatarLabel('中文名'), '中');
      expect(avatarLabel('  '), '?');
    });
  });
}
