import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/media/media_library.dart';
import 'package:lume_box/core/media/media_resource_service.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_media_hints.dart';

import 'support/fake_reading_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('有声板块声明直接提供音频类型，显式媒体类型仍优先', () {
    expect(
      SourceMediaHints.fromScript('// LumeSource: {"category":"audiobook"}'),
      'audio',
    );
    expect(
      SourceMediaHints.fromScript(
        '// LumeSource: {"category":"audiobook","mediaType":"video"}',
      ),
      'video',
    );
  });
  late Directory root;
  late MediaLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lume-media-test-');
    library = MediaLibrary();
    await library.boot(directory: root);
  });
  tearDown(() async {
    library.dispose();
    await root.delete(recursive: true);
  });
  test(
    'real audio-only tracks override video origin and misleading filename',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('lumebox/mediaTracks'),
            (_) async => {'known': true, 'audio': true, 'video': false},
          );
      final entry = await MediaResourceService(library: library).source(
        source: FakeReadingDataSource(section: Section.video),
        item: const SourceItem(id: 'audio', title: '有声书'),
        chapters: const [SourceChapter(id: '1', title: '第1集')],
        firstContent: VideoContent(
          url: Uri.parse('https://audio.example/misleading.mp4'),
        ),
      );
      expect(entry.kind, ResourceKind.audioBook);
      expect(entry.destination, Section.video);
      expect(entry.originSection, Section.video);
      expect(entry.manual, false);
    },
  );
  test('video track wins even when file is named mp3', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('lumebox/mediaTracks'),
          (_) async => {'known': true, 'audio': true, 'video': true},
        );
    final entry = await MediaResourceService(library: library).source(
      source: FakeReadingDataSource(section: Section.video),
      item: const SourceItem(id: 'video', title: '视频'),
      chapters: const [SourceChapter(id: '1', title: '第1集')],
      firstContent: VideoContent(
        url: Uri.parse('https://video.example/misleading.mp3'),
        audioOnly: true,
      ),
    );
    expect(entry.kind, ResourceKind.video);
    expect(entry.destination, Section.video);
  });

  test('audio payload kinds retain audio classification hint', () {
    final content = ChapterContent.parse({
      'kind': 'audio',
      'url': 'https://example.com/audio',
    });
    expect(content, isA<VideoContent>());
    expect((content as VideoContent).audioOnly, true);
    expect(
      const MediaTrackInfo(known: true, audio: true).kind,
      ResourceKind.audioBook,
    );
    expect(const MediaTrackInfo().kind, null);
  });

  test('旧小说库中的成品音频仍保留，文本小说不会恢复', () {
    final entry = MediaResource.fromJson({
      'id': 'old-audio',
      'title': '音频',
      'kind': 'audioBook',
      'destination': 'novel',
      'episodes': [
        {'id': 'one', 'title': '第一集', 'url': 'file:///audio/one.mp3'},
      ],
    });
    expect(entry.destination, Section.video);
    expect(entry.episodes.single.url.toString(), 'file:///audio/one.mp3');
    expect(
      () => MediaResource.fromJson({
        'id': 'old-text',
        'title': '正文',
        'kind': 'textNovel',
        'destination': 'novel',
        'episodes': [],
      }),
      throwsArgumentError,
    );
  });

  test('音频播放队列保留延迟解析地址与请求头', () async {
    final entry = MediaResource(
      id: 'playlist',
      title: '音频合集',
      kind: ResourceKind.audioBook,
      destination: Section.video,
      episodes: [
        ResourceEpisode(
          id: 'one',
          title: '第一集',
          url: Uri.parse('https://example.test/audio.mp3'),
          headers: const {'Referer': 'https://example.test/'},
        ),
      ],
    );
    final tracks = MediaResourceService(library: library).audioTracks(entry);
    expect(tracks.single.album, entry.title);
    final resolved = await tracks.single.resolve!();
    expect(resolved.url, entry.episodes.single.url);
    expect(resolved.headers, entry.episodes.single.headers);
  });
}
