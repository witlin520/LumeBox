import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/privacy_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/features/settings/privacy_settings_page.dart';
import 'package:lume_box/shared/widgets/app_privacy_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PrivacySettings settings;
  var accepted = true;
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('lumebox-privacy');
    settings = PrivacySettings.instance;
    accepted = true;
    calls.clear();
    messenger.setMockMethodCallHandler(PrivacySettings.channel, (call) async {
      calls.add(call);
      return call.method == 'authenticate' ? accepted : null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    await settings.boot(directory: root);
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    root.deleteSync(recursive: true);
    messenger.setMockMethodCallHandler(PrivacySettings.channel, null);
  });

  test(
    'concurrent privacy writes merge preferences without temporary-file races',
    () async {
      await settings.setMethod(AppUnlockMethod.face);
      await Future.wait([
        settings.setAppLock(true),
        settings.setShowAdult(false),
        settings.setShowAdult(true),
      ]);
      final restored = PrivacySettings();
      await restored.boot(directory: root);
      expect(restored.appLock, true);
      expect(restored.method, AppUnlockMethod.face);
      expect(restored.showAdult, true);
      restored.dispose();
    },
  );

  test('new defaults, persisted options and failed authorization', () async {
    expect(settings.appLock, false);
    expect(settings.showAdult, false);
    accepted = false;
    expect(await settings.setAppLock(true), false);
    expect(settings.appLock, false);
    accepted = true;
    expect(await settings.setMethod(AppUnlockMethod.face), true);
    expect(await settings.setAppLock(true), true);
    await settings.setShowAdult(true);
    final restored = PrivacySettings();
    await restored.boot(directory: root);
    expect(restored.appLock, true);
    expect(restored.method, AppUnlockMethod.face);
    expect(restored.showAdult, true);
    restored.dispose();
    // Disabling still requires the real system passcode even if Face ID is unavailable.
    expect(await settings.setAppLock(false), true);
    expect(
      (calls.where((c) => c.method == 'authenticate').last.arguments
          as Map)['method'],
      'passcode',
    );
  });

  test('corrupt saved configuration fails closed and unavailable auth does not enable', () async {
    File('${root.path}/${PrivacySettings.fileName}')
        .writeAsStringSync('{"appLock":"false"}');
    await settings.boot(directory: root);
    expect(settings.appLock, true);
    expect(settings.showAdult, false);
    messenger.setMockMethodCallHandler(
      PrivacySettings.channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    await expectLater(
      settings.setAppLock(false),
      throwsA(isA<PlatformException>()),
    );
    expect(settings.appLock, true);
  });

  test(
    'adult filtering is reversible and preserves stored library items',
    () async {
      final library = await ReadingLibrary.open(Section.comic);
      library.shelve(
        sourceId: 'jm18_comic',
        itemId: 'adult-book',
        title: '测试漫画',
      );
      library.shelve(
        sourceId: 'ordinary',
        itemId: 'ordinary-book',
        title: '普通漫画',
      );
      expect(library.shelf().map((i) => i.itemId), ['ordinary-book']);
      expect(library.item('adult-book'), isNotNull);
      expect(settings.allowsSource('site:jm18_comic'), false);
      expect(settings.allowsSource('unclassified', '18+ 测试'), false);
      expect(settings.allowsSource('unclassified', '普通站点'), true);
      await settings.setShowAdult(true);
      expect(library.shelf(), hasLength(2));
      await settings.setShowAdult(false);
      expect(library.shelf(), hasLength(1));
      expect(library.item('adult-book'), isNotNull);
    },
  );

  testWidgets('privacy switches persist only after successful authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PrivacySettingsPage(settings: settings)),
    );
    accepted = false;
    await tester.tap(find.widgetWithText(SwitchListTile, '应用锁'));
    await tester.pumpAndSettle();
    expect(settings.appLock, false);
    expect(find.text('验证未完成，设置未更改'), findsOneWidget);
    accepted = true;
    await tester.tap(find.widgetWithText(SwitchListTile, '应用锁'));
    for (var i = 0; i < 30 && !settings.appLock; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    await tester.pumpAndSettle();
    expect(settings.appLock, true);
    await tester.tap(find.widgetWithText(SwitchListTile, '显示成人内容'));
    for (var i = 0; i < 30 && !settings.showAdult; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    await tester.pumpAndSettle();
    expect(settings.showAdult, true);
    // Drain the chained persistence future before leaving this widget test's fake clock.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets(
    'cold start and lifecycle conceal all content and reject cancelled unlock',
    (tester) async {
      await tester.runAsync(() => settings.setAppLock(true));
      accepted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AppPrivacyGuard(
            settings: settings,
            child: const Text('private reader'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('private reader'), findsNothing);
      expect(find.text('LumeBox 已锁定'), findsOneWidget);
      accepted = true;
      await tester.tap(find.text('使用锁屏密码解锁'));
      await tester.pumpAndSettle();
      expect(find.text('private reader'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('private reader'), findsNothing);
      accepted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('private reader'), findsNothing);
    },
  );

  testWidgets(
    'backgrounding during authentication cannot unlock on stale success',
    (tester) async {
      await tester.runAsync(() => settings.setAppLock(true));
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(
        PrivacySettings.channel,
        (call) async => call.method == 'authenticate' ? pending.future : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppPrivacyGuard(
            settings: settings,
            child: const Text('private detail'),
          ),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      pending.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('private detail'), findsNothing);
      expect(find.text('LumeBox 已锁定'), findsOneWidget);
      // Dispose before returning to resumed so it cannot start another test's job.
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
