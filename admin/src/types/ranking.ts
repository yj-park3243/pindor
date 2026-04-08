import type { SportType, Tier } from './user';

export interface RankingEntry {
  id: string;
  pinId: string;
  pinName?: string;
  sportsProfileId: string;
  sportType: SportType;
  rank: number;
  score: number;
  tier: Tier;
  gamesPlayed: number;
  updatedAt: string;
  user?: {
    id: string;
    nickname: string;
    profileImageUrl: string | null;
  };
}

export interface RankingAnomalyFlag {
  id: string;
  sportsProfileId: string;
  userId: string;
  nickname: string;
  flagType: 'FREQUENT_SAME_OPPONENT' | 'LARGE_SCORE_GAP' | 'SAME_DEVICE' | 'RAPID_SCORE_GAIN';
  severity: 'LOW' | 'MEDIUM' | 'HIGH';
  description: string;
  isResolved: boolean;
  resolvedBy: string | null;
  resolvedAt: string | null;
  createdAt: string;
}

export interface RankingListFilter {
  pinId?: string;
  sportType?: SportType;
  tier?: Tier;
}
