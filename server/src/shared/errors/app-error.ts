// ─────────────────────────────────────
// 에러 코드 정의
// ─────────────────────────────────────

export enum ErrorCode {
  // 인증 (AUTH_)
  AUTH_MISSING_TOKEN = 'AUTH_001',
  AUTH_INVALID_TOKEN = 'AUTH_002',
  AUTH_EXPIRED_TOKEN = 'AUTH_003',
  AUTH_REFRESH_INVALID = 'AUTH_004',
  AUTH_KAKAO_FAILED = 'AUTH_005',
  AUTH_UNAUTHORIZED = 'AUTH_006',
  AUTH_FORBIDDEN = 'AUTH_007',
  AUTH_GOOGLE_FAILED = 'AUTH_008',
  AUTH_APPLE_FAILED = 'AUTH_009',

  // 사용자 (USER_)
  USER_NOT_FOUND = 'USER_001',
  USER_NICKNAME_TAKEN = 'USER_002',
  USER_SUSPENDED = 'USER_003',
  USER_WITHDRAWN = 'USER_004',
  USER_ALREADY_EXISTS = 'USER_005',

  // 스포츠 프로필 (PROFILE_)
  PROFILE_NOT_FOUND = 'PROFILE_001',
  PROFILE_ALREADY_EXISTS = 'PROFILE_002',
  PROFILE_INVALID_HANDICAP = 'PROFILE_003',

  // 매칭 (MATCH_)
  MATCH_REQUEST_NOT_FOUND = 'MATCH_001',
  MATCH_NOT_FOUND = 'MATCH_002',
  MATCH_ALREADY_EXISTS = 'MATCH_003',
  MATCH_INVALID_STATUS = 'MATCH_004',
  MATCH_NOT_PARTICIPANT = 'MATCH_005',
  MATCH_CANCEL_TOO_LATE = 'MATCH_006',
  MATCH_SCORE_RANGE_INVALID = 'MATCH_007',
  MATCH_RADIUS_INVALID = 'MATCH_008',
  MATCH_REJECTION_COOLDOWN = 'MATCH_009',
  MATCH_ACCEPT_EXPIRED = 'MATCH_010',
  MATCH_ALREADY_RESPONDED = 'MATCH_011',

  // 경기 (GAME_)
  GAME_NOT_FOUND = 'GAME_001',
  GAME_RESULT_ALREADY_SUBMITTED = 'GAME_002',
  GAME_ALREADY_CONFIRMED = 'GAME_003',
  GAME_ALREADY_DISPUTED = 'GAME_004',
  GAME_DEADLINE_EXCEEDED = 'GAME_005',
  GAME_NOT_PARTICIPANT = 'GAME_006',

  // 채팅 (CHAT_)
  CHAT_ROOM_NOT_FOUND = 'CHAT_001',
  CHAT_NOT_PARTICIPANT = 'CHAT_002',
  CHAT_ROOM_BLOCKED = 'CHAT_003',
  CHAT_MESSAGE_TOO_LONG = 'CHAT_004',

  // 랭킹 (RANK_)
  RANK_PIN_NOT_FOUND = 'RANK_001',

  // 핀 (PIN_)
  PIN_NOT_FOUND = 'PIN_001',
  PIN_NOT_ACTIVE = 'PIN_002',

  // 게시판 (POST_)
  POST_NOT_FOUND = 'POST_001',
  POST_NOT_AUTHOR = 'POST_002',
  POST_CONTENT_TOO_LONG = 'POST_003',
  POST_IMAGE_LIMIT_EXCEEDED = 'POST_004',
  COMMENT_NOT_FOUND = 'COMMENT_001',
  COMMENT_NOT_AUTHOR = 'COMMENT_002',
  COMMENT_DEPTH_EXCEEDED = 'COMMENT_003',

  // 알림 (NOTIF_)
  NOTIFICATION_NOT_FOUND = 'NOTIF_001',

  // 파일 업로드 (UPLOAD_)
  UPLOAD_FILE_TOO_LARGE = 'UPLOAD_001',
  UPLOAD_INVALID_TYPE = 'UPLOAD_002',
  UPLOAD_FAILED = 'UPLOAD_003',

  // 어드민 (ADMIN_)
  ADMIN_ACCESS_DENIED = 'ADMIN_001',
  ADMIN_INVALID_ROLE = 'ADMIN_002',

