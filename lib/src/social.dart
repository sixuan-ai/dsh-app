/// Client for the DSH App social backend (friends, ranking, private
/// messages, community posts). Transport is plain HTTP under the same Basic
/// credentials as the DSH connection; in-app identity rides the
/// x-social-token header issued at registration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Server-side failure with a user-facing message.
class SocialError implements Exception {
  SocialError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A user row as the server projects it.
class SocialUser {
  SocialUser({
    required this.userId,
    required this.nickname,
    required this.promptCount,
    required this.level,
    required this.title,
    this.friendCode,
    this.avatarVer = 0,
  });

  factory SocialUser.fromJson(Map<String, dynamic> json) => SocialUser(
        userId: json['userId'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        promptCount: (json['promptCount'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 1,
        title: json['title'] as String? ?? '',
        friendCode: json['friendCode'] as String?,
        avatarVer: (json['avatarVer'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String nickname;
  final int promptCount;
  final int level;
  final String title;
  final String? friendCode;

  /// Avatar content version (0 = default letter avatar); the avatar URL
  /// embeds it so clients can long-cache.
  final int avatarVer;
}

/// One conversation row in the message list.
class Conversation {
  Conversation({
    required this.userId,
    required this.nickname,
    required this.lastText,
    required this.lastTime,
    required this.unread,
    this.avatarVer = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        userId: json['userId'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        lastText: json['lastText'] as String? ?? '',
        lastTime: (json['lastTime'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        avatarVer: (json['avatarVer'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String nickname;
  final String lastText;
  final int lastTime;
  final int unread;
  final int avatarVer;
}

/// One private message.
class SocialMessage {
  SocialMessage({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.text,
    required this.time,
  });

  factory SocialMessage.fromJson(Map<String, dynamic> json) => SocialMessage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        fromId: json['fromId'] as String? ?? '',
        toId: json['toId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        time: (json['time'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String fromId;
  final String toId;
  final String text;
  final int time;
}

/// One community post.
class Post {
  Post({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.kind,
    required this.text,
    required this.likes,
    required this.liked,
    required this.mine,
    required this.time,
    this.levelInfo,
    this.avatarVer = 0,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: json['userId'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        kind: json['kind'] as String? ?? 'text',
        text: json['text'] as String? ?? '',
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        liked: json['liked'] == true,
        mine: json['mine'] == true,
        time: (json['time'] as num?)?.toInt() ?? 0,
        levelInfo:
            (json['levelInfo'] as Map?)?.cast<String, dynamic>(),
        avatarVer: (json['avatarVer'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String userId;
  final String nickname;
  final String kind; // 'text' | 'level'
  final String text;
  int likes;
  bool liked;
  final bool mine;
  final int time;
  final Map<String, dynamic>? levelInfo;
  final int avatarVer;
}

/// Friends endpoint result: own profile plus the ranking rows.
class FriendsPage {
  FriendsPage({required this.me, required this.items});
  final SocialUser me;
  final List<SocialUser> items;
}

/// Posts endpoint result page.
class PostsPage {
  PostsPage({required this.items, required this.hasMore});
  final List<Post> items;
  final bool hasMore;
}

/// Thin HTTP client for the social endpoints.
class SocialApi {
  SocialApi({
    required this.baseUrl,
    this.basicUser,
    this.basicPass,
    this.token,
  });

  /// e.g. https://dsh.example.com/social
  final String baseUrl;
  final String? basicUser;
  final String? basicPass;

  /// In-app identity token from register(); persisted by the caller.
  String? token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (basicUser != null && basicUser!.isNotEmpty)
          'authorization':
              'Basic ${base64Encode(utf8.encode('$basicUser:${basicPass ?? ''}'))}',
        if (token != null) 'x-social-token': ?token,
      };

  Future<Map<String, dynamic>> _request(
      String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await switch (method) {
      'GET' => http.get(uri, headers: _headers),
      _ => http.post(uri, headers: _headers, body: jsonEncode(body ?? {})),
    }
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw SocialError('服务异常 (HTTP ${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw SocialError(json['error'] as String? ?? 'HTTP ${response.statusCode}');
    }
    return json;
  }

  /// Registers a new identity; returns the profile including the token.
  Future<Map<String, dynamic>> register(String nickname) async {
    final json = await _request('POST', '/register', {'nickname': nickname});
    token = json['token'] as String?;
    return json;
  }

  Future<SocialUser> me() async =>
      SocialUser.fromJson(await _request('GET', '/me'));

  Future<void> uploadStats(int promptCount) =>
      _request('POST', '/me/stats', {'promptCount': promptCount});

  Future<void> rename(String nickname) =>
      _request('POST', '/me/nickname', {'nickname': nickname});

  /// Uploads a custom avatar (base64 image ≤ 400KB, jpeg/png/webp).
  Future<int> uploadAvatar(String base64Data, String mime) async =>
      ((await _request('POST', '/me/avatar', {'data': base64Data, 'mime': mime}))
              ['avatarVer'] as num?)
          ?.toInt() ??
      0;

  /// Clears the custom avatar, restoring the letter default.
  Future<void> clearAvatar() => _request('POST', '/me/avatar', {'data': ''});

  /// Avatar image URL for a user; [ver] is the content version (0 = none).
  String avatarUrl(String userId, int ver) =>
      '$baseUrl/avatar?userId=$userId&v=$ver';

  /// Headers (Basic + token) for Image.network avatar loads.
  Map<String, String> get imageHeaders => _headers;

  Future<SocialUser> addFriend(String friendCode) async => SocialUser.fromJson(
      (await _request('POST', '/friends/add', {'friendCode': friendCode}))['friend']
          as Map<String, dynamic>);

  Future<void> removeFriend(String userId) =>
      _request('POST', '/friends/remove', {'userId': userId});

  Future<FriendsPage> friends() async {
    final json = await _request('GET', '/friends');
    return FriendsPage(
      me: SocialUser.fromJson(json['me'] as Map<String, dynamic>),
      items: [
        for (final item in (json['items'] as List? ?? const []))
          SocialUser.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  Future<List<Conversation>> conversations() async {
    final json = await _request('GET', '/conversations');
    return [
      for (final item in (json['items'] as List? ?? const []))
        Conversation.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<SocialMessage>> messages(String peer, {int after = 0}) async {
    final json = await _request('GET', '/messages?peer=$peer&after=$after');
    return [
      for (final item in (json['items'] as List? ?? const []))
        SocialMessage.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<int> sendMessage(String to, String text) async =>
      (await _request('POST', '/messages', {'to': to, 'text': text}))['id']
          as int;

  Future<void> markRead(String peer, int lastId) =>
      _request('POST', '/messages/read', {'peer': peer, 'lastId': lastId});

  Future<PostsPage> posts({int before = 0, int limit = 20}) async {
    final json =
        await _request('GET', '/posts?before=$before&limit=$limit');
    return PostsPage(
      items: [
        for (final item in (json['items'] as List? ?? const []))
          Post.fromJson((item as Map).cast<String, dynamic>()),
      ],
      hasMore: json['hasMore'] == true,
    );
  }

  Future<int> createPost(String text, {bool shareLevel = false}) async =>
      (await _request('POST', '/posts', {
        'text': text,
        if (shareLevel) 'kind': 'level',
      }))['id'] as int;

  Future<void> toggleLike(Post post) async {
    final json = await _request('POST', '/posts/like', {'id': post.id});
    post
      ..likes = (json['likes'] as num?)?.toInt() ?? post.likes
      ..liked = json['liked'] == true;
  }

  Future<void> deletePost(int id) =>
      _request('POST', '/posts/delete', {'id': id});
}
