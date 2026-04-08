export type UserStatus = 'ACTIVE' | 'SUSPENDED' | 'WITHDRAWN';
export type SportType = 'GOLF' | 'BILLIARDS' | 'TENNIS' | 'TABLE_TENNIS';
export type Tier = 'GRANDMASTER' | 'MASTER' | 'PLATINUM' | 'GOLD' | 'SILVER' | 'BRONZE' | 'IRON';
export type SocialProvider = 'KAKAO' | 'APPLE' | 'GOOGLE';

export interface User {
  id: string;
  email: string | null;
  nickname: string;
  profileImageUrl: string | null;
  phone: string | null;
  status: UserStatus;
  createdAt: string;
  updatedAt: string;
  lastLoginAt: string | null;
  sportsProfiles?: SportsProfile[];
  socialAccounts?: SocialAccount[];
}

export interface SocialAccount {
  id: string;
  userId: string;
  provider: SocialProvider;
  providerId: string;
  createdAt: string;
}

export interface SportsProfile {
  id: string;
  userId: string;
  sportType: SportType;
  displayName: string;
  initialScore: number;
  currentScore: number;
  tier: Tier;
  gHandicap: number | null;
  extraData: Record<string, unknown>;
  isVerified: boolean;
  gamesPlayed: number;
  wins: number;
  losses: number;
  createdAt: string;
}

export interface ScoreHistory {
  id: string;
  sportsProfileId: string;
  previousScore: number;
  newScore: number;
  change: number;
  reason: string;
  gameId: string | null;
  adminId: string | null;
  adminNote: string | null;
  createdAt: string;
}

export interface UserListFilter {
  search?: string;
  status?: UserStatus;
  sportType?: SportType;
  tier?: Tier;
  dateRange?: [string, string];
}
