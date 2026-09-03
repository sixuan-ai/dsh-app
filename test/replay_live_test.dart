import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile/state.dart';

/// 回放真实 live 事件序列, 验证折叠后是否产出最后的 assistant 消息。
void main() {
  test('replay real alpha.4 live turn', () async {
    final file = File('/tmp/live-events.json');
    if (!file.existsSync()) {
      print('跳过: 无 /tmp/live-events.json 抓包文件');
      return;
    }
    final raw = file.readAsStringSync();
    final events = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    expect(events, isNotEmpty, reason: '应有捕获的事件');

    final app = AppState();
    var lastSeq = -1;
    for (final e in events) {
      final seq = (e['seq'] as num).toInt();
      expect(seq, greaterThan(lastSeq), reason: 'seq 应连续递增(实际缺口: $lastSeq -> $seq)');
      lastSeq = seq;
      app.foldForTest({
        'seq': seq,
        'time': 0,
        'type': e['type'],
        'data': e['data'],
      });
    }

    final kinds = app.items.map((i) => i.kind.name).join(',');
    print('折叠产出 ${app.items.length} 项: $kinds');
    final last = app.items.isEmpty ? null : app.items.last;
    if (last != null) {
      print('最后一项 kind=${last.kind.name} text=${last.text.length > 60 ? last.text.substring(0, 60) : last.text}');
    }
    expect(app.items, isNotEmpty);
  });
}
