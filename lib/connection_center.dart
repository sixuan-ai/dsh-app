/// Full-page device hub; preserves the previous connection widget API.
library;

import 'access_policy.dart';

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'src/theme.dart';

import 'src/l10n.dart';
import 'src/connector_pairing.dart';
import 'src/protocol.dart';

class ConnectionCenterSheet extends StatelessWidget {
  const ConnectionCenterSheet({
    super.key,
    required this.connectionMode,
    required this.checkingLocal,
    required this.localAvailable,
    required this.onSwitchRemote,
    required this.onSwitchLocal,
    required this.onRefreshLocal,
    this.connected = true,
    this.reconnecting = false,
    this.onSwitchDirect,
    this.localUrl,
    this.onSetLocalAddress,
    this.onAutoSearchLocal,
    this.computers = const [],
    this.currentComputerId,
    this.pairedName,
    this.pairedComputers = const [],
    this.activePairedNodeId,
    this.onSwitchPairedComputer,
    this.pairedRemoteUrl,
    this.onPairComputer,
    this.onSwitchComputer,
    this.accountLabel,
    this.onAccount,
  });

  final String connectionMode;
  final String? accountLabel;
  final VoidCallback? onAccount;
  final bool connected;
  final bool reconnecting;
  final bool checkingLocal;
  final bool localAvailable;
  final VoidCallback onSwitchRemote;
  final VoidCallback onSwitchLocal;
  final VoidCallback onRefreshLocal;

  /// Switches to the direct Shenzhen relay (low-latency route).
  final VoidCallback? onSwitchDirect;

  /// Persisted LAN address of the local computer (empty when unset).
  final String? localUrl;

  /// Opens the local-address editor (HomePage owns the dialog).
  final VoidCallback? onSetLocalAddress;

  /// Runs mDNS discovery for DSH hosts on the LAN.
  final VoidCallback? onAutoSearchLocal;

  /// The account's computers, as last reported by the directory at login.
  final List<AccountComputer> computers;

  /// Id of the computer the socket is currently connected to.
  final String? currentComputerId;
  final List<PairedComputer> pairedComputers;
  final String? activePairedNodeId;
  final void Function(PairedComputer)? onSwitchPairedComputer;
  final String? pairedName;
  final String? pairedRemoteUrl;
  final VoidCallback? onPairComputer;

  /// Switches to one of the account's computers.
  final void Function(AccountComputer computer)? onSwitchComputer;

  String get _deviceName {
    if (pairedName != null) return pairedName!;
    for (final computer in computers) {
      if (computer.id == currentComputerId) return computer.name;
    }
    return '我的电脑';
  }

