import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/api_client.dart';
import 'package:mocca/core/format.dart';
import 'package:mocca/core/models.dart';

void main() {
  group('登录静态哈希', () {
    // 黄金值：在与真实 Mocca 后端联调时确认过，密码为 Passw0rd。
    // 若此断言失败，说明公式或盐值被改动了，会直接导致线上登录失败。
    test('与后端 model.StaticHash 的公式一致', () {
      expect(
        ApiClient.staticHash('Passw0rd'),
        '671869e93ed4fdf78e3e1b26eb8225911208b0bca5822dcbcc1a78448d8891d0',
      );
    });

    test('不同密码得到不同哈希', () {
      expect(
        ApiClient.staticHash('a'),
        isNot(equals(ApiClient.staticHash('b'))),
      );
    });
  });

  group('服务器地址规范化', () {
    test('缺少协议时补 http', () {
      expect(
        ApiClient.normalizeBaseUrl('192.168.1.10:5244'),
        'http://192.168.1.10:5244',
      );
    });

    test('去掉尾部斜杠但保留子路径', () {
      expect(
        ApiClient.normalizeBaseUrl('http://host:5244/nas/'),
        'http://host:5244/nas',
      );
    });

    test('保留 https', () {
      expect(
        ApiClient.normalizeBaseUrl('https://media.example.com'),
        'https://media.example.com',
      );
    });

    test('空串与非法输入返回空', () {
      expect(ApiClient.normalizeBaseUrl(''), '');
      expect(ApiClient.normalizeBaseUrl('   '), '');
    });

    test('去掉查询串与锚点', () {
      expect(
        ApiClient.normalizeBaseUrl('http://host:5244/nas?a=1#b'),
        'http://host:5244/nas',
      );
    });
  });

  group('播放地址解析', () {
    test('绝对地址原样返回', () {
      final api = ApiClient(baseUrl: 'http://host:5244');
      expect(
        api.resolveUrl('https://cdn.example.com/a.mp4'),
        'https://cdn.example.com/a.mp4',
      );
    });

    test('根路径部署：绝对路径补全为 origin', () {
      final api = ApiClient(baseUrl: 'http://host:5244');
      expect(
        api.resolveUrl('/d/movies/a.mp4?sign=abc'),
        'http://host:5244/d/movies/a.mp4?sign=abc',
      );
    });

    test('子路径部署：后端已带前缀，不应重复拼接', () {
      final api = ApiClient(baseUrl: 'http://host:5244/nas');
      expect(api.resolveUrl('/nas/d/a.mp4'), 'http://host:5244/nas/d/a.mp4');
    });

    test('相对路径按 base 解析', () {
      final api = ApiClient(baseUrl: 'http://host:5244/nas');
      expect(api.resolveUrl('d/a.mp4'), 'http://host:5244/nas/d/a.mp4');
    });

    test('空串返回空', () {
      final api = ApiClient(baseUrl: 'http://host:5244');
      expect(api.resolveUrl(''), '');
    });
  });

  group('后端 header 字段解析', () {
    test('解析多行 Key: Value', () {
      const detail = MediaDetail(
        obj: MediaObj(name: 'a', size: 0, isDir: false, type: 2),
        rawUrl: '/d/a',
        header: 'Referer: https://example.com\nUser-Agent: mocca',
      );
      expect(detail.parsedHeaders(), {
        'Referer': 'https://example.com',
        'User-Agent': 'mocca',
      });
    });

    test('忽略空值与非法行', () {
      const detail = MediaDetail(
        obj: MediaObj(name: 'a', size: 0, isDir: false, type: 2),
        rawUrl: '/d/a',
        header: '无冒号的行\n : 空 key\nK: v',
      );
      expect(detail.parsedHeaders(), {'K': 'v'});
    });

    test('空 header 返回空映射', () {
      const detail = MediaDetail(
        obj: MediaObj(name: 'a', size: 0, isDir: false, type: 2),
        rawUrl: '/d/a',
      );
      expect(detail.parsedHeaders(), isEmpty);
    });
  });

  group('格式化', () {
    test('时长', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(-5), '0:00');
      expect(formatDuration(1000), '0:01');
      expect(formatDuration(65000), '1:05');
      expect(formatDuration(3665000), '1:01:05');
    });

    test('体积', () {
      expect(formatSize(0), '0 B');
      expect(formatSize(512), '512 B');
      expect(formatSize(1024), '1.0 KB');
      expect(formatSize(1536), '1.5 KB');
      expect(formatSize(734003200), '700 MB');
    });

    test('按扩展名兜底判断类型', () {
      expect(guessKindFromName('a.MP4'), MediaKind.video);
      expect(guessKindFromName('a.mp3'), MediaKind.audio);
      expect(guessKindFromName('a.jpg'), MediaKind.image);
      expect(guessKindFromName('a.png'), MediaKind.image);
      expect(guessKindFromName('a.txt'), MediaKind.unknown);
      expect(guessKindFromName('noext'), MediaKind.unknown);
    });
  });

  group('播放记录', () {
    test('进度与「已看完」判定', () {
      final r = PlayRecord(
        path: '/a.mp4',
        name: 'a.mp4',
        kind: MediaKind.video,
        positionMs: 50000,
        durationMs: 100000,
      );
      expect(r.progress, closeTo(0.5, 0.001));
      expect(r.isFinished, isFalse);

      r.positionMs = 99000;
      expect(r.isFinished, isTrue);
    });

    test('接近片头时从头播放，避免立刻跳到片尾', () {
      final r = PlayRecord(
        path: '/a.mp4',
        name: 'a.mp4',
        kind: MediaKind.video,
        positionMs: 3000,
        durationMs: 100000,
      );
      expect(r.resumeMs, 0);

      r.positionMs = 30000;
      expect(r.resumeMs, 30000);
    });

    test('时长未知时进度为 0 且不算看完', () {
      final r = PlayRecord(
        path: '/a.mp3',
        name: 'a.mp3',
        kind: MediaKind.audio,
      );
      expect(r.progress, 0);
      expect(r.isFinished, isFalse);
    });

    test('JSON 往返保持字段', () {
      final r = PlayRecord(
        path: '/movies/a.mp4',
        name: 'a.mp4',
        kind: MediaKind.video,
        positionMs: 12345,
        durationMs: 600000,
        watchedMs: 98765,
        thumb: 'http://host/t.jpg',
      );
      final back = PlayRecord.fromJson(r.toJson());
      expect(back.path, r.path);
      expect(back.name, r.name);
      expect(back.kind, r.kind);
      expect(back.positionMs, r.positionMs);
      expect(back.durationMs, r.durationMs);
      expect(back.watchedMs, r.watchedMs);
      expect(back.thumb, r.thumb);
    });
  });

  group('收藏条目', () {
    test('JSON 往返', () {
      final item = SavedItem(
        path: '/a.mp3',
        name: 'a.mp3',
        kind: MediaKind.audio,
        thumb: 't',
      );
      final back = SavedItem.fromJson(item.toJson());
      expect(back.path, item.path);
      expect(back.name, item.name);
      expect(back.kind, item.kind);
      expect(back.thumb, item.thumb);
    });
  });

  group('Session', () {
    test('角色判定', () {
      const user = Session(username: 'alice', role: 0, basePath: '/alice');
      expect(user.isGuest, isFalse);
      expect(user.isAdmin, isFalse);
      expect(user.roleLabel, '用户');
      expect(user.basePath, '/alice');

      const guest = Session(username: 'guest', role: 1);
      expect(guest.isGuest, isTrue);

      const admin = Session(username: 'admin', role: 2);
      expect(admin.isAdmin, isTrue);
    });
  });
}
