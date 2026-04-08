export type ReportTargetType = 'USER' | 'POST' | 'COMMENT' | 'GAME_RESULT' | 'CHAT';
export type ReportStatus = 'PENDING' | 'REVIEWED' | 'RESOLVED' | 'DISMISSED';

export interface Report {
  id: string;
  reporterId: string;
  reporter?: {
    id: string;
    nickname: string;
  };
  targetType: ReportTargetType;
  targetId: string;
  reason: string;
  description: string | null;
  status: ReportStatus;
  resolvedBy: string | null;
  resolvedAt: string | null;
  resolverNote: string | null;
  createdAt: string;
}

export interface ReportListFilter {
  status?: ReportStatus;
  targetType?: ReportTargetType;
  dateRange?: [string, string];
}
