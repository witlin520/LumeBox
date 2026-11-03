import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/features/video/danmaku/dandanplay_client.dart';
import 'package:lume_box/features/video/danmaku/danmaku_connection_test.dart';

void main() {
  testWidgets('连接按钮用当前输入验证签名，显示拒绝原因与成功状态', (tester) async {
    var reject = true;
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DanmakuConnectionTest(
                credentials: () => const DandanplayCredentials(
                  'sample',
                  'secret',
                  baseUrl: DandanplayCredentials.officialBase,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('测试连接'));
        await tester.pumpAndSettle();
        expect(find.textContaining('AppSecret 无效'), findsOneWidget);
        reject = false;
        await tester.tap(find.text('测试连接'));
        await tester.pumpAndSettle();
        expect(find.textContaining('连接成功，应用凭证已通过验证'), findsOneWidget);
        expect(find.textContaining('AppSecret 无效'), findsNothing);
        expect(requests, 2);
      },
      () => MockClient((request) async {
        requests++;
        expect(request.url.host, 'api.dandanplay.net');
        expect(request.headers['X-AppId'], 'sample');
        expect(request.headers['X-Signature'], isNotEmpty);
        return reject
            ? http.Response(
                '',
                403,
                headers: {'x-error-message': 'Invalid Signature'},
              )
            : http.Response('{"success":true,"animes":[]}', 200);
      }),
    );
  });
}
