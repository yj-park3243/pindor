import type { SportType, SportsProfile, User } from './user';

export type GameResultStatus =
  | 'PENDING'
  | 'PROOF_UPLOADED'
  | 'VERIFIED'
  | 'DISPUTED'
  | 'VOIDED';

export interface Game {
  id: string;
  matchId: string;
  sportType: SportType;
  venueName: string | null;
  venueLocation: { lat: number; lng: number } | null;
  playedAt: string | null;
  scoreData: Record<string, unknown>;
  resultStatus: GameResultStatus;
  winnerId: string | null;
  winner?: SportsProfile & { user?: User };
  requesterProfile?: SportsProfile & { user?: User };
  opponentProfile?: SportsProfile & { user?: User };
  proofs?: GameResultProof[];
  dispute?: GameDispute | null;
  createdAt: string;
}

export interface GameResultProof {
  id: string;
  gameId: string;
  uploadedBy: string;
  uploader?: User;
  imageUrl: string;
  imageType: 'SCORECARD' | 'RECEIPT' | 'OTHER';
  isApproved: boolean | null;
  reviewedBy: string | null;
  createdAt: string;
}

export interface GameDispute {
  id: string;
  gameId: string;
  disputedBy: string;
  reason: string;
  evidenceImageUrls: string[];
  status: 'PENDING' | 'RESOLVED';
  resolution: 'ORIGINAL' | 'MODIFIED' | 'VOIDED' | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
  adminNote: string | null;
  createdAt: string;
}

export interface GameListFilter {
  resultStatus?: GameResultStatus;
  sportType?: SportType;
  dateRange?: [string, string];
  search?: string;
}
