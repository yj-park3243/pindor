export type PinLevel = 'DONG' | 'GU' | 'CITY' | 'PROVINCE';

export interface Pin {
  id: string;
  name: string;
  slug: string;
  center: { lat: number; lng: number };
  boundary?: GeoJSON.Polygon;
  level: PinLevel;
  parentPinId: string | null;
  isActive: boolean;
  userCount: number;
  createdAt: string;
}

export interface PinStats {
  pinId: string;
  userCount: number;
  activeMatchRequests: number;
  weeklyGames: number;
  topRankedUsers: {
    id: string;
    nickname: string;
    tier: string;
    score: number;
  }[];
}

export interface PinPost {
  id: string;
  pinId: string;
  pin?: Pin;
  authorId: string;
  author?: {
    id: string;
    nickname: string;
    profileImageUrl: string | null;
  };
  title: string;
  content: string;
  category: 'GENERAL' | 'MATCH_SEEK' | 'REVIEW' | 'NOTICE';
  viewCount: number;
  likeCount: number;
  commentCount: number;
  isDeleted: boolean;
  isBlinded: boolean;
  images?: PostImage[];
  createdAt: string;
  updatedAt: string;
}

export interface PostImage {
  id: string;
  postId: string;
  imageUrl: string;
  sortOrder: number;
}

export interface Comment {
  id: string;
  postId: string;
  authorId: string;
  author?: {
    id: string;
    nickname: string;
    profileImageUrl: string | null;
  };
  parentId: string | null;
  content: string;
  isDeleted: boolean;
  isBlinded: boolean;
  replies?: Comment[];
  createdAt: string;
  updatedAt: string;
}

export interface PinListFilter {
  level?: PinLevel;
  isActive?: boolean;
  search?: string;
}

export interface PostListFilter {
  pinId?: string;
  category?: string;
  isDeleted?: boolean;
  isBlinded?: boolean;
  search?: string;
}
