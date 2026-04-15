import { z } from 'zod';

export const kcpVerifySchema = z.object({
  key: z.string().min(1, 'KCP 인증 key가 필요합니다.'),
});

export type KcpVerifyDto = z.infer<typeof kcpVerifySchema>;

// KCP 서버에서 반환하는 인증 결과 원본
export interface KcpRawResult {
  ci: string;
  di: string;
  phoneNumber: string;
  gender: string;       // M | F
  birthDate: string;    // YYYYMMDD
  realName: string;
  carrier: string;      // KT | SKT | LGT | KT_MVNO | SKT_MVNO | LGT_MVNO
}

// verifyCert 반환 타입
export interface KcpVerifyResult {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    nickname: string;
    profileImageUrl: string | null;
    isNewUser: boolean;
    isVerified: boolean;
    phoneNumber: string;
  };
  nextRoute: 'profile-setup' | 'home';
}
