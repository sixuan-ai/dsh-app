/// Virtual pet: a local-only companion with decaying care stats (饱腹/心情/
/// 清洁) and a growth level derived from the user's cumulative cache-hit
/// input tokens (1 M tokens per level). Care stats persist in
/// SharedPreferences; all time math goes through [Pet.applyElapsed], so
/// background time decays the pet exactly once per load regardless of app
/// uptime.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Care-stat ceiling and starting value for a freshly adopted pet.
const kPetStatMax = 100;

/// Decay per elapsed hour, applied proportionally by [Pet.applyElapsed].
const kPetHungerDecayPerHour = 6.0;
const kPetMoodDecayPerHour = 4.0;
const kPetHygieneDecayPerHour = 3.0;

/// Cache-hit input tokens per pet level: every 1 M levels the pet up once.
const kPetTokensPerLevel = 1000000;

/// Current growth level for a cumulative token count (1-based).
int petLevelForTokens(int tokens) =>
    math.max(0, tokens) ~/ kPetTokensPerLevel + 1;

/// Fraction (0..1) of tokens within the current level.
double petLevelProgressForTokens(int tokens) =>
    (math.max(0, tokens) % kPetTokensPerLevel) / kPetTokensPerLevel;

/// One evolution form of the pet, reached at [minLevel].
class PetStage {
  const PetStage({
    required this.name,
    required this.minLevel,
    required this.base,
  });

  /// Display name (蛋蛋/幼崽/小猫/猛虎/神兽).
  final String name;

  /// First level (inclusive) of this form.
  final int minLevel;

  /// Species emoji; non-cat forms compose mood faces from it.
  final String base;
}

/// Shared level thresholds for every species' five evolution forms.
const kPetStageMinLevels = [1, 3, 6, 10, 15];

/// A pet species: five evolution forms sharing [kPetStageMinLevels].
class PetSpecies {
  const PetSpecies({
    required this.id,
    required this.name,
    required this.stages,
  });

  /// Stable id persisted on the pet (spirit/cat/dog/dragon/phoenix).
  final String id;

  /// Species display name (灵宠/灵猫/神犬/神龙/凤凰).
  final String name;

  /// Evolution forms, ascending by [PetStage.minLevel]; length 5.
  final List<PetStage> stages;

  /// The form for a cumulative token count.
  PetStage stageForTokens(int tokens) =>
      stages[petStageIndexForTokens(tokens)];
}

/// Adoptable species, named in the 宝可梦/洛克王国 evolution-family style.
/// The 'spirit' chain keeps the v1.10.5 emoji sequence, so pets adopted
/// before species existed keep their exact faces (only names change).
const kPetSpecies = [
  PetSpecies(id: 'spirit', name: '哈灵', stages: [
    PetStage(name: '灵蛋', minLevel: 1, base: '🥚'),
    PetStage(name: '小哈仔', minLevel: 3, base: '🐥'),
    PetStage(name: '哈灵猫', minLevel: 6, base: '🐱'),
    PetStage(name: '威哈虎', minLevel: 10, base: '🐯'),
    PetStage(name: '哈灵龙皇', minLevel: 15, base: '🐉'),
  ]),
  PetSpecies(id: 'cat', name: '雷光猫', stages: [
    PetStage(name: '灵蛋', minLevel: 1, base: '🥚'),
    PetStage(name: '闪电喵', minLevel: 3, base: '🐱'),
    PetStage(name: '疾电猫', minLevel: 6, base: '🐈'),
    PetStage(name: '雷纹虎', minLevel: 10, base: '🐯'),
    PetStage(name: '雷霆狮皇', minLevel: 15, base: '🦁'),
  ]),
  PetSpecies(id: 'dog', name: '苍月狼', stages: [
    PetStage(name: '灵蛋', minLevel: 1, base: '🥚'),
    PetStage(name: '小苍犬', minLevel: 3, base: '🐶'),
    PetStage(name: '苍月犬', minLevel: 6, base: '🐕'),
    PetStage(name: '啸月狼', minLevel: 10, base: '🐺'),
    PetStage(name: '九尾天狐', minLevel: 15, base: '🦊'),
  ]),
  PetSpecies(id: 'dragon', name: '焚天炎龙', stages: [
    PetStage(name: '灵蛋', minLevel: 1, base: '🥚'),
    PetStage(name: '小火蜥', minLevel: 3, base: '🦎'),
    PetStage(name: '熔岩鳄', minLevel: 6, base: '🐊'),
    PetStage(name: '烈焰飞龙', minLevel: 10, base: '🐲'),
    PetStage(name: '焚天炎龙', minLevel: 15, base: '🐉'),
  ]),
  PetSpecies(id: 'phoenix', name: '九天凤凰', stages: [
    PetStage(name: '灵蛋', minLevel: 1, base: '🥚'),
    PetStage(name: '绒绒雏', minLevel: 3, base: '🐣'),
    PetStage(name: '云雀仔', minLevel: 6, base: '🐥'),
    PetStage(name: '疾风鹰', minLevel: 10, base: '🦅'),
    PetStage(name: '九天凤凰', minLevel: 15, base: '🦚'),
  ]),
];

