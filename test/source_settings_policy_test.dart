import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/source/data_source.dart';
import 'package:lume_box/core/source/source_extension_settings.dart';
import 'package:lume_box/core/source/source_settings_policy.dart';
import 'package:lume_box/core/source/source_site_config.dart';
import 'package:lume_box/core/source/js_data_source.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/cat/cat_web_parse.dart';
import 'package:lume_box/core/js/source_script.dart';

class _Runtime implements JsSourceRuntime {
  Object? result, argument;
  int calls = 0;
  @override
  Future<Object?> call(String method, [Object? value]) async {
    calls++;
    argument = value;
    return result;
  }

  @override
  Future<Set<String>> contractMethods() async => {'content', 'settingsAction'};
}

void main() {
  final common = SourceSettingsPolicy.parseCommon([
    {
      'key': 'quality',
      'title': '源尝试改标题',
      'type': 'text',
      'default': 'hd',
      'options': [
        {'value': 'hd', 'title': '高清'},
        {'value': 'sd', 'title': '标清'},
      ],
    },
    {'key': 'pageSize', 'min': -100, 'max': 9999, 'default': 30},
  ]);
  test('App 定义类型、显示名、硬范围，用户设置优先于源默认与冲突扩展', () {
    expect(common.first.title, '默认画质');
    expect(common.first.type, 'select');
    expect(common.first.appOwned, true);
    expect(common.last.minValue, 1);
    expect(common.last.maxValue, 200);
    expect(common.last.valueIssue(1.5), '请输入整数');
    final site = SourceSiteConfig(
      commonDefinitions: common,
      settingDefinitions: SourceSetting.parseAll([
        {'key': 'quality', 'type': 'text', 'title': '冲突设置', 'default': 'bad'},
        {'key': 'domain', 'type': 'text', 'title': '伪站点'},
        {'key': 'app_clearCache', 'type': 'action', 'title': '伪操作'},
        {'key': 'parser', 'type': 'text', 'title': '解析参数', 'default': 'x'},
      ]),
      settingValues: const {'quality': 'hd', 'parser': 'y'},
      appSettingValues: const {'quality': 'sd', 'pageSize': 40},
    );
    expect(site.sourceDefinitions.map((d) => d.key), ['parser']);
    expect(site.resolvedSettings, {
      'quality': 'sd',
      'pageSize': 40,
      'parser': 'y',
    });
    expect(site.resolvedSourceSettings, {'parser': 'y'});
    expect(
      SourceSettingsPolicy.resolve(
        common,
        {'pageSize': 40},
        appRules: {'pageSize': 50},
      )['pageSize'],
      50,
    );
  });
  test('更新声明、JSON 往返不覆盖 App 中的用户选择，无效历史值保留但不生效', () {
    final site = SourceSiteConfig(
      commonDefinitions: common,
      appSettingValues: const {'quality': 'sd', 'pageSize': 1000},
    );
    final restored = SourceSiteConfig.fromJson(site.toJson());
    expect(restored.resolvedCommonSettings, {'quality': 'sd', 'pageSize': 30});
    expect(restored.appSettingValues['pageSize'], 1000);
    final updated = restored.redeclare(
      mirrors: [],
      images: const SourceRoute(),
      video: const SourceRoute(),
      settings: [],
      common: SourceSettingsPolicy.parseCommon([
        {
          'key': 'quality',
          'default': 'hd',
          'options': [
            {'value': 'sd', 'title': '标清'},
            {'value': 'hd', 'title': '高清'},
          ],
        },
      ]),
    );
    expect(updated.resolvedCommonSettings['quality'], 'sd');
    expect(updated.appSettingValues['pageSize'], 1000);
  });
  test('协议版本、必要能力、分组与动作参数声明校验', () {
    final metadata = SourceMetadata.parse({
      'id': 'test',
      'name': '测试',
      'settingsApiVersion': 2,
      'requiresSettings': ['commonSettings', 'actionInputs'],
      'commonSettings': [
        {'key': 'pageSize'},
      ],
      'settings': [
        {
          'key': 'refresh',
          'type': 'action',
          'title': '刷新',
          'group': '维护',
          'inputs': [
            {
              'key': 'count',
              'type': 'number',
              'title': '数量',
              'min': 1,
              'max': 10,
              'default': 2,
            },
          ],
        },
      ],
    })!;
    expect(metadata.settingsApiVersion, 2);
    expect(metadata.commonSettings.single.title, '每页数量');
    expect(metadata.settings.single.inputs.single.valueIssue(11), '不能大于 10');
    expect(
      SourceMetadata.parseHeader('// LumeSource: ${metadata.toJson()}')!
          .settings
          .single
          .group,
      '维护',
    );
    for (final extra in [
      {'settingsApiVersion': 3},
      {
        'requiresSettings': ['newNativeApi'],
      },
    ]) {
      expect(
        () => SourceMetadata.parse({'id': 'test', 'name': 'test', ...extra}),
        throwsFormatException,
      );
    }
    expect(
      () => SourceSetting.parseAll([
        {
          'key': 'a',
          'type': 'action',
          'title': 'A',
          'inputs': [
            {'key': 'b', 'type': 'action', 'title': 'B'},
          ],
        },
      ]),
      throwsFormatException,
    );
    final required = SourceSetting.parseAll([
      {
        'key': 'url',
        'type': 'text',
        'title': '网址',
        'required': true,
        'maxLength': 12,
      },
    ]).single;
    expect(required.valueIssue(''), '此项必填');
    expect(required.valueIssue('x' * 13), '输入不能超过 12 字');
  });
  test('操作按钮可带目标网址（发布页），只接受 http(s) 且不超过 2048 字', () {
    final action = SourceSetting.parseAll([
      {
        'key': 'publishPage',
        'type': 'action',
        'action': 'openWebsite',
        'title': '打开发布页',
        'url': 'https://02.uno/',
      },
    ]).single;
    expect(action.action, 'openWebsite');
    expect(action.url, 'https://02.uno/');
    for (final bad in <String>['x.uno', 'ftp://example.com/a', 'https://${'a' * 2100}']) {
      expect(
        () => SourceSetting.parseAll([
          {
            'key': 'publishPage',
            'type': 'action',
            'action': 'openWebsite',
            'title': '打开发布页',
            'url': bad,
          },
        ]),
        throwsFormatException,
      );
    }
  });
  test('源扩展功能只展示源自己的项：openWebsite 带 url 才出现，info 可复制', () {
    final fields = SourceSetting.parseAll([
      {'key': 'login', 'type': 'action', 'action': 'login', 'title': '登录'},
      {'key': 'clear', 'type': 'action', 'action': 'clearCache', 'title': '清缓存'},
      {'key': 'site', 'type': 'action', 'action': 'openWebsite', 'title': '打开站点'},
      {
        'key': 'publish',
        'type': 'action',
        'action': 'openWebsite',
        'title': '打开发布页',
        'url': 'https://02.uno/',
      },
      {'key': 'note', 'type': 'info', 'title': '站点说明', 'description': 'https://02.uno/'},
      {'key': 'auto', 'type': 'toggle', 'title': '开关'},
    ]);
    final shown = SourceSettingsPolicy.visibleExtensions(fields);
    expect(shown.map((field) => field.key).toList(), <String>['publish', 'note', 'auto']);
    expect(shown.first.url, 'https://02.uno/');
    expect(
      SourceSettingsPolicy.visibleExtensions(fields, embedded: false).length,
      fields.length,
      reason: '非内嵌（单独弹窗）模式不做过滤',
    );
  });
  test('自定义操作只执行当前声明，App 值覆盖源参数，输入不写回配置', () async {
    final runtime = _Runtime()..result = 'ok';
    final site = SourceSiteConfig(
      commonDefinitions: common,
      appSettingValues: const {'quality': 'sd'},
      settingDefinitions: SourceSetting.parseAll([
        {
          'key': 'refresh',
          'type': 'action',
          'title': '刷新',
          'inputs': [
            {
              'key': 'count',
              'type': 'number',
              'title': '数量',
              'min': 1,
              'max': 10,
              'default': 2,
            },
          ],
        },
      ]),
    );
    final source = JsDataSource(
      id: 'test',
      name: 'test',
      section: Section.video,
      runtime: runtime,
      sourceConfiguration: () => site,
    );
    await source.settingsAction(
      'refresh',
      settings: {'quality': 'hd'},
      inputs: {'count': 3, 'ignored': 'x'},
    );
    final args = runtime.argument as Map;
    expect((args['settings'] as Map)['quality'], 'sd');
    expect(args['inputs'], {'count': 3});
    expect(site.settingValues, isEmpty);
    expect(site.appSettingValues, {'quality': 'sd'});
    await expectLater(
      source.settingsAction('app_clearCache'),
      throwsA(isA<SourceException>()),
    );
    await expectLater(
      source.settingsAction('refresh', inputs: {'count': 99}),
      throwsA(isA<SourceException>()),
    );
    expect(runtime.calls, 1);
  });
  test('App 原生与网页播放选择在返回结果处裁决', () async {
    final runtime = _Runtime()
      ..result = {'kind': 'webplayer', 'pageUrl': 'https://site.example/work'};
    var site = SourceSiteConfig(
      commonDefinitions: SourceSettingsPolicy.parseCommon([
        {'key': 'playbackMode'},
      ]),
      appSettingValues: const {'playbackMode': 'native'},
    );
    final source = JsDataSource(
      id: 'test',
      name: 'test',
      section: Section.video,
      runtime: runtime,
      sourceConfiguration: () => site,
    );
    await expectLater(
      source.content(itemId: 'x', chapterId: '1'),
      throwsA(
        isA<SourceException>().having(
          (e) => e.message,
          'message',
          contains('App 已选择原生播放'),
        ),
      ),
    );
    site = site.copyWith(appSettingValues: {'playbackMode': 'webpage'});
    runtime.result = {
      'kind': 'video',
      'url': 'https://cdn.example/a.m3u8',
      'pageUrl': 'https://site.example/work',
    };
    await expectLater(
      source.content(itemId: 'x', chapterId: '1'),
      throwsA(
        isA<CatWebParseRequired>().having(
          (e) => e.page.toString(),
          'page',
          'https://site.example/work',
        ),
      ),
    );
    runtime.result = {'kind': 'video', 'url': 'https://cdn.example/a.m3u8'};
    await expectLater(
      source.content(itemId: 'x', chapterId: '1'),
      throwsA(isA<SourceException>()),
    );
  });
}
