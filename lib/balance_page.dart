/// DeepSeek API balance viewer. The balance is queried through the DSH host's
/// own auth gateway (`/api/balance`), which reads the DSH credentials store
/// server-side — the API key never reaches the phone.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart' show kDefaultServerUrl;
import 'src/l10n.dart';
import 'src/theme.dart';

/// One currency's balance row as returned by the official API.
class BalanceEntry {
  const BalanceEntry({
    required this.currency,
    required this.total,
    required this.granted,
    required this.toppedUp,
  });

  factory BalanceEntry.fromJson(Map<String, dynamic> json) => BalanceEntry(
    currency: json['currency'] as String? ?? '',
    total: json['total_balance'] as String? ?? '0',
    granted: json['granted_balance'] as String? ?? '0',
    toppedUp: json['topped_up_balance'] as String? ?? '0',
  );

  final String currency;
  final String total;
  final String granted;
  final String toppedUp;
}

class BalanceResult {
  const BalanceResult({required this.isAvailable, required this.entries});

  factory BalanceResult.fromJson(Map<String, dynamic> json) => BalanceResult(
    isAvailable: json['is_available'] as bool? ?? false,
    entries: [
      for (final raw in (json['balance_infos'] as List? ?? []))
        if (raw is Map) BalanceEntry.fromJson(raw.cast<String, dynamic>()),
    ],
  );

  final bool isAvailable;
  final List<BalanceEntry> entries;
}

class BalancePage extends StatefulWidget {
  const BalancePage({super.key, this.username, this.password, this.client});

  /// DSH login credentials, forwarded as Basic auth to the host gateway.
  final String? username;
  final String? password;

  /// Injectable transport for tests; defaults to the global http.
  final http.Client? client;

  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage> {
  bool _loading = false;
  BalanceResult? _result;
  String? _error;

  http.Client get _client => widget.client ?? http.Client();

  Future<void> _query() async {
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
          .get(Uri.parse('$kDefaultServerUrl/api/balance'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _result = BalanceResult.fromJson(
            (jsonDecode(response.body) as Map).cast<String, dynamic>(),
          );
        });
      } else if (response.statusCode == 503) {
        setState(() => _error = S.balanceServerNoKey);
      } else {
        setState(
          () => _error = '${S.balanceQueryFailed}(${response.statusCode})',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.balanceQueryFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.balanceTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: P.fillSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: P.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.balanceServerNote,
                      style: TextStyle(
                        color: P.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _query,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(_loading ? S.loading : S.balanceQuery),
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
            if (_result != null) ...[
              const SizedBox(height: 20),
              _BalanceCard(result: _result!),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _query,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(S.balanceRefresh),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Balance summary card: availability badge + total + granted/topped-up rows.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.result});

  final BalanceResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: P.brandGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [P.brandGlow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: P.onAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      result.isAvailable
                          ? Icons.check_circle
                          : Icons.error_outline,
                      size: 14,
                      color: P.onAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      result.isAvailable
                          ? S.balanceAvailable
                          : S.balanceUnavailable,
                      style: TextStyle(
                        color: P.onAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (result.entries.isNotEmpty)
                Text(
                  result.entries.first.currency,
                  style: TextStyle(
                    color: P.onAccent.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            S.balanceTotal,
            style: TextStyle(
              color: P.onAccent.withValues(alpha: 0.8),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            result.entries.isEmpty ? '0' : result.entries.first.total,
            style: TextStyle(
              color: P.onAccent,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _BalanceLine(
                  label: S.balanceGranted,
                  value: result.entries.isEmpty
                      ? '0'
                      : result.entries.first.granted,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _BalanceLine(
                  label: S.balanceToppedUp,
                  value: result.entries.isEmpty
                      ? '0'
                      : result.entries.first.toppedUp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: P.onAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: P.onAccent.withValues(alpha: 0.8),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: P.onAccent,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