/// Resolves a persisted species id; unknown/old saves map to the original
/// 'spirit' chain.
PetSpecies petSpeciesById(String? id) {
  for (final species in kPetSpecies) {
    if (species.id == id) return species;
  }
  return kPetSpecies.first;
}

/// Random species id for a fresh adoption (mystery egg: the species only
/// reveals itself when the egg hatches).
String randomPetSpeciesId() =>
    kPetSpecies[math.Random().nextInt(kPetSpecies.length)].id;

/// Index into any species' stage list for a cumulative token count (all
/// chains share [kPetStageMinLevels]).
int petStageIndexForTokens(int tokens) {
  final level = petLevelForTokens(tokens);
  var index = 0;
  for (var i = 0; i < kPetStageMinLevels.length; i++) {
    if (level >= kPetStageMinLevels[i]) index = i;
  }
  return index;
}

/// Face emoji for [pet] at [stage]: the most urgent unmet need wins,
/// otherwise the overall average decides. The cat form keeps the expressive
/// cat faces; other forms compose `base` with a mood mark.
String petFace(Pet pet, PetStage stage) {
  if (stage.base == '🐱') {
    if (pet.hunger <= 15) return '😿'; // 饿哭了
    if (pet.hygiene <= 15) return '🙀'; // 脏到炸毛
    if (pet.mood <= 15) return '😾'; // 不开心
    if (pet.overall >= 80) return '😸';
    if (pet.overall >= 55) return '😺';
    if (pet.overall >= 35) return '😽';
    return '🙁';
  }
  if (pet.hunger <= 15) return '${stage.base}💦';
  if (pet.hygiene <= 15) return '${stage.base}🛁';
  if (pet.mood <= 15) return '${stage.base}💔';
  if (pet.overall >= 80) return '${stage.base}✨';
  if (pet.overall >= 35) return stage.base;
  return '${stage.base}🌧️';
}

/// The pet's state. Stats are integers in `0..kPetStatMax`. All mutators
/// clamp instead of throwing.
class Pet {
  Pet({
    required this.name,
    required this.speciesId,
    required this.hunger,
    required this.mood,
    required this.hygiene,
    required this.bornAtMs,
    required this.lastTickMs,
  });

  /// A freshly adopted pet with full stats. [speciesId] defaults to the
  /// original chain; the pet page passes [randomPetSpeciesId] for the
  /// mystery-egg draw.
  factory Pet.newborn(String name, int nowMs, {String speciesId = 'spirit'}) =>
      Pet(
        name: name,
        speciesId: speciesId,
        hunger: kPetStatMax,
        mood: kPetStatMax,
        hygiene: kPetStatMax,
        bornAtMs: nowMs,
        lastTickMs: nowMs,
      );

  /// Restores a pet from its persisted JSON (missing keys fall back to a
  /// newborn's values so older saves keep loading; the retired `growth` key
  /// from v1.10.0 saves is ignored — growth now derives from tokens).
  factory Pet.fromJson(Map<String, dynamic> json, int nowMs) => Pet(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : '小哈',
        speciesId: (json['speciesId'] as String?) ?? 'spirit',
        hunger: _clampStat((json['hunger'] as num?)?.toInt() ?? kPetStatMax),
        mood: _clampStat((json['mood'] as num?)?.toInt() ?? kPetStatMax),
        hygiene: _clampStat((json['hygiene'] as num?)?.toInt() ?? kPetStatMax),
        bornAtMs: (json['bornAtMs'] as num?)?.toInt() ?? nowMs,
        lastTickMs: (json['lastTickMs'] as num?)?.toInt() ?? nowMs,
      )..stageSeen = (json['stageSeen'] as num?)?.toInt();

  String name;

  /// Species drawn at adoption; fixed for the pet's lifetime.
  String speciesId;

  int hunger;
  int mood;
  int hygiene;

  /// Evolution form index (into the species' stage list) the user has
  /// already seen and celebrated; null on old saves. The pet page advances
  /// it silently on first load and pops a celebration when the stage
  /// crosses upward.
  int? stageSeen;

