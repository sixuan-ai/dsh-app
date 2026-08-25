/// OTA update availability and download-progress dialogs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'src/formatters.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'src/updater.dart';

// ---------------------------------------------------------------------------
// Update download
// ---------------------------------------------------------------------------

/// Branded update-available dialog: gradient hero, version/size chips, and a
/// scrollable release-notes card above a full-width gradient CTA.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.info,
    required this.onUpdate,
  });

  final UpdateInfo info;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: P.cardAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // gradient hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(gradient: P.brandGradient),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: P.onAccent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    size: 28,
                    color: P.onAccent,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  S.updateAvailableTitle,
                  style: TextStyle(
                    color: P.onAccent,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'v${info.version}',
                  style: TextStyle(
                    color: P.onAccent.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.size != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: P.fillSubtle,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.save_alt_rounded,
                          size: 13,
                          color: P.textTertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${S.installPackage} ${formatBytes(info.size!)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: P.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (info.notes != null && info.notes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: P.fillSubtle,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        info.notes!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: P.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // gradient CTA
                Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: P.brandGradient,
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [P.brandGlow],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      onTap: onUpdate,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.download_rounded,
                              size: 18,
                              color: P.onAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              S.updateNow,
                              style: TextStyle(
                                color: P.onAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      S.later,
                      style: TextStyle(color: P.textTertiary, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal download-progress dialog; on completion it hands the APK to the
/// system installer and closes itself.
class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({
    super.key,
    required this.checker,
    required this.info,
  });

  final UpdateChecker checker;
  final UpdateInfo info;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  int _received = 0;
  int? _total;
  String? _error;

  /// Smoothed download speed (bytes/s), sampled from progress callbacks.
  double? _speed;
  int _lastSampled = 0;
  int _lastSampleTime = 0;

  /// Shown when nothing has arrived yet after a few seconds.
  bool _slowHint = false;
  Timer? _slowHintTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _slowHintTimer?.cancel();
    super.dispose();
  }

  void _sampleSpeed(int received) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSampleTime == 0) {
      _lastSampleTime = now;
      _lastSampled = received;
      return;
    }
    final dt = now - _lastSampleTime;
    if (dt < 500) return;
    final instant = (received - _lastSampled) / (dt / 1000);
    _speed = _speed == null ? instant : _speed! * 0.6 + instant * 0.4;
    _lastSampleTime = now;
    _lastSampled = received;
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _received = 0;
      _total = null;
      _speed = null;
      _lastSampleTime = 0;
      _slowHint = false;
    });
    _slowHintTimer?.cancel();
    _slowHintTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _error == null && _received == 0) {
        setState(() => _slowHint = true);
      }
    });
    try {
      final file = await widget.checker.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
              _sampleSpeed(received);
            });
          }
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.checker.install(file);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final progress = total != null && total > 0 ? _received / total : null;
    return Dialog(
      backgroundColor: P.cardAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.downloadingUpdate,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              'v${widget.info.version}',
              style: TextStyle(fontSize: 12.5, color: P.textTertiary),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: P.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 26,
                  color: P.danger,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '下载失败',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: P.danger,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: P.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('关闭', style: TextStyle(color: P.textTertiary)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(S.retry),
                    style: FilledButton.styleFrom(
                      backgroundColor: P.accent,
                      foregroundColor: P.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 108,
                      height: 108,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: P.fillLight,
                        valueColor: AlwaysStoppedAnimation(P.accent),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          progress != null
                              ? '${(progress * 100).toStringAsFixed(0)}%'
                              : '…',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: P.text,
                          ),
                        ),
                        if (_speed != null)
                          Text(
                            '${formatBytes(_speed!.round())}/s',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: P.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                total != null
                    ? '${formatBytes(_received)} / ${formatBytes(total)}'
                    : '已下载 ${formatBytes(_received)}',
                style: TextStyle(fontSize: 12, color: P.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                _slowHint
                    ? '网络较慢,连接无响应会自动重试…'
                    : '完成后将自动打开安装界面',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