  // 팀 (TEAM_)
  TEAM_NOT_FOUND = 'TEAM_001',
  TEAM_ALREADY_EXISTS = 'TEAM_002',
  TEAM_NOT_MEMBER = 'TEAM_003',
  TEAM_NOT_CAPTAIN = 'TEAM_004',
  TEAM_FULL = 'TEAM_005',
  TEAM_ALREADY_MEMBER = 'TEAM_006',
  TEAM_DISBANDED = 'TEAM_007',
  TEAM_CAPTAIN_CANNOT_LEAVE = 'TEAM_008',
  TEAM_MATCH_REQUEST_NOT_FOUND = 'TEAM_009',
  TEAM_MATCH_NOT_FOUND = 'TEAM_010',
  TEAM_CHAT_ROOM_NOT_FOUND = 'TEAM_011',
  TEAM_POST_NOT_FOUND = 'TEAM_012',
  TEAM_POST_NOT_AUTHOR = 'TEAM_013',
  TEAM_COMMENT_NOT_FOUND = 'TEAM_014',
  TEAM_COMMENT_NOT_AUTHOR = 'TEAM_015',
  TEAM_INSUFFICIENT_PERMISSION = 'TEAM_016',

  // KCP 본인인증 (KCP_)
  PHONE_NUMBER_BANNED = 'KCP_001',
  KCP_INVALID_KEY = 'KCP_002',
  KCP_KEY_ALREADY_USED = 'KCP_003',
  KCP_SERVER_ERROR = 'KCP_004',
  VERIFICATION_REQUIRED = 'KCP_005',

  // 공통 (COMMON_)
  VALIDATION_ERROR = 'COMMON_001',
  NOT_FOUND = 'COMMON_002',
  INTERNAL_SERVER_ERROR = 'COMMON_003',
  RATE_LIMIT_EXCEEDED = 'COMMON_004',
  BAD_REQUEST = 'COMMON_005',
  CONFLICT = 'COMMON_006',
}

// ─────────────────────────────────────
// AppError 클래스
// ─────────────────────────────────────

export class AppError extends Error {
  public readonly code: ErrorCode;
  public readonly statusCode: number;
  public readonly details?: unknown;

