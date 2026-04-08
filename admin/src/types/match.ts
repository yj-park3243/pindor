import type { SportType, SportsProfile, User } from './user';

export type MatchRequestStatus = 'WAITING' | 'MATCHED' | 'CANCELLED' | 'EXPIRED';
export type MatchRequestType = 'SCHEDULED' | 'INSTANT';
export type TimeSlot = 'MORNING' | 'AFTERNOON' | 'EVENING' | 'ANY';
export type MatchStatus = 'CHAT' | 'CONFIRMED' | 'COMPLETED' | 'CANCELLED' | 'DISPUTED';

export interface MatchRequest {
  id: string;
  requesterId: string;
  requester?: User;
  sportType: SportType;
  requestType: MatchRequestType;
  desiredDate: string;
  desiredTimeSlot: TimeSlot;
  location: { lat: number; lng: number };
  locationName: string;
  radiusKm: number;
  minScoreOpponent: number;
  maxScoreOpponent: number;
  status: MatchRequestStatus;
  expiresAt: string;
  createdAt: string;
}

export interface Match {
  id: string;
  matchRequestId: string;
  requesterProfileId: string;
  requesterProfile?: SportsProfile & { user?: User };
  opponentProfileId: string;
  opponentProfile?: SportsProfile & { user?: User };
  sportType: SportType;
  scheduledDate: string | null;
  status: MatchStatus;
  chatRoomId: string;
  confirmedAt: string | null;
  completedAt: string | null;
  createdAt: string;
}

export interface MatchListFilter {
  status?: MatchStatus;
  sportType?: SportType;
  dateRange?: [string, string];
  search?: string;
}
