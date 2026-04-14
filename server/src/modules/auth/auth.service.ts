import { DataSource } from 'typeorm';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { issueTokenPair, verifyRefreshToken } from '../../shared/utils/jwt.js';
import { redis } from '../../config/redis.js';
import {
  User,
  SocialAccount,
  NotificationSettings,
  DeviceToken,
} from '../../entities/index.js';
import { SocialProvider } from '../../entities/index.js';
import { createHash } from 'crypto';
import type { KakaoLoginDto, KakaoUserInfo, GoogleLoginDto, GoogleUserInfo, AppleLoginDto, EmailRegisterDto, EmailLoginDto } from './auth.schema.js';
import { createPublicKey } from 'crypto';
import * as jwt from 'jsonwebtoken';

export class AuthService {
  constructor(private dataSource: DataSource) {}

  // ─────────────────────────────────────
  // 카카오 OAuth 로그인
  // ─────────────────────────────────────

  async kakaoLogin(dto: KakaoLoginDto): Promise<{
    accessToken: string;
    refreshToken: string;
    user: {
      id: string;
      nickname: string;
      profileImageUrl: string | null;
      isNewUser: boolean;
    };
  }> {
    // 카카오 사용자 정보 조회
    const kakaoUser = await this.fetchKakaoUserInfo(dto.accessToken);

    const providerId = String(kakaoUser.id);
    const email = kakaoUser.kakao_account?.email ?? null;
    const nickname =
      kakaoUser.kakao_account?.profile?.nickname ??
      kakaoUser.properties?.nickname ??
      null;
    const profileImageUrl =
      kakaoUser.kakao_account?.profile?.profile_image_url ??
      kakaoUser.properties?.profile_image ??
      null;

    // 성별 변환 (카카오: male/female → 서비스: MALE/FEMALE)
    const kakaoGender = kakaoUser.kakao_account?.gender;
    const gender =
      kakaoGender === 'male' ? 'MALE' :
      kakaoGender === 'female' ? 'FEMALE' :
      null;

    // 생년월일 변환 (birthyear: YYYY + birthday: MMDD → YYYY-MM-DD)
    const birthyear = kakaoUser.kakao_account?.birthyear;
    const birthday = kakaoUser.kakao_account?.birthday;
    let birthDate: Date | null = null;
    if (birthyear && birthday && birthday.length === 4) {
      const dateStr = `${birthyear}-${birthday.slice(0, 2)}-${birthday.slice(2, 4)}`;
      const parsed = new Date(dateStr);
      if (!isNaN(parsed.getTime())) {
        birthDate = parsed;
      }
    }

    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);
    const userRepo = this.dataSource.getRepository(User);

    // 기존 소셜 계정 확인
    const existingSocial = await socialAccountRepo.findOne({
      where: { provider: SocialProvider.KAKAO, providerId },
      relations: { user: true },
    });

    let isNewUser = false;

    if (existingSocial) {
      // 기존 사용자 — 로그인 처리
      const user = existingSocial.user;

      if (user.status === 'SUSPENDED') {
        throw new AppError(ErrorCode.USER_SUSPENDED, 403);
      }
      if (user.status === 'WITHDRAWN') {
        throw new AppError(ErrorCode.USER_WITHDRAWN, 403);
      }

      // 마지막 로그인 시간 업데이트 + 성별/생년월일 갱신 (카카오에서 받은 경우)
      await userRepo.update(user.id, {
        lastLoginAt: new Date(),
        ...(gender && !user.gender && { gender }),
        ...(birthDate && !user.birthDate && { birthDate }),
      });

      const tokens = await issueTokenPair({ userId: user.id, email: user.email });
      await this.storeRefreshToken(user.id, tokens.refreshToken);

      return {
        ...tokens,
        user: {
          id: user.id,
          nickname: user.nickname,
          profileImageUrl: user.profileImageUrl,
          isNewUser: false,
        },
      };
    }

