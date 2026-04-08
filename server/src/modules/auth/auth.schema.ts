import { z } from 'zod';

export const kakaoLoginSchema = z.object({
  accessToken: z.string().min(1, '카카오 액세스 토큰이 필요합니다.'),
});

export const appleLoginSchema = z.object({
  identityToken: z.string().min(1, '애플 Identity 토큰이 필요합니다.'),
  authorizationCode: z.string().min(1, '애플 인증 코드가 필요합니다.'),
  email: z.string().email().optional(),
  fullName: z.string().optional(),
});

export const refreshTokenSchema = z.object({
  refreshToken: z.string().min(1, '리프레시 토큰이 필요합니다.'),
});

export const logoutSchema = z.object({
  pushToken: z.string().optional(), // 로그아웃 시 푸시 토큰 제거
});

export const googleLoginSchema = z.object({
  idToken: z.string().min(1, 'idToken is required'),
});

export const emailRegisterSchema = z.object({
  email: z.string().email('유효한 이메일을 입력해주세요.'),
  password: z.string().min(6, '비밀번호는 6자 이상이어야 합니다.'),
  nickname: z.string().min(2).max(20).optional(),
});

export const emailLoginSchema = z.object({
  email: z.string().email('유효한 이메일을 입력해주세요.'),
  password: z.string().min(1, '비밀번호를 입력해주세요.'),
});

export type KakaoLoginDto = z.infer<typeof kakaoLoginSchema>;
export type AppleLoginDto = z.infer<typeof appleLoginSchema>;
export type GoogleLoginDto = z.infer<typeof googleLoginSchema>;
export type EmailRegisterDto = z.infer<typeof emailRegisterSchema>;
export type EmailLoginDto = z.infer<typeof emailLoginSchema>;
export type RefreshTokenDto = z.infer<typeof refreshTokenSchema>;
export type LogoutDto = z.infer<typeof logoutSchema>;

// Google ID Token payload 타입
export interface GoogleUserInfo {
  sub: string;           // Google user ID
  email?: string;
  email_verified?: string; // tokeninfo API는 string으로 반환
  name?: string;
  picture?: string;
  given_name?: string;
  family_name?: string;
}

// 카카오 API 응답 타입
export interface KakaoUserInfo {
  id: number;
  kakao_account?: {
    email?: string;
    email_needs_agreement?: boolean;
    profile?: {
      nickname?: string;
      profile_image_url?: string;
      thumbnail_image_url?: string;
    };
    // 성별: male / female
    gender?: string;
    gender_needs_agreement?: boolean;
    // 생년월일: MMDD 형식 (예: 0101)
    birthday?: string;
    birthday_needs_agreement?: boolean;
    // 출생년도: YYYY 형식
    birthyear?: string;
    birthyear_needs_agreement?: boolean;
  };
  properties?: {
    nickname?: string;
    profile_image?: string;
    thumbnail_image?: string;
  };
}