  constructor(code: ErrorCode, statusCode: number, message?: string, details?: unknown) {
    super(message ?? AppError.defaultMessage(code));
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;

    // V8 스택 트레이스 유지
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, AppError);
    }
  }

  private static defaultMessage(code: ErrorCode): string {
    const messages: Record<ErrorCode, string> = {
      [ErrorCode.AUTH_MISSING_TOKEN]: '인증 토큰이 없습니다.',
      [ErrorCode.AUTH_INVALID_TOKEN]: '유효하지 않은 토큰입니다.',
      [ErrorCode.AUTH_EXPIRED_TOKEN]: '토큰이 만료되었습니다.',
      [ErrorCode.AUTH_REFRESH_INVALID]: '리프레시 토큰이 유효하지 않습니다.',
      [ErrorCode.AUTH_KAKAO_FAILED]: '카카오 인증에 실패했습니다.',
      [ErrorCode.AUTH_UNAUTHORIZED]: '인증이 필요합니다.',
      [ErrorCode.AUTH_FORBIDDEN]: '접근 권한이 없습니다.',
      [ErrorCode.AUTH_GOOGLE_FAILED]: 'Google 인증에 실패했습니다.',
      [ErrorCode.AUTH_APPLE_FAILED]: 'Apple 인증에 실패했습니다.',
      [ErrorCode.USER_NOT_FOUND]: '사용자를 찾을 수 없습니다.',
      [ErrorCode.USER_NICKNAME_TAKEN]: '이미 사용 중인 닉네임입니다.',
      [ErrorCode.USER_SUSPENDED]: '정지된 계정입니다.',
      [ErrorCode.USER_WITHDRAWN]: '탈퇴한 계정입니다.',
      [ErrorCode.USER_ALREADY_EXISTS]: '이미 존재하는 사용자입니다.',
      [ErrorCode.PROFILE_NOT_FOUND]: '스포츠 프로필을 찾을 수 없습니다.',
      [ErrorCode.PROFILE_ALREADY_EXISTS]: '해당 종목의 프로필이 이미 존재합니다.',
      [ErrorCode.PROFILE_INVALID_HANDICAP]: '유효하지 않은 핸디캡 값입니다.',
      [ErrorCode.MATCH_REQUEST_NOT_FOUND]: '매칭 요청을 찾을 수 없습니다.',
      [ErrorCode.MATCH_NOT_FOUND]: '매칭을 찾을 수 없습니다.',
      [ErrorCode.MATCH_ALREADY_EXISTS]: '이미 진행 중인 매칭이 있습니다.',
      [ErrorCode.MATCH_INVALID_STATUS]: '현재 상태에서 수행할 수 없는 작업입니다.',
      [ErrorCode.MATCH_NOT_PARTICIPANT]: '해당 매칭의 참여자가 아닙니다.',
      [ErrorCode.MATCH_CANCEL_TOO_LATE]: '경기 24시간 전까지만 취소할 수 있습니다.',
      [ErrorCode.MATCH_SCORE_RANGE_INVALID]: '점수 범위가 올바르지 않습니다.',
      [ErrorCode.MATCH_RADIUS_INVALID]: '매칭 반경은 1km에서 50km 사이여야 합니다.',
      [ErrorCode.MATCH_REJECTION_COOLDOWN]: '거절 쿨다운 중입니다. 잠시 후 다시 시도해 주세요.',
      [ErrorCode.MATCH_ACCEPT_EXPIRED]: '매칭 수락 시간이 만료되었습니다.',
      [ErrorCode.MATCH_ALREADY_RESPONDED]: '이미 응답한 매칭입니다.',
      [ErrorCode.GAME_NOT_FOUND]: '경기를 찾을 수 없습니다.',
      [ErrorCode.GAME_RESULT_ALREADY_SUBMITTED]: '이미 결과가 제출되었습니다.',
      [ErrorCode.GAME_ALREADY_CONFIRMED]: '이미 인증된 경기입니다.',
      [ErrorCode.GAME_ALREADY_DISPUTED]: '이미 이의 신청된 경기입니다.',
      [ErrorCode.GAME_DEADLINE_EXCEEDED]: '결과 입력 기한이 지났습니다.',
      [ErrorCode.GAME_NOT_PARTICIPANT]: '해당 경기의 참여자가 아닙니다.',
      [ErrorCode.CHAT_ROOM_NOT_FOUND]: '채팅방을 찾을 수 없습니다.',
      [ErrorCode.CHAT_NOT_PARTICIPANT]: '해당 채팅방의 참여자가 아닙니다.',
      [ErrorCode.CHAT_ROOM_BLOCKED]: '차단된 채팅방입니다.',
      [ErrorCode.CHAT_MESSAGE_TOO_LONG]: '메시지는 최대 500자까지 입력할 수 있습니다.',
      [ErrorCode.RANK_PIN_NOT_FOUND]: '핀 랭킹을 찾을 수 없습니다.',
      [ErrorCode.PIN_NOT_FOUND]: '핀을 찾을 수 없습니다.',
      [ErrorCode.PIN_NOT_ACTIVE]: '비활성화된 핀입니다.',
      [ErrorCode.POST_NOT_FOUND]: '게시글을 찾을 수 없습니다.',
      [ErrorCode.POST_NOT_AUTHOR]: '게시글 작성자만 수정/삭제할 수 있습니다.',
      [ErrorCode.POST_CONTENT_TOO_LONG]: '게시글은 최대 2000자까지 입력할 수 있습니다.',
      [ErrorCode.POST_IMAGE_LIMIT_EXCEEDED]: '게시글당 최대 5장까지 첨부할 수 있습니다.',
      [ErrorCode.COMMENT_NOT_FOUND]: '댓글을 찾을 수 없습니다.',
      [ErrorCode.COMMENT_NOT_AUTHOR]: '댓글 작성자만 수정/삭제할 수 있습니다.',
      [ErrorCode.COMMENT_DEPTH_EXCEEDED]: '대댓글에는 답글을 달 수 없습니다.',
      [ErrorCode.NOTIFICATION_NOT_FOUND]: '알림을 찾을 수 없습니다.',
      [ErrorCode.UPLOAD_FILE_TOO_LARGE]: '파일 크기가 초과되었습니다.',
      [ErrorCode.UPLOAD_INVALID_TYPE]: '지원하지 않는 파일 형식입니다.',
      [ErrorCode.UPLOAD_FAILED]: '파일 업로드에 실패했습니다.',
      [ErrorCode.ADMIN_ACCESS_DENIED]: '어드민 권한이 필요합니다.',
      [ErrorCode.ADMIN_INVALID_ROLE]: '유효하지 않은 어드민 역할입니다.',
      [ErrorCode.TEAM_NOT_FOUND]: '팀을 찾을 수 없습니다.',
      [ErrorCode.TEAM_ALREADY_EXISTS]: '이미 존재하는 팀입니다.',
      [ErrorCode.TEAM_NOT_MEMBER]: '해당 팀의 멤버가 아닙니다.',
      [ErrorCode.TEAM_NOT_CAPTAIN]: '팀 캡틴만 수행할 수 있는 작업입니다.',
      [ErrorCode.TEAM_FULL]: '팀 정원이 가득 찼습니다.',
      [ErrorCode.TEAM_ALREADY_MEMBER]: '이미 해당 팀의 멤버입니다.',
      [ErrorCode.TEAM_DISBANDED]: '해산된 팀입니다.',
      [ErrorCode.TEAM_CAPTAIN_CANNOT_LEAVE]: '캡틴은 역할을 양도한 후에만 탈퇴할 수 있습니다.',
      [ErrorCode.TEAM_MATCH_REQUEST_NOT_FOUND]: '팀 매칭 요청을 찾을 수 없습니다.',
      [ErrorCode.TEAM_MATCH_NOT_FOUND]: '팀 매칭을 찾을 수 없습니다.',
      [ErrorCode.TEAM_CHAT_ROOM_NOT_FOUND]: '팀 채팅방을 찾을 수 없습니다.',
      [ErrorCode.TEAM_POST_NOT_FOUND]: '팀 게시글을 찾을 수 없습니다.',
      [ErrorCode.TEAM_POST_NOT_AUTHOR]: '게시글 작성자만 수정/삭제할 수 있습니다.',
      [ErrorCode.TEAM_COMMENT_NOT_FOUND]: '팀 댓글을 찾을 수 없습니다.',
      [ErrorCode.TEAM_COMMENT_NOT_AUTHOR]: '댓글 작성자만 삭제할 수 있습니다.',
      [ErrorCode.TEAM_INSUFFICIENT_PERMISSION]: '캡틴 또는 부캡틴만 수행할 수 있는 작업입니다.',
      [ErrorCode.PHONE_NUMBER_BANNED]: '해당 전화번호로는 가입이 불가합니다.',
      [ErrorCode.KCP_INVALID_KEY]: '인증 정보가 유효하지 않습니다. 다시 시도해주세요.',
      [ErrorCode.KCP_KEY_ALREADY_USED]: '이미 처리된 인증입니다.',
      [ErrorCode.KCP_SERVER_ERROR]: '인증 서버와 통신 중 오류가 발생했습니다.',
      [ErrorCode.VERIFICATION_REQUIRED]: '본인인증이 필요합니다.',
      [ErrorCode.VALIDATION_ERROR]: '입력값이 올바르지 않습니다.',
      [ErrorCode.NOT_FOUND]: '요청한 리소스를 찾을 수 없습니다.',
      [ErrorCode.INTERNAL_SERVER_ERROR]: '서버 오류가 발생했습니다.',
      [ErrorCode.RATE_LIMIT_EXCEEDED]: '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
      [ErrorCode.BAD_REQUEST]: '잘못된 요청입니다.',
      [ErrorCode.CONFLICT]: '리소스 충돌이 발생했습니다.',
    };

    return messages[code] ?? '알 수 없는 오류가 발생했습니다.';
  }

  // 자주 쓰는 에러 팩토리 메서드
  static badRequest(code: ErrorCode, message?: string, details?: unknown): AppError {
    return new AppError(code, 400, message, details);
  }

  static unauthorized(code: ErrorCode = ErrorCode.AUTH_UNAUTHORIZED, message?: string): AppError {
    return new AppError(code, 401, message);
  }

  static forbidden(code: ErrorCode = ErrorCode.AUTH_FORBIDDEN, message?: string): AppError {
    return new AppError(code, 403, message);
  }

  static notFound(code: ErrorCode = ErrorCode.NOT_FOUND, message?: string): AppError {
    return new AppError(code, 404, message);
  }

  static conflict(code: ErrorCode = ErrorCode.CONFLICT, message?: string): AppError {
    return new AppError(code, 409, message);
  }

  static internal(message?: string): AppError {
    return new AppError(ErrorCode.INTERNAL_SERVER_ERROR, 500, message);
  }

  toJSON() {
    return {
      success: false,
      error: {
        code: this.code,
        message: this.message,
        details: this.details,
      },
    };
  }
}