  /// Adoption time, milliseconds since epoch.
  final int bornAtMs;

  /// Last time [applyElapsed] ran; decay is measured from here.
  int lastTickMs;

  static int _clampStat(int v) => v.clamp(0, kPetStatMax);

  Map<String, dynamic> toJson() => {
        'name': name,
        'speciesId': speciesId,
        'hunger': hunger,
        'mood': mood,
        'hygiene': hygiene,
        'stageSeen': ?stageSeen,
        'bornAtMs': bornAtMs,
        'lastTickMs': lastTickMs,
      };

  /// Mean of the three care stats; drives the overall face.
  double get overall => (hunger + mood + hygiene) / 3;

  /// Applies time-based decay for the span since the last tick. Safe to call
  /// repeatedly or with a past/future [nowMs] (future clocks move the tick
  /// forward without rewinding stats).
  void applyElapsed(int nowMs) {
    if (nowMs <= lastTickMs) {
      lastTickMs = math.max(lastTickMs, nowMs);
      return;
    }
    final hours = (nowMs - lastTickMs) / Duration.millisecondsPerHour;
    hunger = _clampStat((hunger - hours * kPetHungerDecayPerHour).round());
    mood = _clampStat((mood - hours * kPetMoodDecayPerHour).round());
    hygiene = _clampStat((hygiene - hours * kPetHygieneDecayPerHour).round());
    lastTickMs = nowMs;
  }

  /// Feeds the pet: restores 饱腹, small 心情 comfort.
  void feed() {
    hunger = _clampStat(hunger + 30);
    mood = _clampStat(mood + 2);
  }

  /// Plays with the pet: big 心情 boost at a 饱腹/清洁 cost. Refused when the
  /// pet is too hungry (returns false; nothing changes).
  bool play() {
    if (hunger < 15) return false;
    mood = _clampStat(mood + 25);
    hunger = _clampStat(hunger - 8);
    hygiene = _clampStat(hygiene - 5);
    return true;
  }

  /// Bathes the pet: restores 清洁, small 心情 lift.
  void clean() {
    hygiene = _clampStat(hygiene + 35);
    mood = _clampStat(mood + 3);
  }

  /// Renames the pet; blank names are ignored (returns false).
  bool rename(String next) {
    final trimmed = next.trim();
    if (trimmed.isEmpty) return false;
    name = trimmed;
    return true;
  }

  /// Short status line matching [petFace], shown under the pet.
  String get statusLine {
    if (hunger <= 15) return '肚子饿扁了,快喂我!';
    if (hygiene <= 15) return '身上脏脏的,想洗澡…';
    if (mood <= 15) return '有点孤单,陪我玩嘛';
    if (overall >= 80) return '今天心情超棒!';
    if (overall >= 55) return '感觉很不错~';
    if (overall >= 35) return '还凑合吧';
    return '需要你的照顾';
  }
}

/// Loads/saves the single local pet in SharedPreferences.
class PetStore {
  static const _key = 'petState';

  /// Returns the persisted pet with decay applied up to now, or null when no
  /// pet was adopted yet.
  Future<Pet?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('pet state not a map');
      final pet = Pet.fromJson(decoded.cast<String, dynamic>(), now);
      pet.applyElapsed(now);
      return pet;
    } on FormatException {
      // Corrupt payload: start over instead of crashing the page.
      await prefs.remove(_key);
      return null;
    }
  }

  /// Persists [pet] (or deletes it when null).
  Future<void> save(Pet? pet) async {
    final prefs = await SharedPreferences.getInstance();
    if (pet == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(pet.toJson()));
    }
  }
}

/// Cumulative cache-hit input tokens per session, persisted across launches.
/// The server's tokenUsage projection is cumulative per session, so each
/// session contributes only its max observed value; the pet's growth total
/// is the sum across sessions.
class PetTokenStore {
  static const _key = 'petTokenTotals';

  /// Reads the persisted per-session map (empty on corruption).
  Future<Map<String, int>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('token map not a map');
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    } on FormatException {
      await prefs.remove(_key);
      return {};
    }
  }

  /// Global total across all recorded sessions.
  Future<int> total() async =>
      (await _read()).values.fold<int>(0, (sum, v) => sum + v);

  /// Records one session's cumulative hit-token observation (max wins) and
  /// returns the global total.
  Future<int> record(String sessionId, int tokens) async {
    final map = await _read();
    final previous = map[sessionId] ?? 0;
    if (tokens > previous) {
      map[sessionId] = tokens;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    }
    return map.values.fold<int>(0, (sum, v) => sum + v);
  }
}
