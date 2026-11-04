/// Anonymous reads and Sixuan Bearer writes. Never uses desktop credentials.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const kPetBoardBaseUrl = String.fromEnvironment(
  'PET_BOARD_BASE_URL',
  defaultValue: 'https://dsh.sixuanai.com/social/pet',
);

class PetBoardEntry {
  const PetBoardEntry({
    this.rank,
    required this.nickname,
    this.petName = '大肥鱼',
    this.species = 'dafeiyu',
    this.stage = '初见伙伴',
    this.tokens = 0,
    this.pkScore = 1000,
    this.level = 1,
    this.score = 0,
    this.gap = 0,
    this.optedOut = false,
  });
  final int? rank;
  final String nickname, petName, species, stage;
  final int tokens, pkScore, level, score, gap;
  final bool optedOut;
  factory PetBoardEntry.fromJson(Map<String, dynamic> v) => PetBoardEntry(
    rank: (v['rank'] as num?)?.toInt(),
    nickname: v['nickname'] as String? ?? '',
    petName: v['petName'] as String? ?? '大肥鱼',
    species: v['species'] as String? ?? 'dafeiyu',
    stage: v['stage'] as String? ?? '初见伙伴',
    tokens: (v['tokens'] as num?)?.toInt() ?? 0,
    pkScore: (v['pkScore'] as num?)?.toInt() ?? 1000,
    level: (v['level'] as num?)?.toInt() ?? 1,
    score: (v['score'] as num?)?.toInt() ?? 0,
    gap: (v['gap'] as num?)?.toInt() ?? 0,
    optedOut: v['optedOut'] == true,
  );
}

class PetBoardData {
  const PetBoardData({required this.items, this.me, this.weekKey = ''});
  final List<PetBoardEntry> items;
  final PetBoardEntry? me;
  final String weekKey;
  factory PetBoardData.fromJson(Map<String, dynamic> v) => PetBoardData(
    items: [
      for (final e in v['items'] as List? ?? [])
        PetBoardEntry.fromJson((e as Map).cast<String, dynamic>()),
    ],
    me: v['me'] is Map
        ? PetBoardEntry.fromJson((v['me'] as Map).cast<String, dynamic>())
        : null,
    weekKey: v['weekKey'] as String? ?? '',
  );
}

class PetBoardApi {
  PetBoardApi({
    http.Client? client,
    this.baseUrl = kPetBoardBaseUrl,
    required this.token,
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final String baseUrl;
  final String? Function() token;
  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final session = token();
    if (method != 'GET' && session == null) throw StateError('请先登录');
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (session != null) request.headers['Authorization'] = 'Bearer $session';
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('排行榜暂时不可用（${response.statusCode}）');
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }

  Future<PetBoardData> board([String scope = 'all']) async =>
      PetBoardData.fromJson(
        await _call('GET', '/board?scope=$scope&limit=100'),
      );
  Future<Map<String, dynamic>> report(Map<String, dynamic> snapshot) =>
      _call('POST', '/me', snapshot);
  Future<void> settings(String? nickname, bool optedOut) async {
    await _call('PATCH', '/me', {
      'nickname': ?nickname,
      'optedOut': optedOut,
    });
  }

  void close() => _client.close();
}

/// Trailing debounce, independent resume throttle, serialized silent retries.
/// Clock and timer factory are injectable; identity changes cancel pending work.
class PetBoardReporter {
  PetBoardReporter({
    required this.send,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? timer,
  }) : clock = clock ?? DateTime.now,
       timer = timer ?? ((d, f) => Timer(d, f));
  final Future<void> Function() send;
  final DateTime Function() clock;
  final Timer Function(Duration, void Function()) timer;
  Timer? _pending;
  DateTime? _lastAttempt, _lastResume;
  bool _active = false, _busy = false;
  int _generation = 0;
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _generation++;
    _pending?.cancel();
    _lastAttempt = _lastResume = null;
  }

  void changed() {
    if (!_active) return;
    _pending?.cancel();
    _pending = timer(const Duration(seconds: 30), opened);
  }

  void resumed() {
    if (!_active) return;
    final now = clock();
    if (_lastResume != null &&
        now.difference(_lastResume!) < const Duration(minutes: 10)) {
      return;
    }
    _lastResume = now;
    opened();
  }

  void opened() {
    if (!_active) return;
    _pending?.cancel();
    final remaining = _lastAttempt == null
        ? Duration.zero
        : const Duration(seconds: 20) - clock().difference(_lastAttempt!);
    if (_busy || remaining > Duration.zero) {
      _pending = timer(_busy ? const Duration(seconds: 30) : remaining, opened);
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _busy = true;
    _lastAttempt = clock();
    final generation = _generation;
    try {
      await send();
    } catch (_) {
      if (_active && generation == _generation) {
        _pending?.cancel();
        _pending = timer(const Duration(minutes: 1), opened);
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    setActive(false);
    _pending?.cancel();
  }
}
