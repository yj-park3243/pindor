export interface Team {
  id: string;
  name: string;
  slug: string;
  sportType: string;
  logoUrl?: string;
  description?: string;
  activityRegion?: string;
  currentMembers: number;
  maxMembers: number;
  wins: number;
  losses: number;
  draws: number;
  teamScore: number;
  isRecruiting: boolean;
  status: 'ACTIVE' | 'INACTIVE' | 'DISBANDED';
  createdAt: string;
}

export interface TeamMember {
  id: string;
  teamId: string;
  userId: string;
  role: 'CAPTAIN' | 'VICE_CAPTAIN' | 'MEMBER';
  position?: string;
  status: 'ACTIVE' | 'INACTIVE' | 'BANNED';
  joinedAt: string;
  user?: {
    id: string;
    nickname: string;
    profileImageUrl?: string;
  };
}

export interface TeamMatch {
  id: string;
  homeTeamId: string;
  awayTeamId: string;
  sportType: string;
  status: string;
  homeScore?: number;
  awayScore?: number;
  resultStatus: string;
  homeTeam?: Team;
  awayTeam?: Team;
  createdAt: string;
}

export interface TeamPost {
  id: string;
  teamId: string;
  authorId: string;
  category: string;
  title: string;
  content: string;
  isPinned: boolean;
  viewCount: number;
  createdAt: string;
}

export type TeamStatus = Team['status'];
export type TeamMemberRole = TeamMember['role'];
export type TeamMemberStatus = TeamMember['status'];
