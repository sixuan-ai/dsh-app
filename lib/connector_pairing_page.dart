/// Explicit desktop identity preview before granting a phone remote access.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';
import 'state.dart';
import 'src/connector_pairing.dart';

String decodeConnectorQr(Uint8List bytes) {
  var photo = image.decodeImage(bytes);
  if (photo == null) throw const FormatException('无法读取图片');
  photo = image.bakeOrientation(photo);
  if (photo.width > 1400 || photo.height > 1400) {
    photo = image.copyResize(
      photo,
      width: photo.width >= photo.height ? 1400 : null,
      height: photo.height > photo.width ? 1400 : null,
    );
  }
  final pixels = Int32List(photo.width * photo.height);
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      final p = photo.getPixel(x, y);
      pixels[y * photo.width + x] =
          (255 << 24) | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
  }
  return QRCodeReader()
      .decode(
        BinaryBitmap(
          HybridBinarizer(
            RGBLuminanceSource(photo.width, photo.height, pixels),
          ),
        ),
      )
      .text;
}

class ConnectorPairingPage extends StatefulWidget {
  const ConnectorPairingPage({super.key, required this.state});
  final AppState state;
  @override
  State<ConnectorPairingPage> createState() => _ConnectorPairingPageState();
}

class _ConnectorPairingPageState extends State<ConnectorPairingPage> {
  final _text = TextEditingController();
  ConnectorPairing? _pair;
  String? _error;
  bool _busy = false;
  void _preview() {
    try {
      final p = ConnectorPairing.parse(_text.text);
      setState(() {
        _pair = p;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _pair = null;
        _error = '配对信息无效或已过期，请在电脑重新生成二维码';
      });
    }
  }

  Future<void> _photo(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (photo == null) return;
      final value = await compute(decodeConnectorQr, await photo.readAsBytes());
      if (!mounted) return;
      _text.text = value;
      _preview();
    } catch (_) {
      if (mounted) setState(() => _error = '未识别到配对二维码，请重新拍摄、选择清晰图片或粘贴配对链接');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final p = _pair;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final computer = await p.claim();
      await widget.state.activatePairedComputer(computer);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = '连接失败：请确认电脑在线、二维码未使用且证书未更换。若已保存配对，可在连接中心重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state.pairedComputer;
    return Scaffold(
      appBar: AppBar(title: const Text('连接我的电脑')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('电脑打开“xHarness 电脑连接器”生成配对码。可以保存多台电脑，添加新电脑会保留其他电脑。'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _photo(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍摄配对码'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('从相册识别'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '配对链接或配对文件内容',
              hintText: 'xharness://pair?...',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _preview,
            child: const Text('检查配对信息'),
          ),
          if (_pair case final p?) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(p.endpoint),
                    const SizedBox(height: 8),
                    Text('证书指纹：${p.fingerprint.substring(0, 16)}…'),
                    const SizedBox(height: 8),
                    const Text('请确认这是您电脑刚生成的二维码。确认后，这台手机将能够查看工作区并发起电脑任务。'),
                  ],
                ),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? '正在配对…' : '确认并连接'),
            ),
          ],
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.state.savedPairedComputers.isNotEmpty) ...[
            const Divider(height: 40),
            const Text('已保存的电脑'),
            for (final computer in widget.state.savedPairedComputers)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${computer.name}${computer.nodeId == active?.nodeId ? ' · 当前电脑' : ''}',
                      ),
                      Text(computer.remoteUrl == null ? '仅配置局域网' : '局域网与公网已配置'),
                      Wrap(
                        children: [
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      await widget.state.activatePairedComputer(
                                        computer,
                                      );
                                      if (mounted) setState(() {});
                                    } catch (_) {
                                      if (mounted) {
                                        setState(
                                          () => _error = '暂时无法连接，电脑和密钥仍已保存',
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: Text(
                              computer.nodeId == active?.nodeId
                                  ? '重试连接'
                                  : '切换到此电脑',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: Text('忘记 ${computer.name}？'),
                                        content: const Text(
                                          '只移除这台电脑在手机上的配对，其他电脑会保留。要撤销手机访问权限，请同时在对应电脑连接器中撤销此手机。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('忘记'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await widget.state.forgetPairedComputer(
                                        nodeId: computer.nodeId,
                                      );
                                      if (mounted) setState(() {});
                                    }
                                  },
                            child: const Text('忘记此电脑'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
