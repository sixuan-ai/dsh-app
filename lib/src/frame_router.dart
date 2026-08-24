/// Pure classification of host and session-mux downlink payloads.
library;

sealed class HostFrameAction {
  const HostFrameAction();
}

class HostSessionAdded extends HostFrameAction {
  const HostSessionAdded({
    required this.sessionId,
    required this.isSubagent,
    required this.blank,
    this.cwd,
  });

  final String sessionId;
  final bool isSubagent;
  final bool blank;
  final String? cwd;
}

class HostSessionRemoved extends HostFrameAction {
  const HostSessionRemoved(this.sessionId);
  final String sessionId;
}

class HostSessionStatus extends HostFrameAction {
  const HostSessionStatus({required this.sessionId, required this.running});
  final String sessionId;
  final bool running;
}

class HostAgentError extends HostFrameAction {
  const HostAgentError({required this.sessionId, required this.message});
  final String sessionId;
  final String message;
}

HostFrameAction? routeHostFrame(Map<String, dynamic> payload) {
  switch (payload['type']) {
    case 'host/session-added':
      final projections = (payload['projections'] as Map?)?['values'] as Map?;
      return HostSessionAdded(
        sessionId: payload['sessionId'] as String,
        isSubagent:
            payload['origin'] == 'subagent' || projections?['subagent'] != null,
        blank: payload['blank'] == true,
        cwd: payload['cwd'] as String?,
      );
    case 'host/session-removed':
      return HostSessionRemoved(payload['sessionId'] as String);
    case 'host/session-status':
      return HostSessionStatus(
        sessionId: payload['sessionId'] as String,
        running: payload['running'] == true,
      );
    case 'host/agent-error':
      return HostAgentError(
        sessionId: payload['sessionId'] as String,
        message: payload['message'] as String? ?? '未知错误',
      );
    default:
      return null;
  }
}

sealed class MuxFrameAction {
  const MuxFrameAction(this.sessionId);
  final String? sessionId;
}

class MuxSubscribed extends MuxFrameAction {
  const MuxSubscribed(super.sessionId, this.lastSeq);
  final int lastSeq;
}

class MuxSessionEvent extends MuxFrameAction {
  const MuxSessionEvent(super.sessionId, this.event);
  final Map<String, dynamic> event;
}

class MuxProjection extends MuxFrameAction {
  const MuxProjection(
    super.sessionId, {
    required this.key,
    required this.seq,
    required this.value,
  });
  final String key;
  final int seq;
  final dynamic value;
}

class MuxApprovalRequested extends MuxFrameAction {
  const MuxApprovalRequested(
    super.sessionId, {
    required this.approvalId,
    required this.toolName,
    this.reason,
  });
  final String approvalId;
  final String toolName;
  final String? reason;
}

class MuxApprovalResolved extends MuxFrameAction {
  const MuxApprovalResolved(super.sessionId, this.approvalId);
  final String approvalId;
}

class MuxQuestionRequested extends MuxFrameAction {
  const MuxQuestionRequested(super.sessionId, this.questions);
  final List<Map<String, dynamic>> questions;
}

class MuxQuestionResolved extends MuxFrameAction {
  const MuxQuestionResolved(super.sessionId, this.questionRpcId);
  final String questionRpcId;
}

class MuxQueueSnapshot extends MuxFrameAction {
  const MuxQueueSnapshot(super.sessionId, this.items);
  final Object? items;
}

MuxFrameAction? routeMuxFrame(Map<String, dynamic> payload) {
  final sessionId = payload['sessionId'] as String?;
  switch (payload['type']) {
    case 'session/subscribed':
      return MuxSubscribed(
        sessionId,
        (payload['lastSeq'] as num?)?.toInt() ?? -1,
      );
    case 'session/event':
      return MuxSessionEvent(
        sessionId,
        (payload['event'] as Map).cast<String, dynamic>(),
      );
    case 'session/projection':
      return MuxProjection(
        sessionId,
        key: payload['key'] as String? ?? '',
        seq: (payload['seq'] as num?)?.toInt() ?? 0,
        value: payload['value'],
      );
    case 'approval/requested':
      return MuxApprovalRequested(
        sessionId,
        approvalId: payload['approvalId'] as String,
        toolName: payload['toolName'] as String,
        reason: payload['reason'] as String?,
      );
    case 'approval/resolved':
      return MuxApprovalResolved(sessionId, payload['approvalId'] as String);
    case 'question/requested':
      return MuxQuestionRequested(
        sessionId,
        (payload['questions'] as List).cast<Map<String, dynamic>>(),
      );
    case 'question/resolved':
      return MuxQuestionResolved(sessionId, payload['questionRpcId'] as String);
    case 'session/queue':
      return MuxQueueSnapshot(sessionId, payload['items']);
    default:
      return null;
  }
}
