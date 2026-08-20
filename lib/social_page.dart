/// Community pages: feed with level sharing, friends with 8-digit codes and
/// level ranking, and private chat.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_lib;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/social.dart';
import 'state.dart';

const _kBrandGradient = LinearGradient(
  colors: [Color(0xFF4D6BFE), Color(0xFF7C5CFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

String _ago(int millis) {
  if (millis <= 0) return '';
  final diff =
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Letter avatar with a hash-stable tint; shows the uploaded image when
/// [imageUrl] is given and falls back to the letter on load failure.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.size = 36,
    this.imageUrl,
    this.headers,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;

  static const _colors = [
    Color(0xFF4D6BFE),
    Color(0xFF7C5CFF),
    Color(0xFF2EA44F),
    Color(0xFFD29922),
    Color(0xFFDB61A2),
    Color(0xFF39C5CF),
  ];

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: headers,
          errorBuilder: (_, _, _) => _letter(),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _letter(),
        ),
      );
    }
    return _letter();
  }

  Widget _letter() {
    final tint = _colors[name.hashCode.abs() % _colors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: tint.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
            color: tint,
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Community home: 动态 / 好友 / 消息.
class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.state,
    required this.socialBaseUrl,
  });

  final AppState state;
  final String socialBaseUrl;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late final SocialApi _api = SocialApi(
    baseUrl: widget.socialBaseUrl,
    basicUser: widget.state.authUsername,
    basicPass: widget.state.authPassword,
  );
  SocialUser? _me;
  bool _booting = true;
  String? _bootError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _api.token = prefs.getString('socialToken');
      if (_api.token == null) {
        final nickname = await _askNickname();
        if (nickname == null) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        final json = await _api.register(nickname);
        await prefs.setString('socialToken', _api.token!);
        _me = SocialUser.fromJson(json);
      } else {
        _me = await _api.me();
      }
      // Report the local level so friends' rankings see fresh numbers.
      unawaited(_api.uploadStats(widget.state.userLevel.count));
      await _cacheProfile();
    } on SocialError catch (error) {
      // A stale token (server reset) falls back to re-registration.
      if (error.message.contains('token')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('socialToken');
        _api.token = null;
        return _bootstrap();
      }
      _bootError = error.message;
    } catch (error) {
      _bootError = error.toString();
    }
    if (mounted) setState(() => _booting = false);
  }

  /// Persists the profile (with token) so the main drawer can show the
  /// avatar and nickname without entering the community first.
  Future<void> _cacheProfile() async {
    final me = _me;
    final token = _api.token;
    if (me == null || token == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'socialProfile',
        jsonEncode({
          'userId': me.userId,
          'nickname': me.nickname,
          'level': me.level,
          'title': me.title,
          'avatarVer': me.avatarVer,
          'token': token,
        }));
  }

  Future<String?> _askNickname() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加入社区'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置你的昵称,系统会为你分配一个 8 位好友码,朋友凭它添加你。',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              decoration: const InputDecoration(hintText: '昵称'),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('进入社区'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('社区')),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : _bootError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载失败: $_bootError',
                          style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _bootstrap, child: const Text('重试')),
                    ],
                  ),
                )
              : switch (_tab) {
                  1 => FriendsTab(
                      api: _api,
                      me: _me!,
                      onChanged: () async {
                        try {
                          final me = await _api.me();
                          if (mounted) setState(() => _me = me);
                          await _cacheProfile();
                        } catch (_) {}
                      },
                    ),
                  2 => MessagesTab(api: _api, me: _me!),
                  _ => FeedTab(api: _api, state: widget.state),
                },
      bottomNavigationBar: _booting || _bootError != null
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.dynamic_feed_outlined),
                    selectedIcon: Icon(Icons.dynamic_feed),
                    label: '动态'),
                NavigationDestination(
                    icon: Icon(Icons.emoji_events_outlined),
                    selectedIcon: Icon(Icons.emoji_events),
                    label: '好友'),
                NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: '消息'),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed
// ---------------------------------------------------------------------------

class FeedTab extends StatefulWidget {
  const FeedTab({super.key, required this.api, required this.state});