  void _switch(BuildContext context, VoidCallback callback) {
    Navigator.of(context).maybePop();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final c = _HubColors(Theme.of(context).brightness == Brightness.dark);
    final total = pairedComputers.length + computers.length;
    final otherPaired = pairedComputers
        .where((p) => p.nodeId != activePairedNodeId)
        .toList();
    final otherAccount = computers
        .where((p) => activePairedNodeId != null || p.id != currentComputerId)
        .toList();
    final publicEnabled = (pairedName == null || pairedRemoteUrl != null);
    final lanEnabled =
        localAvailable ||
        connectionMode == 'lan' ||
        (localUrl?.isNotEmpty ?? false);
    final routeLabel = switch (connectionMode) {
      'lan' => '局域网直连',
      'direct' => '备用直连',
      'pending' => '正在选择连接路径',
      _ => '公网连接',
    };
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: c.lime.withValues(alpha: .08),
        highlightColor: c.lime.withValues(alpha: .05),
        dividerColor: P.transparent,
      ),
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            Positioned(
              top: -100,
              left: -130,
              child: IgnorePointer(
                child: Container(
                  width: 470,
                  height: 470,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        c.lime.withValues(alpha: c.dark ? .10 : .14),
                        c.bg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RoundControl(
                          c: c,
                          icon: Icons.arrow_back_rounded,
                          tooltip: '返回',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.inset,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: c.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'xHarness',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  color: c.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Spacer(),
                        _RoundControl(
                          c: c,
                          icon: Icons.help_outline_rounded,
                          tooltip: '连接帮助',
                          onTap: () => _help(context, c),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      '连接中心',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -.8,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '工作，在每台电脑间自由继续',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 22),
                    _CurrentDevice(
                      c: c,
                      name: _deviceName,
                      connected: connected,
                      reconnecting: reconnecting,
                      route: routeLabel,
                    ),
                    SizedBox(height: 18),
                    _Surface(
                      c: c,
                      radius: 25,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '连接方式',
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Spacer(),
                                IconButton(
                                  tooltip: S.retestLocal,
                                  onPressed: checkingLocal
                                      ? null
                                      : onRefreshLocal,
                                  constraints: BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  icon: checkingLocal
                                      ? SizedBox(
                                          width: 17,
                                          height: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: c.accent,
                                          ),
                                        )
                                      : Icon(
                                          Icons.refresh_rounded,
                                          size: 20,
                                          color: c.muted,
                                        ),
                                ),
                              ],
                            ),
                            SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: c.inset,
                                borderRadius: BorderRadius.circular(19),
                                border: Border.all(color: c.line),
                                boxShadow: [
                                  BoxShadow(
                                    color: P.neuShadow.withValues(
                                      alpha: c.dark ? .24 : .04,
                                    ),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _RouteChoice(
                                      c: c,
                                      label: '局域网',
                                      icon: Icons.wifi_rounded,
                                      selected: connectionMode == 'lan',
                                      enabled: lanEnabled,
                                      onTap: () =>
                                          _switch(context, onSwitchLocal),
                                    ),
                                  ),
                                  SizedBox(width: 5),
                                  Expanded(
                                    child: _RouteChoice(
                                      c: c,
                                      label: '公网',
                                      icon: Icons.public_rounded,
                                      selected: connectionMode == 'public',
                                      enabled: publicEnabled,
                                      onTap: () =>
                                          _switch(context, onSwitchRemote),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 13),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  publicEnabled
                                      ? Icons.route_outlined
                                      : Icons.info_outline_rounded,
                                  size: 16,
                                  color: c.accent,
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    checkingLocal
                                        ? '正在检测局域网入口…'
                                        : !publicEnabled
                                        ? '此电脑尚未配置公网，可先在同一网络使用'
                                        : pairedName != null
                                        ? '同一网络优先，离开后可通过公网连接'
                                        : '选择当前电脑的连接方式',
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 11.5,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!lanEnabled)
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text(
                                  S.localAddressEmpty,
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 11.5,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => showAccessPolicy(context),
                        icon: Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: c.accent,
                        ),
                        label: Text('功能与权限', style: TextStyle(color: c.accent)),
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '我的电脑',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(width: 9),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.inset,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.line),
                          ),
                          child: Text(
                            total.toString().padLeft(2, '0'),
                            style: TextStyle(
                              color: c.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Spacer(),
                        Text(
                          '选择后连接',
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ],
                    ),
                    SizedBox(height: 13),
                    for (final computer in otherPaired)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _DeviceRow(
                          c: c,
                          name: computer.name,
                          source: '已配对',
                          active: computer.nodeId == activePairedNodeId,
                          onTap: onSwitchPairedComputer == null
                              ? null
                              : () => _switch(
                                  context,
                                  () => onSwitchPairedComputer!(computer),
                                ),
                        ),
                      ),
                    for (final computer in otherAccount)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _DeviceRow(
                          c: c,
                          name: computer.name.isEmpty
                              ? computer.id
                              : computer.name,
                          source: '账号设备',
                          active:
                              activePairedNodeId == null &&
                              computer.id == currentComputerId,
                          onTap: onSwitchComputer == null
                              ? null
                              : () => _switch(
                                  context,
                                  () => onSwitchComputer!(computer),
                                ),
                        ),
                      ),
                    if (otherPaired.isEmpty && otherAccount.isEmpty)
                      _Surface(
                        c: c,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Icon(
                                Icons.devices_rounded,
                                color: c.muted,
                                size: 27,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  total == 0
                                      ? '添加电脑后，在这里切换工作区'
                                      : '当前只有这一台电脑，可继续添加更多',
                                  style: TextStyle(
                                    color: c.muted,
                                    height: 1.6,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(height: 8),
                    _Surface(
                      c: c,
                      radius: 22,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: ExpansionTile(
                          key: const PageStorageKey('connection-advanced'),
                          tilePadding: EdgeInsets.symmetric(
                            horizontal: 17,
                            vertical: 3,
                          ),
                          iconColor: c.muted,
                          collapsedIconColor: c.muted,
                          leading: Icon(
                            Icons.tune_rounded,
                            color: c.muted,
                            size: 21,
                          ),
                          title: Text(
                            '连接设置',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '地址、发现与诊断',
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                          childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: [
                            if (localUrl?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 9, 6, 12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SelectableText(
                                    localUrl!,
                                    key: PageStorageKey(
                                      'connection-local-address',
                                    ),
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            if (onSetLocalAddress != null)
                              _SettingAction(
                                c: c,
                                icon: Icons.edit_location_alt_outlined,
                                label: S.setLocalAddress,
                                onTap: onSetLocalAddress!,
                              ),
                            if (onAutoSearchLocal != null)
                              _SettingAction(
                                c: c,
                                icon: Icons.wifi_find_rounded,
                                label: S.autoSearchLocal,
                                onTap: onAutoSearchLocal!,
                              ),
                            _SettingAction(
                              c: c,
                              icon: Icons.refresh_rounded,
                              label: S.retestLocal,
                              onTap: onRefreshLocal,
                            ),
                            if (onSwitchDirect != null)
                              _SettingAction(
                                c: c,
                                icon: Icons.alt_route_rounded,
                                label: '使用备用直连',
                                onTap: () => _switch(context, onSwitchDirect!),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: onPairComputer == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: c.lime.withValues(
                                alpha: c.dark ? .13 : .17,
                              ),
                              blurRadius: 25,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: FilledButton(
                          onPressed: onPairComputer,
                          style: FilledButton.styleFrom(
                            backgroundColor: c.lime,
                            foregroundColor: P.onAccent,
                            minimumSize: const Size(double.infinity, 54),
                            padding: EdgeInsets.symmetric(
                              horizontal: 21,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 23),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '添加 / 管理电脑',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(width: 15),
                              Container(
                                width: 1,
                                height: 18,
                                color: P.neuShadow.withValues(alpha: .18),
                              ),
                              SizedBox(width: 15),
                              Icon(Icons.qr_code_scanner_rounded, size: 21),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '独立保存电脑，切换不丢会话',
                        style: TextStyle(fontSize: 10.5, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _help(BuildContext context, _HubColors c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '连接你的电脑',
                style: TextStyle(
                  color: c.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 18),
              for (final tip in [
                '1. 电脑打开 xHarness 连接器，生成一次性配对码。',
                '2. 手机与电脑在同一网络，添加电脑并核对名称。',
                '3. 无需登录即可使用局域网与公网，登录可选用于账号同步。',
                '4. 切换电脑不会停止电脑上正在运行的任务。',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Text(
                    tip,
                    style: TextStyle(color: c.muted, fontSize: 14, height: 1.7),
                  ),
                ),
              Text(
                '其他已保存电脑的在线状态，以实际连接结果为准。',
                style: TextStyle(color: c.accent, fontSize: 12, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '$kLocalAccessLimits $kComputerPermissionSummary',
                style: TextStyle(color: c.muted, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubColors {
  _HubColors(this.dark);
  final bool dark;
  AppPalette get palette =>
      dark == P.isDark ? P : paletteFor(dark ? "obsidian" : "light");
  Color get bg => palette.bg;
  Color get surface => palette.card;
  Color get inset => palette.code;
  Color get text => palette.text;
  Color get muted => palette.textSecondary;
  Color get lime => palette.accent;
  Color get accent => palette.accent;
  Color get line => palette.divider;
  Color get onLime => palette.onAccent;
  List<BoxShadow> get shadows => palette.neuShadows;
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.c,
    required this.child,
    this.radius = 20,
    this.active = false,
  });
  final _HubColors c;
  final Widget child;
  final double radius;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: active ? c.accent.withValues(alpha: .35) : c.line,
      ),
      boxShadow: c.shadows,
    ),
    child: Material(
      color: P.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: child,
    ),
  );
}

class _CurrentDevice extends StatelessWidget {
  const _CurrentDevice({
    required this.c,
    required this.name,
    required this.route,
    required this.connected,
    required this.reconnecting,
  });
  final _HubColors c;
  final String name, route;
  final bool connected, reconnecting;
  @override
  Widget build(BuildContext context) {
    final status = connected
        ? '已连接'
        : reconnecting
        ? '连接中'
        : '离线';
    final statusColor = connected
        ? c.accent
        : reconnecting
        ? c.muted
        : c.dark
        ? P.warning
        : P.warning;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          ...c.shadows,
          BoxShadow(color: c.lime.withValues(alpha: .045), blurRadius: 27),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.accent.withValues(alpha: .26)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.dark ? P.glassHighlight.withValues(alpha: .08) : c.surface,
                  c.dark ? P.glassFill : c.surface,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '当前设备',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withValues(alpha: .3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              connected
                                  ? Icons.circle
                                  : reconnecting
                                  ? Icons.sync
                                  : Icons.cloud_off_outlined,
                              size: 8,
                              color: statusColor,
                            ),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.route_rounded,
                                size: 13,
                                color: c.accent,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  route,
                                  style: TextStyle(
                                    color: c.accent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 15),
                    Container(
                      width: 67,
                      height: 67,
                      decoration: BoxDecoration(
                        color: c.inset,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: P.neuShadow.withValues(
                              alpha: c.dark ? .38 : .08,
                            ),
                            blurRadius: 10,
                            offset: const Offset(3, 5),
                          ),
                          BoxShadow(
                            color: P.glassHighlight.withValues(
                              alpha: c.dark ? .04 : .8,
                            ),
                            blurRadius: 7,
                            offset: const Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.desktop_windows_outlined,
                            size: 34,
                            color: c.text.withValues(alpha: .85),
                          ),
                          Positioned(
                            top: 9,
                            right: 9,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: .3),
                                    blurRadius: 9,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 13),
                Container(height: 1, color: c.line),
                SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link_rounded, size: 14, color: c.muted),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        connected ? '工作区与任务来自这台电脑' : '显示已缓存内容，等待连接恢复',
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.c,
    required this.name,
    required this.source,
    required this.active,
    required this.onTap,
  });
  final _HubColors c;
  final String name, source;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: !active,
    selected: active,
    label: '$name，$source，${active ? '当前电脑' : '切换到此电脑'}',
    child: _Surface(
      c: c,
      active: active,
      child: Material(
        color: P.transparent,
        child: InkWell(
          onTap: active ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.inset,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: active ? c.accent.withValues(alpha: .3) : c.line,
                    ),
                  ),
                  child: Icon(
                    Icons.computer_rounded,
                    size: 22,
                    color: active ? c.accent : c.muted,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        source,
                        style: TextStyle(color: c.muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                if (active)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.accent.withValues(alpha: .3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 13,
                          color: c.accent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '使用中',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '切换',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: c.muted,
                        size: 15,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RouteChoice extends StatelessWidget {
  const _RouteChoice({
    required this.c,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final _HubColors c;
  final String label;
  final IconData icon;
  final bool selected, enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    enabled: enabled,
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? c.surface : P.transparent,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: selected ? c.accent.withValues(alpha: .42) : P.transparent,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: P.neuShadow.withValues(alpha: c.dark ? .25 : .05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: P.transparent,
        child: InkWell(
          onTap: enabled && !selected ? onTap : null,
          borderRadius: BorderRadius.circular(15),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: icon == Icons.public_rounded && enabled
                        ? P.info
                        : selected
                        ? c.accent
                        : c.muted.withValues(alpha: enabled ? 1 : .45),
                  ),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? c.accent
                            : c.muted.withValues(alpha: enabled ? 1 : .45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.c,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final _HubColors c;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: c.surface,
      border: Border.all(color: c.line),
      boxShadow: c.shadows,
    ),
    child: IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, color: c.muted, size: 22),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
  );
}

class _SettingAction extends StatelessWidget {
  const _SettingAction({
    required this.c,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final _HubColors c;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minVerticalPadding: 13,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    leading: Icon(icon, color: c.muted, size: 18),
    title: Text(label, style: TextStyle(color: c.text, fontSize: 12.5)),
    trailing: Icon(Icons.chevron_right_rounded, color: c.muted, size: 17),
    onTap: onTap,
  );
}
