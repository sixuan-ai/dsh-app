import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';

/// 真实全栈集成测试: 通过认证代理连 alpha.4 服务器, 用 App 真实协议栈
/// 驱动一次完整对话, 验证新消息能实时折叠出来。
/// 需要环境变量 DSH_TEST_USER / DSH_TEST_PASS (代理 Basic 凭据)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = Platform.environment['DSH_TEST_USER'];
  final pass = Platform.environment['DSH_TEST_PASS'];
  if (user == null || pass == null) {
    print('跳过: 未设置 DSH_TEST_USER/DSH_TEST_PASS');
    return;
  }

  test('real pipeline: create session, prompt, live-fold the reply', () async {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null; // flutter_test 默认拦网络, 恢复真实 HTTP
    final api = DshApi('http://127.0.0.1:3081', username: user, password: pass);
    await api.hostReady();
    final app = AppState();
    app.attachApiForTest(api);

    // 建会话并打开
    final created =
        await api.call('session.create', {'cwd': '/tmp'})
            as Map<String, dynamic>;
    final sessionId = created['sessionId'] as String;
    print('测试会话: $sessionId');
    await app.openSession(sessionId);
    await Future<void>.delayed(const Duration(seconds: 2));

    // 发送 prompt, 让 agent 输出一段长文本(多轮 chunk)
    final rpcId = 'it-${DateTime.now().millisecondsSinceEpoch}';
    await api.call('session.prompt', {
      'sessionId': sessionId,
      'mode': 'queue',
      'content': [
        {
          'type': 'text',
          'text': '请输出一段约 300 字的介绍文字(关于深圳),不要调用任何工具,直接写正文。',
        },
      ],
      'requestId': rpcId,
    });

    // 轮询等待 turn/end 后内容出现(最长 60s)
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    var sawAssistant = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final kinds = app.items.map((i) => i.kind.name).join(',');
      final has = app.items.where((i) => i.kind.name == 'assistant').toList();
      if (has.isNotEmpty) {
        final last = has.last;
        final texts = last.blocks
            .where((b) => b.type == 'text')
            .map((b) => b.text)
            .join();
        print(
          '已见 assistant: blocks=${last.blocks.length} textLen=${texts.length}',
        );
        if (texts.length > 100) {
          sawAssistant = true;
          break;
        }
      }
      print('等待中… items=${app.items.length} [$kinds]');
    }
    expect(sawAssistant, isTrue,
        reason: '60s 内应折叠出完整的 assistant 文本消息');
    app.disconnect();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