  final SocialApi api;
  final AppState state;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab>
    with AutomaticKeepAliveClientMixin {
  final List<Post> _posts = [];
  final TextEditingController _composer = TextEditingController();
  bool _loading = true;
  bool _hasMore = false;
  bool _posting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.api.posts();
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_posts.isEmpty) return;
    final page = await widget.api.posts(before: _posts.last.id);
    if (!mounted) return;
    setState(() {
      _posts.addAll(page.items);
      _hasMore = page.hasMore;
    });
  }

  Future<void> _publish({bool shareLevel = false}) async {
    final text = _composer.text.trim();
    if (!shareLevel && text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await widget.api.createPost(text, shareLevel: shareLevel);
      _composer.clear();
      await _refresh();
    } on SocialError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final level = widget.state.userLevel;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF171D2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '分享点什么…',
                  hintStyle: TextStyle(color: Colors.white30),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.military_tech,
                        size: 16, color: Colors.amber),
                    label: Text('分享等级 Lv.${level.level}',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: _posting ? null : () => _publish(shareLevel: true),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _posting ? null : _publish,
                    child: _posting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('发布'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: _posts.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                                child: Text('还没有动态,来发第一条吧',
                                    style:
                                        TextStyle(color: Colors.white38))),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _posts.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _posts.length) {
                              return TextButton(
                                onPressed: _loadMore,
                                child: const Text('加载更多'),
                              );
                            }
                            return _PostCard(
                              post: _posts[index],
                              api: widget.api,
                              onDeleted: _refresh,
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

class _PostCard extends StatefulWidget {
  const _PostCard(
      {required this.post, required this.api, required this.onDeleted});

  final Post post;
  final SocialApi api;
  final VoidCallback onDeleted;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  Future<void> _like() async {
    // Optimistic toggle; the server answer reconciles the count.
    setState(() {
      widget.post.liked = !widget.post.liked;
      widget.post.likes += widget.post.liked ? 1 : -1;
    });
    try {
      await widget.api.toggleLike(widget.post);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final levelInfo = post.levelInfo;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171D2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                name: post.nickname,
                imageUrl: post.avatarVer > 0
                    ? widget.api.avatarUrl(post.userId, post.avatarVer)
                    : null,
                headers: widget.api.imageHeaders,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.nickname,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    Text(_ago(post.time),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
              if (post.mine)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.white30),
                  onPressed: () async {
                    await widget.api.deletePost(post.id);
                    widget.onDeleted();
                  },
                ),
            ],
          ),
          if (levelInfo != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: _kBrandGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.military_tech,
                      color: Colors.amber, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lv.${levelInfo['level']} · ${levelInfo['title']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        Text('累计 ${levelInfo['count']} 次对话',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(post.text, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: _like,
                icon: Icon(
                  post.liked ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: post.liked ? Colors.redAccent : Colors.white38,
                ),
              ),
              Text('${post.likes}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white54)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friends & ranking
// ---------------------------------------------------------------------------

class FriendsTab extends StatefulWidget {
  const FriendsTab(
      {super.key,
      required this.api,
      required this.me,
      required this.onChanged});

  final SocialApi api;
  final SocialUser me;
  final VoidCallback onChanged;

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab>
    with AutomaticKeepAliveClientMixin {
  List<SocialUser> _friends = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.api.friends();
      if (!mounted) return;
      setState(() {
        _friends = page.items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加好友'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '输入 8 位好友码'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (code == null || code.length != 8) return;
    try {
      final friend = await widget.api.addFriend(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加好友: ${friend.nickname}')));
      _refresh();
    } on SocialError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _changeAvatar() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择头像'),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('恢复默认字母头像'),
              onTap: () => Navigator.of(sheetContext).pop('clear'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'pick') {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 90,
        );
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        final cropped = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
              builder: (_) => AvatarCropPage(bytes: bytes)),
        );
        if (cropped == null) return;
        if (cropped.length > 400 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('图片过大,请换一张')));
          }
          return;
        }
        await widget.api.uploadAvatar(base64Encode(cropped), 'image/jpeg');
      } else {
        await widget.api.clearAvatar();
      }
      widget.onChanged();
      await _refresh();
    } on SocialError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.me.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.api.rename(name);
      widget.onChanged();
      if (mounted) setState(() {});
    } on SocialError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final me = widget.me;
    final ranked = [..._friends, me]
      ..sort((a, b) => b.promptCount.compareTo(a.promptCount));
    final code = me.friendCode ?? '';
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: _kBrandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _changeAvatar,
                      child: Stack(
                        children: [
                          _Avatar(
                            name: me.nickname,
                            size: 44,
                            imageUrl: me.avatarVer > 0
                                ? widget.api
                                    .avatarUrl(me.userId, me.avatarVer)
                                : null,
                            headers: widget.api.imageHeaders,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.photo_camera,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me.nickname,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          Text('Lv.${me.level} · ${me.title}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '修改昵称',
                      icon: const Icon(Icons.edit_outlined,
                          color: Colors.white70, size: 18),
                      onPressed: _rename,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('好友码已复制')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          code.length == 8
                              ? '${code.substring(0, 4)} ${code.substring(4)}'
                              : code,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              letterSpacing: 4,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy,
                            size: 16, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('这是我的好友码,点按复制',
                    style:
                        TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _addFriend,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('输入好友码添加好友'),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.emoji_events_outlined,
                  size: 16, color: Colors.amber),
              SizedBox(width: 6),
              Text('等级排名',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (var i = 0; i < ranked.length; i++)
              _rankTile(ranked[i], i + 1, ranked[i].userId == me.userId,
                  ranked.first.promptCount),
        ],
      ),
    );
  }

  Widget _rankTile(SocialUser user, int rank, bool isMe, int topCount) {
    final medal = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFFFAB91),
      _ => Colors.white24,
    };
    final ratio = topCount > 0 ? user.promptCount / topCount : 0.0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                child: rank <= 3
                    ? Icon(Icons.emoji_events, size: 20, color: medal)
                    : Text('$rank',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38)),
              ),
              _Avatar(
                name: user.nickname,
                size: 32,
                imageUrl: user.avatarVer > 0
                    ? widget.api.avatarUrl(user.userId, user.avatarVer)
                    : null,
                headers: widget.api.imageHeaders,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${user.nickname}${isMe ? ' (我)' : ''}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Lv.${user.level} · ${user.title}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white54)),
                  ],
                ),
              ),
              Text('${user.promptCount} 次',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.02, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(
                  isMe ? const Color(0xFF4D6BFE) : Colors.white24),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key, required this.api, required this.me});

  final SocialApi api;
  final SocialUser me;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab>
    with AutomaticKeepAliveClientMixin {
  List<Conversation> _items = [];
  bool _loading = true;
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final items = await widget.api.conversations();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return const Center(
        child: Text('还没有私聊,先去好友页添加好友吧',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final c = _items[index];
          return ListTile(
            leading: _Avatar(
              name: c.nickname,
              imageUrl: c.avatarVer > 0
                  ? widget.api.avatarUrl(c.userId, c.avatarVer)
                  : null,
              headers: widget.api.imageHeaders,
            ),
            title: Text(c.nickname),
            subtitle: Text(c.lastText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_ago(c.lastTime),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white38)),
                if (c.unread > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('${c.unread}',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white)),
                  ),
              ],
            ),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => FriendChatPage(
                    api: widget.api, me: widget.me, peer: c),
              ));
              _refresh();
            },
          );
        },
      ),
    );
  }
}