    // 같은 이메일로 이미 가입된 유저가 있으면 카카오 계정만 연결
    if (email) {
      const existingUser = await userRepo.findOne({ where: { email } });
      if (existingUser) {
        if (existingUser.status === 'SUSPENDED') throw new AppError(ErrorCode.USER_SUSPENDED, 403);
        if (existingUser.status === 'WITHDRAWN') throw new AppError(ErrorCode.USER_WITHDRAWN, 403);

        await socialAccountRepo.save(socialAccountRepo.create({
          userId: existingUser.id,
          provider: SocialProvider.KAKAO,
          providerId,
        }));
        await userRepo.update(existingUser.id, {
          lastLoginAt: new Date(),
          ...(gender && !existingUser.gender && { gender }),
          ...(birthDate && !existingUser.birthDate && { birthDate }),
        });

        const tokens = await issueTokenPair({ userId: existingUser.id, email: existingUser.email });
        await this.storeRefreshToken(existingUser.id, tokens.refreshToken);

        return {
          ...tokens,
          user: {
            id: existingUser.id,
            nickname: existingUser.nickname,
            profileImageUrl: existingUser.profileImageUrl,
            isNewUser: false,
          },
        };
      }
    }

    // 완전 신규 사용자 — 회원 가입
    isNewUser = true;

    const uniqueNickname = await this.generateUniqueNickname(nickname);

