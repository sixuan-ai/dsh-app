/// DSH (server framework) update checker: compares the version installed on
/// the host (read by the auth gateway) with the latest npm release, and shows
/// the newest GitHub release notes. How-to-update hint included for the PC.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;

import 'main.dart' show kDefaultServerUrl;
import 'src/l10n.dart';
import 'src/theme.dart';

/// Update status payload from the host gateway (`/api/dsh-update`).
class DshUpdateInfo {
  const DshUpdateInfo({
    required this.installed,
    this.latest,
    this.hasUpdate = false,
    this.notes = '',
    this.releaseUrl,
  });

  factory DshUpdateInfo.fromJson(Map<String, dynamic> json) => DshUpdateInfo(
    installed: json['installed'] as String? ?? '',
    latest: json['latest'] as String?,
    hasUpdate: json['hasUpdate'] == true,
    notes: json['notes'] as String? ?? '',
    releaseUrl: json['releaseUrl'] as String?,
  );

  final String installed;
  final String? latest;
  final bool hasUpdate;
  final String notes;
  final String? releaseUrl;
}

class DshUpdatePage extends StatefulWidget {
  const DshUpdatePage({super.key, this.username, this.password, this.client});

  /// DSH login credentials, forwarded as Basic auth to the host gateway.
  final String? username;
  final String? password;

  /// Injectable transport for tests; defaults to the global http.
  final http.Client? client;

  @override
  State<DshUpdatePage> createState() => _DshUpdatePageState();
}

class _DshUpdatePageState extends State<DshUpdatePage> {
  bool _loading = false;
  DshUpdateInfo? _info;
  String? _error;

  http.Client get _client => widget.client ?? http.Client();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      final user = widget.username;
      final pass = widget.password;
      if (user != null && pass != null) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }
      final response = await _client
          .get(Uri.parse('$kDefaultServerUrl/api/dsh-update'), headers: headers)
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _info = DshUpdateInfo.fromJson(
            (jsonDecode(response.body) as Map).cast<String, dynamic>(),
          );
        });
      } else {
        setState(() => _error = '${S.dshCheckFailed}(${response.statusCode})');
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.dshCheckFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(S.dshUpdate)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _check,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_loading ? S.loading : S.refresh),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: P.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: P.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: TextStyle(color: P.danger)),
                    ),
                  ],
                ),
              ),
            ],
            if (info != null) ...[
              const SizedBox(height: 20),
              _VersionRow(label: S.dshInstalled, value: info.installed),
              const SizedBox(height: 10),
              _VersionRow(
                label: S.dshLatest,
                value: info.latest ?? '—',
                highlight: info.hasUpdate,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: (info.hasUpdate ? P.accent : P.success).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      info.hasUpdate
                          ? Icons.new_releases_outlined
                          : Icons.check_circle,
                      size: 16,
                      color: info.hasUpdate ? P.accent : P.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      info.hasUpdate ? S.dshUpdateAvailable : S.dshUpToDate,
                      style: TextStyle(
                        color: info.hasUpdate ? P.accent : P.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (info.hasUpdate) ...[
                const SizedBox(height: 18),
                Text(
                  S.dshHowToUpdate,
                  style: TextStyle(
                    color: P.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: P.fillLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    'npm install -g @deepseek-ai/dsh@latest',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: P.code,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  S.dshUpdateCommandHint,
                  style: TextStyle(color: P.textTertiary, fontSize: 12),
                ),
              ],
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  S.dshReleaseNotes,
                  style: TextStyle(
                    color: P.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: P.fillSubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: MarkdownBody(
                    data: info.notes,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          p: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: P.textSecondary,
                          ),
                          listBullet: TextStyle(
                            fontSize: 12.5,
                            color: P.textSecondary,
                          ),
                        ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: P.fillSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: P.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: highlight ? P.accentLight : null,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
