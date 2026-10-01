/// User feedback form: category, description, optional contact. Submits to
/// the centralized social backend (`/social/feedback`) with Basic auth.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart' show kDefaultServerUrl;
import 'src/l10n.dart';
import 'src/theme.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.username, this.password, this.client});

  final String? username;
  final String? password;

  /// Injectable transport for tests; defaults to the global http.post.
  final http.Client? client;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  String _type = 'bug';
  final TextEditingController _content = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _content.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      final user = widget.username;
      final pass = widget.password;
      if (user != null && pass != null) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }
      final response = await (widget.client ?? http.Client())
          .post(
            Uri.parse('$kDefaultServerUrl/social/feedback'),
            headers: headers,
            body: jsonEncode({
              'type': _type,
              'content': content,
              'contact': _contact.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode == 200) {
        _content.clear();
        _contact.clear();
        _toast(S.submitSuccess);
        Navigator.of(context).pop();
      } else {
        _toast(S.submitFailed);
      }
    } catch (_) {
      if (mounted) _toast(S.submitFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeLabels = [S.typeBug, S.typeSuggestion, S.typeOther];
    const typeValues = ['bug', 'suggestion', 'other'];
    return Scaffold(
      appBar: AppBar(title: Text(S.feedbackTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            S.feedbackType,
            style: TextStyle(color: P.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [
              for (var i = 0; i < typeLabels.length; i++)
                ButtonSegment(value: typeValues[i], label: Text(typeLabels[i])),
            ],
            selected: {_type},
            onSelectionChanged: (selection) {
              setState(() => _type = selection.first);
            },
          ),
          const SizedBox(height: 22),
          Text(
            S.describe,
            style: TextStyle(color: P.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: S.describeHint,
              filled: true,
              fillColor: P.fillSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            S.contact,
            style: TextStyle(color: P.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contact,
            decoration: InputDecoration(
              hintText: S.contactHint,
              filled: true,
              fillColor: P.fillSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(_submitting ? S.loading : S.submit),
          ),
        ],
      ),
    );
  }
}
