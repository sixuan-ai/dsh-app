import 'package:dsh_mobile/connection_center.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const paired = PairedComputer(
  nodeId: 'x26-ui',
  name: 'x-26',
  localUrl: 'https://192.168.1.20:3082',
  remoteUrl: 'https://gateway.example/x26',
  fingerprint: 'fixture',
  username: 'fixture',
  password: 'fixture',
);
Widget app(Widget child) =>
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child);
void main() {
  testWidgets(
    'pending computer selection does not advertise the previous connection',
    (tester) async {
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'pending',
            connected: false,
            reconnecting: true,
            checkingLocal: false,
            localAvailable: true,
            pairedName: 'x-26',
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      );
      expect(find.text('连接中'), findsOneWidget);
      expect(find.text('正在选择连接路径'), findsOneWidget);
      expect(find.text('已连接'), findsNothing);
    },
  );

  testWidgets(
    'current x-26 and original OMEN remain visible and OMEN can be selected',
    (tester) async {
      AccountComputer? selected;
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'lan',
            checkingLocal: false,
            localAvailable: true,
            pairedName: paired.name,
            pairedComputers: const [paired],
            activePairedNodeId: paired.nodeId,
            pairedRemoteUrl: paired.remoteUrl,
            computers: [
              AccountComputer(
                id: 'omen',
                name: 'OMEN 笔记本',
                subdomain: 'dsh.example.com',
                isDefault: true,
              ),
            ],
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
            onSwitchComputer: (p) => selected = p,
          ),
        ),
      );
      expect(find.text('x-26'), findsOneWidget);
      expect(find.text('OMEN 笔记本'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      await tester.ensureVisible(find.text('切换'));
      await tester.tap(find.text('切换'));
      expect(selected?.id, 'omen');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('paired computer switch dispatches its own saved entry', (
    tester,
  ) async {
    PairedComputer? selected;
    await tester.pumpWidget(
      app(
        ConnectionCenterSheet(
          connectionMode: 'public',
          checkingLocal: false,
          localAvailable: false,
          pairedComputers: const [paired],
          onSwitchRemote: () {},
          onSwitchLocal: () {},
          onRefreshLocal: () {},
          onSwitchPairedComputer: (p) => selected = p,
        ),
      ),
    );
    await tester.ensureVisible(find.text('切换'));
    await tester.tap(find.text('切换'));
    expect(identical(selected, paired), isTrue);
  });
  testWidgets('route controls dispatch configured LAN and public callbacks', (
    tester,
  ) async {
    var lan = 0, public = 0;
    await tester.pumpWidget(
      app(
        ConnectionCenterSheet(
          connectionMode: 'public',
          checkingLocal: false,
          localAvailable: true,
          onSwitchRemote: () => public++,
          onSwitchLocal: () => lan++,
          onRefreshLocal: () {},
        ),
      ),
    );
    await tester.ensureVisible(find.text('局域网'));
    await tester.tap(find.text('局域网'));
    expect(lan, 1);
    expect(public, 0);
    await tester.pumpWidget(
      app(
        ConnectionCenterSheet(
          connectionMode: 'lan',
          checkingLocal: false,
          localAvailable: true,
          pairedName: paired.name,
          pairedRemoteUrl: paired.remoteUrl,
          onSwitchRemote: () => public++,
          onSwitchLocal: () => lan++,
          onRefreshLocal: () {},
        ),
      ),
    );
    await tester.ensureVisible(find.text('公网'));
    await tester.tap(find.text('公网'));
    expect(public, 1);
  });
  testWidgets(
    'unconfigured public route cannot connect or claim availability',
    (tester) async {
      var public = 0;
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'lan',
            checkingLocal: false,
            localAvailable: true,
            pairedName: paired.name,
            onSwitchRemote: () => public++,
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      );
      await tester.ensureVisible(find.text('公网'));
      await tester.tap(find.text('公网'));
      expect(public, 0);
      expect(find.text('此电脑尚未配置公网，可先在同一网络使用'), findsOneWidget);
    },
  );
  testWidgets('offline selection is not advertised as connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ConnectionCenterSheet(
          connectionMode: 'public',
          checkingLocal: false,
          localAvailable: false,
          connected: false,
          onSwitchRemote: () {},
          onSwitchLocal: () {},
          onRefreshLocal: () {},
        ),
      ),
    );
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('已连接'), findsNothing);
    expect(find.text('显示已缓存内容，等待连接恢复'), findsOneWidget);
  });
  testWidgets(
    'advanced settings retain manual address, discovery, refresh and direct actions',
    (tester) async {
      var address = 0, search = 0, refresh = 0, direct = 0;
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'public',
            checkingLocal: false,
            localAvailable: false,
            localUrl: 'http://192.168.1.10:3081',
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () => refresh++,
            onSetLocalAddress: () => address++,
            onAutoSearchLocal: () => search++,
            onSwitchDirect: () => direct++,
          ),
        ),
      );
      await tester.ensureVisible(find.text('连接设置'));
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      expect(find.text('http://192.168.1.10:3081'), findsOneWidget);
      await tester.ensureVisible(find.text(S.setLocalAddress));
      await tester.tap(find.text(S.setLocalAddress));
      expect(address, 1);
      await tester.ensureVisible(find.text(S.autoSearchLocal));
      await tester.tap(find.text(S.autoSearchLocal));
      expect(search, 1);
      await tester.ensureVisible(find.text(S.retestLocal));
      await tester.tap(find.text(S.retestLocal));
      expect(refresh, 1);
      await tester.ensureVisible(find.text('使用备用直连'));
      await tester.tap(find.text('使用备用直连'));
      expect(direct, 1);
    },
  );
  testWidgets(
    'help explains real pairing workflow and no unprobed online state',
    (tester) async {
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'lan',
            checkingLocal: false,
            localAvailable: true,
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('连接帮助'));
      await tester.pumpAndSettle();
      expect(find.text('连接你的电脑'), findsOneWidget);
      expect(find.text('其他已保存电脑的在线状态，以实际连接结果为准。'), findsOneWidget);
    },
  );
}
