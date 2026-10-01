/// Developer tools: host DSH status, live request/agent logs (polled), and a
/// guarded restart control. All data comes from the host auth gateway, so it
/// works identically over the tunnel or the LAN.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart' show kDefaultServerUrl;
import 'src/l10n.dart';
import 'src/theme.dart';

class DshStatus {
  const DshStatus({
    required this.version,
    required this.running,
    this.pid,
    this.uptime,
    this.rssKb,
    this.memPercent,
    this.cpuPercent,
  });

  factory DshStatus.fromJson(Map<String, dynamic> json) => DshStatus(
    version: json['version'] as String? ?? '',
    running: json['running'] == true,
    pid: (json['pid'] as num?)?.toInt(),
    uptime: json['uptime'] as String?,
    rssKb: (json['rssKb'] as num?)?.toInt(),
    memPercent: (json['memPercent'] as num?)?.toDouble(),
    cpuPercent: (json['cpuPercent'] as num?)?.toDouble(),
  );

  final String version;
  final bool running;
  final int? pid;
  final String? uptime;
  final int? rssKb;
  final double? memPercent;
  final double? cpuPercent;
}

class DshLogs {
  const DshLogs({required this.proxy, required this.dsh});

  factory DshLogs.fromJson(Map<String, dynamic> json) => DshLogs(
    proxy: json['proxy'] as String? ?? '',
    dsh: json['dsh'] as String? ?? '',
  );

  final String proxy;
  final String dsh;
}

class DevToolsPage extends StatefulWidget {
  const DevToolsPage({super.key, this.username, this.password, this.client});

  final String? username;
  final String? password;

  /// Injectable transport for tests; defaults to the global http.
  final http.Client? client;

  @override
  State<DevToolsPage> createState() => _DevToolsPageState();
}

class _DevToolsPageState extends State<DevToolsPage> {
  DshStatus? _status;
  DshLogs? _logs;
  String? _error;
  bool _loadingLogs = false;
  bool _autoRefresh = true;
  Timer? _timer;
  bool _restarting = false;

  http.Client get _client => widget.client ?? http.Client();

  Map<String, String> get _headers {
    final headers = <String, String>{'Accept': 'application/json'};
    final user = widget.username;
    final pass = widget.password;
    if (user != null && pass != null) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    }
    return headers;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_autoRefresh) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (_loadingLogs) return;
    setState(() => _loadingLogs = true);
    try {
      final statusResp = await _client
          .get(
            Uri.parse('$kDefaultServerUrl/api/dsh-status'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      final logsResp = await _client
          .get(
            Uri.parse('$kDefaultServerUrl/api/dsh-logs?lines=100'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (statusResp.statusCode == 200 && logsResp.statusCode == 200) {
        setState(() {
          _status = DshStatus.fromJson(
            (jsonDecode(statusResp.body) as Map).cast<String, dynamic>(),
          );
          _logs = DshLogs.fromJson(
            (jsonDecode(logsResp.body) as Map).cast<String, dynamic>(),
          );
          _error = null;
        });
      } else {
        setState(() => _error = S.devToolsFetchFailed);
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.devToolsFetchFailed);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _restart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.restartDsh),
        content: Text(S.restartConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.restartDsh),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restarting = true);
    try {
      final response = await _client
          .post(
            Uri.parse('$kDefaultServerUrl/api/dsh-restart'),
            headers: _headers,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _toast(response.statusCode == 200 ? S.restartSuccess : S.restartFailed);
    } catch (_) {
      if (mounted) _toast(S.restartFailed);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.devTools)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(status: _status, error: _error),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.logsTitle,
                    style: TextStyle(
                      color: P.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  S.autoRefresh,
                  style: TextStyle(fontSize: 12, color: P.textTertiary),
                ),
                Switch(
                  value: _autoRefresh,
                  onChanged: (value) {
                    setState(() {
                      _autoRefresh = value;
                      _startTimer();
                    });
                  },
                ),
                IconButton(
                  tooltip: S.refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _refresh,
                ),
              ],
            ),
            _LogCard(title: S.proxyLogs, text: _logs?.proxy ?? ''),
            const SizedBox(height: 12),
            _LogCard(title: S.dshLogs, text: _logs?.dsh ?? ''),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: P.danger.withValues(alpha: 0.12),
                foregroundColor: P.danger,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _restarting ? null : _restart,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(_restarting ? S.loading : S.restartDsh),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.error});

  final DshStatus? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: P.fillSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s == null
                      ? P.textTertiary
                      : s.running
                      ? P.success
                      : P.danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                s == null
                    ? S.loading
                    : s.running
                    ? S.dshProcessRunning
                    : S.dshProcessStopped,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: s == null
                      ? P.textSecondary
                      : s.running
                      ? P.success
                      : P.danger,
                ),
              ),
              const Spacer(),
              if (s != null && s.version.isNotEmpty)
                Text(
                  'v${s.version}',
                  style: TextStyle(color: P.textTertiary, fontSize: 13),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: P.danger, fontSize: 12.5)),
          ],
          if (s != null && s.running) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(label: S.dshPid, value: '${s.pid}'),
                _StatChip(label: S.dshUptime, value: s.uptime ?? '—'),
                _StatChip(
                  label: S.dshMemory,
                  value: s.rssKb == null
                      ? '—'
                      : '${(s.rssKb! / 1024).toStringAsFixed(0)} MB',
                ),
                _StatChip(
                  label: S.dshCpu,
                  value: s.cpuPercent == null
                      ? '—'
                      : '${s.cpuPercent!.toStringAsFixed(1)}%',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label  $value',
        style: TextStyle(
          fontSize: 12,
          color: P.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.trim().isEmpty
        ? const <String>[]
        : text.trim().split('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: P.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            Text('—', style: TextStyle(color: P.textTertiary, fontSize: 12))
          else
            SelectableText(
              lines.reversed.take(60).toList().reversed.join('\n'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                height: 1.35,
                color: P.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
