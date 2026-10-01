/// Directory listing model for the host browse RPC (`host.listDirectory`).
library;

/// One directory row: a listing child or a breadcrumb ancestor.
class DirectoryEntryView {
  const DirectoryEntryView({
    required this.name,
    required this.path,
    required this.hidden,
  });

  factory DirectoryEntryView.fromJson(Map<String, dynamic> json) =>
      DirectoryEntryView(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        hidden: json['hidden'] == true,
      );

  /// Base name shown in a browser row (a root crumb carries its full path).
  final String name;

  /// Absolute host path — clients never join path segments themselves.
  final String path;

  /// Hidden by the host platform's convention; the client owns display.
  final bool hidden;
}

/// One directory level plus its ancestry, as the host browse backend reports.
class DirectoryListingView {
  const DirectoryListingView({
    required this.path,
    required this.home,
    required this.crumbs,
    required this.entries,
    required this.truncated,
  });

  factory DirectoryListingView.fromJson(Map<String, dynamic> json) =>
      DirectoryListingView(
        path: json['path'] as String? ?? '',
        home: json['home'] as String? ?? '',
        crumbs: [
          for (final entry in (json['crumbs'] as List?) ?? const [])
            DirectoryEntryView.fromJson((entry as Map).cast<String, dynamic>()),
        ],
        entries: [
          for (final entry in (json['entries'] as List?) ?? const [])
            DirectoryEntryView.fromJson((entry as Map).cast<String, dynamic>()),
        ],
        truncated: json['truncated'] == true,
      );

  /// Absolute path of the listed directory.
  final String path;

  /// The host account's home directory.
  final String home;

  /// Ancestor chain from the filesystem root to the listed directory.
  final List<DirectoryEntryView> crumbs;

  /// Direct child directories, name-sorted by the host.
  final List<DirectoryEntryView> entries;

  /// True when the host cut `entries` at its complete-result bound.
  final bool truncated;
}
