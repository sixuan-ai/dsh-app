/// Upstream BigFish animations, shared by every companion and growth stage.
library;

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const kDafeiyuClips = {
  'idle',
  'waiting',
  'thinking',
  'working',
  'working_search',
  'working_command',
  'success',
  'error',
  'dragging',
  'dragging_release',
  'head_pat',
  'poke',
  'tail',
  'eat_token',
  'idle_stretch',
  'idle_yawn',
};

/// Search and waiting use exactly the same upstream animation bytes.
/// Keep both activity names while bundling their image only once.
String dafeiyuAnimationAsset(String clip) {
  final known = kDafeiyuClips.contains(clip) ? clip : 'idle';
  final asset = known == 'working_search' ? 'waiting' : known;
  return 'assets/pet/dafeiyu/$asset.webp';
}

bool _licenseRegistered = false;

const _loops = {
  'idle',
  'waiting',
  'thinking',
  'working',
  'working_search',
  'working_command',
  'dragging',
};

class PetSprite extends StatefulWidget {
  const PetSprite({
    super.key,
    required this.speciesId,
    required this.stageIndex,
    this.mood = 80,
    this.hatching = false,
    this.size = 180,
    this.animation = 'idle',
    this.playbackId = 0,
    this.onCompleted,
  });
  // Retained for existing callers/saves; appearance is always BigFish.
  final String speciesId;
  final int stageIndex;
  final int mood;
  final bool hatching;
  final double size;
  final String animation;
  final int playbackId;
  final VoidCallback? onCompleted;
  @override
  State<PetSprite> createState() => _PetSpriteState();
}

class _PetSpriteState extends State<PetSprite> with WidgetsBindingObserver {
  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _timer;
  int _generation = 0;
  int _shown = 0;
  bool _finished = false;
  bool _decoding = false;
  bool _enabled = false;
  bool _initialized = false;
  bool _reducedMotion = false;
  bool _foreground = true;
  Duration _duration = const Duration(milliseconds: 42);
  String get _clip =>
      kDafeiyuClips.contains(widget.animation) ? widget.animation : 'idle';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!_licenseRegistered) {
      _licenseRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          '大肥鱼动画 · PC2005-cloud/dsh-pet',
        ], await rootBundle.loadString('assets/pet/dafeiyu/LICENSE.txt'));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = TickerMode.valuesOf(context).enabled && !_reducedMotion;
    if (!_initialized || enabled != _enabled) {
      _initialized = true;
      _enabled = enabled;
      _restart();
    }
  }

  @override
  void didUpdateWidget(PetSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.playbackId != widget.playbackId) {
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && _enabled) {
      if (_codec == null) {
        unawaited(_restart());
      } else {
        _schedule(_generation);
      }
    }
  }

  Future<void> _restart() async {
    final generation = ++_generation;
    _timer?.cancel();
    _codec?.dispose();
    _codec = null;
    _shown = 0;
    _finished = false;
    if (!_enabled || !_foreground) {
      setState(() {});
      if (_reducedMotion && !_loops.contains(_clip)) _complete(generation);
      return;
    }
    try {
      final data = await rootBundle.load(dafeiyuAnimationAsset(_clip));
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _advance(generation);
    } catch (error) {
      // Keep the original poster visible if a codec cannot be loaded.
      if (mounted && generation == _generation) {
        _codec?.dispose();
        _codec = null;
        final old = _frame;
        setState(() => _frame = null);
        old?.dispose();
        _complete(generation);
      }
    }
  }

  Future<void> _advance(int generation) async {
    final codec = _codec;
    if (!mounted || generation != _generation || codec == null) return;
    _decoding = true;
    ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (_) {
      if (mounted && generation == _generation) {
        _finished = true;
        _complete(generation);
      }
      return;
    } finally {
      if (generation == _generation) _decoding = false;
    }
    if (!mounted || generation != _generation) {
      frame.image.dispose();
      return;
    }
    final old = _frame;
    setState(() {
      _frame = frame.image;
      _shown++;
      _duration = frame.duration;
    });
    old?.dispose();
    _schedule(generation);
  }

  void _schedule(int generation) {
    _timer?.cancel();
    if (!_enabled || !_foreground || _finished || _decoding) return;
    _timer = Timer(_duration, () {
      if (!mounted || generation != _generation) return;
      if (!_loops.contains(_clip) && _shown >= (_codec?.frameCount ?? 0)) {
        _finished = true;
        _complete(generation);
        return;
      }
      unawaited(_advance(generation));
    });
  }

  void _complete(int generation) {
    scheduleMicrotask(() {
      if (mounted && generation == _generation) widget.onCompleted?.call();
    });
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _codec?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '大肥鱼',
    image: true,
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: _frame == null || !_enabled
          ? Image.asset('assets/pet/dafeiyu/poster.webp', fit: BoxFit.contain)
          : RawImage(image: _frame, fit: BoxFit.contain),
    ),
  );
}