    const user = await this.dataSource.transaction(async (manager) => {
      const now = new Date();
      const newUser = manager.create(User, {
        email,
        nickname: uniqueNickname,
        profileImageUrl,
        lastLoginAt: now,
        updatedAt: now,
        ...(gender && { gender }),
        ...(birthDate && { birthDate }),
      });
      await manager.save(User, newUser);

      await manager.save(SocialAccount, manager.create(SocialAccount, {
        userId: newUser.id,
        provider: SocialProvider.KAKAO,
        providerId,
      }));

      await manager.save(NotificationSettings, manager.create(NotificationSettings, {
        userId: newUser.id,
      }));

      return newUser;
    });

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: user.id,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        isNewUser,
      },
    };
  }

  // ─────────────────────────────────────
  // Google OAuth 로그인
  // ─────────────────────────────────────

  async googleLogin(dto: GoogleLoginDto): Promise<{
    accessToken: string;
    refreshToken: string;
    user: {
      id: string;
      nickname: string;
      profileImageUrl: string | null;
      isNewUser: boolean;
    };
  }> {
    // Google ID Token 검증
    const googleUser = await this.verifyGoogleIdToken(dto.idToken);

    const providerId = googleUser.sub;
    const email = googleUser.email ?? null;
    const nickname = googleUser.name ?? googleUser.given_name ?? null;
    const profileImageUrl = googleUser.picture ?? null;

    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);
    const userRepo = this.dataSource.getRepository(User);

    // 기존 소셜 계정 확인
    const existingSocial = await socialAccountRepo.findOne({
      where: { provider: SocialProvider.GOOGLE, providerId },
      relations: { user: true },
    });

    if (existingSocial) {
      // 기존 사용자 — 로그인 처리
      const user = existingSocial.user;

      if (user.status === 'SUSPENDED') {
        throw new AppError(ErrorCode.USER_SUSPENDED, 403);
      }
      if (user.status === 'WITHDRAWN') {
        throw new AppError(ErrorCode.USER_WITHDRAWN, 403);
      }

      // 마지막 로그인 시간 업데이트
      await userRepo.update(user.id, { lastLoginAt: new Date() });

      const tokens = await issueTokenPair({ userId: user.id, email: user.email });
      await this.storeRefreshToken(user.id, tokens.refreshToken);

      return {
        ...tokens,
        user: {
          id: user.id,
          nickname: user.nickname,
          profileImageUrl: user.profileImageUrl,
          isNewUser: false,
        },
      };
    }

    // 같은 이메일로 이미 가입된 유저가 있으면 Google 계정만 연결
    if (email) {
      const existingUser = await userRepo.findOne({ where: { email } });
      if (existingUser) {
        if (existingUser.status === 'SUSPENDED') throw new AppError(ErrorCode.USER_SUSPENDED, 403);
        if (existingUser.status === 'WITHDRAWN') throw new AppError(ErrorCode.USER_WITHDRAWN, 403);

        await socialAccountRepo.save(socialAccountRepo.create({
          userId: existingUser.id,
          provider: SocialProvider.GOOGLE,
          providerId,
        }));
        await userRepo.update(existingUser.id, { lastLoginAt: new Date() });

        const tokens = await issueTokenPair({ userId: existingUser.id, email: existingUser.email });
        await this.storeRefreshToken(existingUser.id, tokens.refreshToken);

        return {
          ...tokens,
          user: {
            id: existingUser.id,
            nickname: existingUser.nickname,
            profileImageUrl: existingUser.profileImageUrl,
            isNewUser: false,
          },
        };
      }
    }

    // 완전 신규 사용자 — 회원 가입
    const uniqueNickname = await this.generateUniqueNickname(nickname);

    const user = await this.dataSource.transaction(async (manager) => {
      const now = new Date();
      const newUser = manager.create(User, {
        email,
        nickname: uniqueNickname,
        profileImageUrl,
        lastLoginAt: now,
        updatedAt: now,
      });
      await manager.save(User, newUser);

      await manager.save(SocialAccount, manager.create(SocialAccount, {
        userId: newUser.id,
        provider: SocialProvider.GOOGLE,
        providerId,
      }));

      await manager.save(NotificationSettings, manager.create(NotificationSettings, {
        userId: newUser.id,
      }));

      return newUser;
    });

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: user.id,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        isNewUser: true,
      },
    };
  }

  // ─────────────────────────────────────
  // Apple OAuth 로그인
  // ─────────────────────────────────────

  async appleLogin(dto: AppleLoginDto): Promise<{
    accessToken: string;
    refreshToken: string;
    user: {
      id: string;
      nickname: string;
      profileImageUrl: string | null;
      isNewUser: boolean;
    };
  }> {
    const applePayload = await this.verifyAppleIdentityToken(dto.identityToken);

    const providerId = applePayload.sub;
    const email = dto.email ?? applePayload.email ?? null;
    const nickname = dto.fullName ?? null;

    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);
    const userRepo = this.dataSource.getRepository(User);

    const existingSocial = await socialAccountRepo.findOne({
      where: { provider: SocialProvider.APPLE, providerId },
      relations: { user: true },
    });

    if (existingSocial) {
      const user = existingSocial.user;
      if (user.status === 'SUSPENDED') throw new AppError(ErrorCode.USER_SUSPENDED, 403);
      if (user.status === 'WITHDRAWN') throw new AppError(ErrorCode.USER_WITHDRAWN, 403);

      await userRepo.update(user.id, { lastLoginAt: new Date() });

      const tokens = await issueTokenPair({ userId: user.id, email: user.email });
      await this.storeRefreshToken(user.id, tokens.refreshToken);

      return {
        ...tokens,
        user: {
          id: user.id,
          nickname: user.nickname,
          profileImageUrl: user.profileImageUrl,
          isNewUser: false,
        },
      };
    }

    // 같은 이메일로 이미 가입된 유저가 있으면 Apple 계정만 연결
    if (email) {
      const existingUser = await userRepo.findOne({ where: { email } });
      if (existingUser) {
        if (existingUser.status === 'SUSPENDED') throw new AppError(ErrorCode.USER_SUSPENDED, 403);
        if (existingUser.status === 'WITHDRAWN') throw new AppError(ErrorCode.USER_WITHDRAWN, 403);

        await socialAccountRepo.save(socialAccountRepo.create({
          userId: existingUser.id,
          provider: SocialProvider.APPLE,
          providerId,
        }));
        await userRepo.update(existingUser.id, { lastLoginAt: new Date() });

        const tokens = await issueTokenPair({ userId: existingUser.id, email: existingUser.email });
        await this.storeRefreshToken(existingUser.id, tokens.refreshToken);

        return {
          ...tokens,
          user: {
            id: existingUser.id,
            nickname: existingUser.nickname,
            profileImageUrl: existingUser.profileImageUrl,
            isNewUser: false,
          },
        };
      }
    }

    // 완전 신규 사용자
    const uniqueNickname = await this.generateUniqueNickname(nickname);

    const user = await this.dataSource.transaction(async (manager) => {
      const now = new Date();
      const newUser = manager.create(User, {
        email,
        nickname: uniqueNickname,
        lastLoginAt: now,
        updatedAt: now,
      });
      await manager.save(User, newUser);

      await manager.save(SocialAccount, manager.create(SocialAccount, {
        userId: newUser.id,
        provider: SocialProvider.APPLE,
        providerId,
      }));

      await manager.save(NotificationSettings, manager.create(NotificationSettings, {
        userId: newUser.id,
      }));

      return newUser;
    });

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: user.id,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        isNewUser: true,
      },
    };
  }

  // ─────────────────────────────────────
  // 이메일 회원가입
  // ─────────────────────────────────────

  async emailRegister(dto: EmailRegisterDto) {
    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);
    const userRepo = this.dataSource.getRepository(User);

    // 이메일 중복 확인
    const existing = await socialAccountRepo.findOne({
      where: { provider: SocialProvider.EMAIL, providerId: dto.email },
    });
    if (existing) {
      throw new AppError(ErrorCode.AUTH_DUPLICATE_EMAIL ?? 'AUTH_DUPLICATE_EMAIL', 409, '이미 가입된 이메일입니다.');
    }

    const passwordHash = this.hashPassword(dto.password);
    const nickname = dto.nickname ?? await this.generateUniqueNickname(null);

    const user = await this.dataSource.transaction(async (manager) => {
      const newUser = manager.create(User, {
        email: dto.email,
        nickname,
        lastLoginAt: new Date(),
        updatedAt: new Date(),
      });
      await manager.save(User, newUser);

      // providerId = email, accessToken = passwordHash
      await manager.save(SocialAccount, manager.create(SocialAccount, {
        userId: newUser.id,
        provider: SocialProvider.EMAIL,
        providerId: dto.email,
        accessToken: passwordHash,
      }));

      await manager.save(NotificationSettings, manager.create(NotificationSettings, {
        userId: newUser.id,
        updatedAt: new Date(),
      }));

      return newUser;
    });

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: user.id,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        isNewUser: true,
      },
    };
  }

  // ─────────────────────────────────────
  // 이메일 로그인
  // ─────────────────────────────────────

  async emailLogin(dto: EmailLoginDto) {
    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);
    const userRepo = this.dataSource.getRepository(User);

    const socialAccount = await socialAccountRepo.findOne({
      where: { provider: SocialProvider.EMAIL, providerId: dto.email },
      relations: { user: true },
    });

    if (!socialAccount || socialAccount.accessToken !== this.hashPassword(dto.password)) {
      throw new AppError(ErrorCode.AUTH_INVALID_CREDENTIALS ?? 'AUTH_INVALID_CREDENTIALS', 401, '이메일 또는 비밀번호가 올바르지 않습니다.');
    }

    const user = socialAccount.user;
    if (user.status === 'SUSPENDED') throw new AppError(ErrorCode.USER_SUSPENDED, 403);
    if (user.status === 'WITHDRAWN') throw new AppError(ErrorCode.USER_WITHDRAWN, 403);

    await userRepo.update(user.id, { lastLoginAt: new Date() });

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: user.id,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        isNewUser: false,
      },
    };
  }

  private hashPassword(password: string): string {
    return createHash('sha256').update(password).digest('hex');
  }

  // ─────────────────────────────────────
  // 토큰 갱신
  // ─────────────────────────────────────

  async refreshToken(refreshToken: string): Promise<{
    accessToken: string;
    refreshToken: string;
  }> {
    const payload = await verifyRefreshToken(refreshToken);

    // Redis에 저장된 토큰과 일치 확인
    const storedToken = await redis.get(`refresh_token:${payload.userId}`);
    if (!storedToken || storedToken !== refreshToken) {
      throw new AppError(ErrorCode.AUTH_REFRESH_INVALID, 401);
    }

    const userRepo = this.dataSource.getRepository(User);
    const user = await userRepo.findOne({
      where: { id: payload.userId },
      select: { id: true, email: true, status: true },
    });

    if (!user || user.status !== 'ACTIVE') {
      throw new AppError(ErrorCode.AUTH_REFRESH_INVALID, 401);
    }

    const tokens = await issueTokenPair({ userId: user.id, email: user.email });
    await this.storeRefreshToken(user.id, tokens.refreshToken);

    return tokens;
  }

  // ─────────────────────────────────────
  // 로그아웃
  // ─────────────────────────────────────

  async logout(userId: string, pushToken?: string): Promise<void> {
    // 리프레시 토큰 삭제
    await redis.del(`refresh_token:${userId}`);

    // 푸시 토큰 비활성화
    if (pushToken) {
      const deviceTokenRepo = this.dataSource.getRepository(DeviceToken);
      await deviceTokenRepo.update(
        { userId, token: pushToken },
        { isActive: false },
      );
    }
  }

  // ─────────────────────────────────────
  // Private 헬퍼 메서드
  // ─────────────────────────────────────

  private async verifyGoogleIdToken(idToken: string): Promise<GoogleUserInfo> {
    const response = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
    );

    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      console.error('[Google] tokeninfo error:', error);
      throw new AppError(
        ErrorCode.AUTH_GOOGLE_FAILED,
        401,
        'Google 인증에 실패했습니다.',
      );
    }

    const payload = await response.json() as GoogleUserInfo;

    // sub(Google user ID) 필수 확인
    if (!payload.sub) {
      throw new AppError(
        ErrorCode.AUTH_GOOGLE_FAILED,
        401,
        'Google ID Token에서 사용자 정보를 가져올 수 없습니다.',
      );
    }

    return payload;
  }

  private async verifyAppleIdentityToken(identityToken: string): Promise<{ sub: string; email?: string }> {
    // Apple 공개 키 가져오기
    const keysResponse = await fetch('https://appleid.apple.com/auth/keys');
    if (!keysResponse.ok) {
      throw new AppError(ErrorCode.AUTH_APPLE_FAILED ?? 'AUTH_APPLE_FAILED', 401, 'Apple 공개 키를 가져올 수 없습니다.');
    }
    const { keys } = await keysResponse.json() as { keys: Array<{ kid: string; kty: string; use: string; alg: string; n: string; e: string }> };

    // JWT 헤더에서 kid 추출
    const header = JSON.parse(Buffer.from(identityToken.split('.')[0], 'base64url').toString());
    const appleKey = keys.find((k: { kid: string }) => k.kid === header.kid);
    if (!appleKey) {
      throw new AppError(ErrorCode.AUTH_APPLE_FAILED ?? 'AUTH_APPLE_FAILED', 401, 'Apple 공개 키를 찾을 수 없습니다.');
    }

    // JWK → PEM 변환
    const publicKey = createPublicKey({
      key: { kty: appleKey.kty, n: appleKey.n, e: appleKey.e },
      format: 'jwk',
    });

    // JWT 검증
    try {
      const payload = jwt.verify(identityToken, publicKey, {
        algorithms: ['RS256'],
        issuer: 'https://appleid.apple.com',
        audience: 'kr.pins',
      }) as { sub: string; email?: string };

      if (!payload.sub) {
        throw new Error('sub missing');
      }

      return payload;
    } catch (e) {
      console.error('[Apple] JWT verify error:', e);
      throw new AppError(ErrorCode.AUTH_APPLE_FAILED ?? 'AUTH_APPLE_FAILED', 401, 'Apple 인증에 실패했습니다.');
    }
  }

  private async fetchKakaoUserInfo(accessToken: string): Promise<KakaoUserInfo> {
    const response = await fetch('https://kapi.kakao.com/v2/user/me', {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      console.error('[Kakao] API error:', error);
      throw new AppError(
        ErrorCode.AUTH_KAKAO_FAILED,
        401,
        '카카오 사용자 정보 조회에 실패했습니다.',
      );
    }

    return response.json() as Promise<KakaoUserInfo>;
  }

  private async generateUniqueNickname(base: string | null): Promise<string> {
    const baseNickname = (base ?? '골퍼').slice(0, 14); // 최대 14자 (뒤에 번호 붙을 공간)

    const userRepo = this.dataSource.getRepository(User);

    // 닉네임 중복 확인
    const exists = await userRepo.findOne({ where: { nickname: baseNickname } });

    if (!exists) return baseNickname;

    // 중복 시 랜덤 숫자 부가
    for (let i = 0; i < 10; i++) {
      const suffix = Math.floor(Math.random() * 9999) + 1;
      const candidate = `${baseNickname}${suffix}`.slice(0, 20);
      const dup = await userRepo.findOne({ where: { nickname: candidate } });
      if (!dup) return candidate;
    }

    // 최후의 수단: 타임스탬프 사용
    return `사용자${Date.now().toString().slice(-8)}`;
  }

  private async storeRefreshToken(userId: string, token: string): Promise<void> {
    // 30일 TTL
    await redis.setex(`refresh_token:${userId}`, 30 * 24 * 3600, token);
  }
}
