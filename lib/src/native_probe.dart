/// Formats one Android-native DSH probe result for the connection snackbar.
String formatNativeProbeResult(Map<String, dynamic> result) {
  final elapsedMs = result['elapsedMs'];
  final elapsed = elapsedMs == null ? '' : '（${elapsedMs}ms）';
  if (result['ok'] == true) {
    return '原生 OkHttp 探测成功$elapsed，Dart TLS 失败';
  }
  final errorType = result['errorType'];
  final error = result['error'];
  final typePrefix = errorType == null ? '' : '$errorType: ';
  return '原生 OkHttp 也失败$elapsed：$typePrefix${error ?? '未知错误'}';
}