/// One-to-one chat page; polls for new messages while open.
class FriendChatPage extends StatefulWidget {
  const FriendChatPage({
    super.key,
    required this.api,
    required this.me,
    required this.peer,
  });

  final SocialApi api;
  final SocialUser me;
  final Conversation peer;

  @override
  State<FriendChatPage> createState() => _FriendChatPageState();
}

class _FriendChatPageState extends State<FriendChatPage> {
  final List<SocialMessage> _messages = [];
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  int get _lastId => _messages.isEmpty ? 0 : _messages.last.id;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer =
        Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final incoming =
          await widget.api.messages(widget.peer.userId, after: _lastId);
      if (!mounted || incoming.isEmpty) return;
      setState(() => _messages.addAll(incoming));
      unawaited(widget.api.markRead(widget.peer.userId, _lastId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendMessage(widget.peer.userId, text);
      _composer.clear();
      await _poll();
    } on SocialError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.peer.nickname)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('打个招呼吧',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final mine = m.fromId == widget.me.userId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            gradient: mine ? _kBrandGradient : null,
                            color: mine
                                ? null
                                : Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(mine ? 16 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 16),
                            ),
                          ),
                          child: Text(m.text,
                              style: const TextStyle(height: 1.4)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: '发消息…',
                        hintStyle:
                            const TextStyle(color: Colors.white30),
                        isDense: true,
                        filled: true,
                        fillColor:
                            Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Ink(
                    decoration: const BoxDecoration(
                        gradient: _kBrandGradient,
                        shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar crop
// ---------------------------------------------------------------------------

/// Square crop page for avatar picks: pan + pinch to choose the visible
/// region, exported as a 448×448 JPEG. Pure Dart (image package), so the
/// crop behavior is identical on Android and iOS.
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}
class _AvatarCropPageState extends State<AvatarCropPage> {
  img_lib.Image? _image;
  Uint8List? _displayBytes;
  double _viewport = 0;
  double _coverScale = 1;

  /// The single source of truth for the transform: the image renders at
  /// natural size scaled by [_scale] and shifted by [_offset] (viewport
  /// pixels). The export crops exactly the inverse mapping.
  double _scale = 1;
  Offset _offset = Offset.zero;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final decoded = img_lib.decodeImage(widget.bytes);
    if (decoded != null) {
      // Bake EXIF orientation so display and export see the same pixels.
      _image = img_lib.bakeOrientation(decoded);
      _displayBytes =
          Uint8List.fromList(img_lib.encodeJpg(_image!, quality: 92));
    }
  }

  void _initTransform() {
    final image = _image!;
    _coverScale =
        math.max(_viewport / image.width, _viewport / image.height);
    _scale = _coverScale;
    _offset = Offset(
      (_viewport - image.width * _scale) / 2,
      (_viewport - image.height * _scale) / 2,
    );
  }

  /// The image must always cover the whole square: no empty edges.
  void _clamp() {
    final image = _image!;
    final minDx = math.min(0.0, _viewport - image.width * _scale);
    final minDy = math.min(0.0, _viewport - image.height * _scale);
    _offset = Offset(
      _offset.dx.clamp(minDx, 0.0),
      _offset.dy.clamp(minDy, 0.0),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final image = _image;
    if (image == null) return;
    setState(() {
      if (details.scale != 1.0) {
        // Pinch: zoom about the focal point so it stays under the fingers.
        final newScale =
            (_scale * details.scale).clamp(_coverScale, _coverScale * 5);
        final ratio = newScale / _scale;
        final focal = details.localFocalPoint;
        _offset = focal - (focal - _offset) * ratio;
        _scale = newScale;
      } else {
        _offset += details.focalPointDelta;
      }
      _clamp();
    });
  }

  void _reset() => setState(_initTransform);

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _exporting) return;
    setState(() => _exporting = true);
    // Render maps child pixel p to viewport v = p * scale + offset, so the
    // visible square [0, viewport] is the inverse region below.
    final left =
        (-_offset.dx / _scale).clamp(0.0, image.width.toDouble() - 1);
    final top =
        (-_offset.dy / _scale).clamp(0.0, image.height.toDouble() - 1);
    final side = math.min(
      _viewport / _scale,
      math.min(image.width - left, image.height - top),
    );
    final cropped = img_lib.copyCrop(
      image,
      x: left.round(),
      y: top.round(),
      width: side.round(),
      height: side.round(),
    );
    final resized = img_lib.copyResize(
      cropped,
      width: 448,
      height: 448,
      interpolation: img_lib.Interpolation.cubic,
    );
    final jpg = img_lib.encodeJpg(resized, quality: 85);
    if (!mounted) return;
    Navigator.of(context).pop(Uint8List.fromList(jpg));
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayBytes;
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('调整头像'),
        actions: [
          IconButton(
            tooltip: '复位',
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
          ),
          TextButton(
            onPressed: _exporting ? null : _confirm,
            child: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('确定',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: display == null || image == null
          ? const Center(child: Text('图片无法解析'))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = math.min(constraints.maxWidth,
                            constraints.maxHeight);
                        if (_viewport != side) {
                          _viewport = side;
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            if (mounted && _scale == 1) {
                              setState(_initTransform);
                            }
                          });
                        }
                        return Container(
                          key: const Key('avatar-crop-viewport'),
                          width: side,
                          height: side,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white54, width: 1.5),
                          ),
                          child: ClipRect(
                            child: GestureDetector(
                              onScaleStart: (_) {},
                              onScaleUpdate: _onScaleUpdate,
                              child: Stack(
                                children: [
                                  Transform(
                                    transform: Matrix4.identity()
                                      ..setTranslationRaw(_offset.dx,
                                          _offset.dy, 0)
                                      ..scaleByDouble(
                                          _scale, _scale, 1.0, 1.0),
                                    child: Image.memory(
                                      display,
                                      width: image.width.toDouble(),
                                      height: image.height.toDouble(),
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '缩放 ${(_scale / _coverScale * 100).round()}% · 拖动/双指缩放调整',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }
}
