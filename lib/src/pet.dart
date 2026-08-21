/// Virtual pet: a local-only companion with decaying care stats (饱腹/心情/
/// 清洁), a growth counter fed by care actions, and SharedPreferences
/// persistence. All time math goes through [Pet.applyElapsed], so background
/// time decays the pet exactly once per load regardless of app uptime.
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

/// Growth points needed per level; level N starts at (N-1) × this.
const kPetGrowthPerLevel = 100;

/// The pet's state. Stats are integers in `0..kPetStatMax`; [growth] only
/// ever increases. All mutators clamp instead of throwing.
class Pet {
  Pet({
    required this.name,
    required this.hunger,
    required this.mood,
    required this.hygiene,
    required this.growth,
    required this.bornAtMs,
    required this.lastTickMs,
  });

  /// A freshly adopted pet with full stats and no growth.
  factory Pet.newborn(String name, int nowMs) => Pet(
        name: name,
        hunger: kPetStatMax,
        mood: kPetStatMax,
        hygiene: kPetStatMax,
        growth: 0,
        bornAtMs: nowMs,
        lastTickMs: nowMs,
      );

  /// Restores a pet from its persisted JSON (missing keys fall back to a
  /// newborn's values so older saves keep loading).
  factory Pet.fromJson(Map<String, dynamic> json, int nowMs) => Pet(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : '小哈',
        hunger: _clampStat((json['hunger'] as num?)?.toInt() ?? kPetStatMax),
        mood: _clampStat((json['mood'] as num?)?.toInt() ?? kPetStatMax),
        hygiene: _clampStat((json['hygiene'] as num?)?.toInt() ?? kPetStatMax),
        growth: math.max(0, (json['growth'] as num?)?.toInt() ?? 0),
        bornAtMs: (json['bornAtMs'] as num?)?.toInt() ?? nowMs,
        lastTickMs: (json['lastTickMs'] as num?)?.toInt() ?? nowMs,
      );

  String name;
  int hunger;
  int mood;
  int hygiene;
  int growth;

  /// Adoption time, milliseconds since epoch.
  final int bornAtMs;

  /// Last time [applyElapsed] ran; decay is measured from here.
  int lastTickMs;

  static int _clampStat(int v) => v.clamp(0, kPetStatMax);

  Map<String, dynamic> toJson() => {
        'name': name,
        'hunger': hunger,
        'mood': mood,
        'hygiene': hygiene,
        'growth': growth,
        'bornAtMs': bornAtMs,
        'lastTickMs': lastTickMs,
      };

  /// Current level, 1-based; [levelProgress] is the fraction toward the next.
  int get level => growth ~/ kPetGrowthPerLevel + 1;

  /// Fraction (0..1) of growth within the current level.
  double get levelProgress =>
      (growth % kPetGrowthPerLevel) / kPetGrowthPerLevel;

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

  /// Feeds the pet: restores 饱腹, small 心情 comfort, grants growth.
  void feed() {
    hunger = _clampStat(hunger + 30);
    mood = _clampStat(mood + 2);
    growth += 5;
  }

  /// Plays with the pet: big 心情 boost at a 饱腹/清洁 cost. Refused when the
  /// pet is too hungry (returns false; nothing changes).
  bool play() {
    if (hunger < 15) return false;
    mood = _clampStat(mood + 25);
    hunger = _clampStat(hunger - 8);
    hygiene = _clampStat(hygiene - 5);
    growth += 6;
    return true;
  }

  /// Bathes the pet: restores 清洁, small 心情 lift, grants growth.
  void clean() {
    hygiene = _clampStat(hygiene + 35);
    mood = _clampStat(mood + 3);
    growth += 4;
  }

  /// Renames the pet; blank names are ignored (returns false).
  bool rename(String next) {
    final trimmed = next.trim();
    if (trimmed.isEmpty) return false;
    name = trimmed;
    return true;
  }

  /// Face emoji for the current state: the most urgent unmet need wins,
  /// otherwise the overall average decides.
  String get face {
    if (hunger <= 15) return '😿'; // 饿哭了
    if (hygiene <= 15) return '🙀'; // 脏到炸毛
    if (mood <= 15) return '😾'; // 不开心
    if (overall >= 80) return '😸';
    if (overall >= 55) return '😺';
    if (overall >= 35) return '😽';
    return '🙁';
  }

  /// Short status line matching [face], shown under the pet.
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
      final pet = Pet.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>(), now);
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
