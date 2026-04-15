import { DataSource } from 'typeorm';
import { createHmac } from 'crypto';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { issueTokenPair } from '../../shared/utils/jwt.js';
import { redis } from '../../config/redis.js';
import { storeRefreshToken } from '../../shared/utils/token.js';
import { env } from '../../config/env.js';
import { User, SocialAccount } from '../../entities/index.js';
import { UserStatus } from '../../entities/enums.js';
import type { KcpRawResult, KcpVerifyResult } from './kcp.schema.js';

// KCP 설정
const KCP_SITE_CD = env.KCP_SITE_CD;
const KCP_CERT_KEY = env.KCP_CERT_KEY;
const KCP_CERT_URL = 'https://cert.kcp.co.kr/kcp_cert/cert_view.jsp';
const KCP_RESULT_URL = 'https://cert.kcp.co.kr/kcp_cert/cert_action_new.jsp';
const KCP_RESULT_URL_DEV = 'https://testcert.kcp.co.kr/kcp_cert/cert_action_new.jsp';

export class KcpService {
  constructor(private dataSource: DataSource) {}

  // ─────────────────────────────────────
  // KCP 인증 HTML Form 생성
  // ─────────────────────────────────────

  async generateCertForm(userId: string, returnUrl: string): Promise<string> {
    const now = new Date();
    const kcp_merchant_time = this.formatDateTime(now);
    const ordr_idxx = `${userId.replace(/-/g, '').slice(0, 14)}_${Date.now()}`;

    // HMAC-SHA256 서명: site_cd + ordr_idxx + req_tx + cert_method + kcp_merchant_time
    const signData = `${KCP_SITE_CD}^${ordr_idxx}^cert^01^${kcp_merchant_time}`;
    const up_hash = createHmac('sha256', KCP_CERT_KEY)
      .update(signData)
      .digest('hex');

    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>본인인증</title>
</head>
<body>
  <form id="certForm" name="form_auth" method="POST" action="${KCP_CERT_URL}">
    <input type="hidden" name="site_cd"            value="${KCP_SITE_CD}" />
    <input type="hidden" name="ordr_idxx"          value="${ordr_idxx}" />
    <input type="hidden" name="req_tx"             value="cert" />
    <input type="hidden" name="cert_method"        value="01" />
    <input type="hidden" name="up_hash"            value="${up_hash}" />
    <input type="hidden" name="kcp_merchant_time"  value="${kcp_merchant_time}" />
    <input type="hidden" name="Ret_URL"            value="${returnUrl}" />
    <input type="hidden" name="cert_otp_use"       value="Y" />
    <input type="hidden" name="cert_able_yn"       value="Y" />
    <input type="hidden" name="web_siteid_hashYN"  value="N" />
    <input type="hidden" name="res_cd"             value="" />
    <input type="hidden" name="res_msg"            value="" />
    <input type="hidden" name="enc_cert_data2"     value="" />
    <input type="hidden" name="phone_no"           value="" />
    <input type="hidden" name="birth_day"          value="" />
    <input type="hidden" name="sex_code"           value="" />
    <input type="hidden" name="local_code"         value="" />
    <input type="hidden" name="user_name"          value="" />
    <input type="hidden" name="CI_value"           value="" />
    <input type="hidden" name="DI_value"           value="" />
  </form>
  <script>
    document.getElementById('certForm').submit();
  </script>
</body>
</html>`;

    return html;
  }

  // ─────────────────────────────────────
  // KCP 인증 결과 검증 및 유저 정보 저장
  // ─────────────────────────────────────

  async verifyCert(userId: string, key: string): Promise<KcpVerifyResult> {
    // key 재사용 방지 체크 (원자적 SET NX로 경쟁 조건 방지)
    const setResult = await redis.set(`kcp:used_key:${key}`, '1', 'EX', 24 * 3600, 'NX');
    if (!setResult) {
      throw new AppError(ErrorCode.KCP_KEY_ALREADY_USED, 409);
    }

    // KCP 서버에서 인증 결과 조회
    const kcpData = await this.fetchKcpResult(key);

    // CI 중복 체크
    const userRepo = this.dataSource.getRepository(User);
    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);

    const existingUser = await userRepo.findOne({
      where: { ci: kcpData.ci },
    });

    const currentUser = await userRepo.findOne({
      where: { id: userId },
    });

    if (!currentUser) {
      throw new AppError(ErrorCode.USER_NOT_FOUND, 404);
    }

    if (existingUser && existingUser.id !== userId) {
      // CI 중복 처리
      return await this.handleDuplicateCi(currentUser, existingUser, kcpData);
    }

    // 정상 가입: 현재 유저에 KCP 정보 저장
    const birthDate = this.parseBirthDate(kcpData.birthDate);
    const gender = kcpData.gender === 'M' ? 'MALE' : kcpData.gender === 'F' ? 'FEMALE' : null;

    await userRepo.update(userId, {
      phoneNumber: kcpData.phoneNumber,
      ci: kcpData.ci,
      di: kcpData.di,
      realName: kcpData.realName,
      carrier: kcpData.carrier,
      isVerified: true,
      verifiedAt: new Date(),
      lastLoginAt: new Date(),
      ...(gender && { gender }),
      ...(birthDate && { birthDate }),
    });

    const updatedUser = await userRepo.findOne({ where: { id: userId } });
    if (!updatedUser) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

    const tokens = await issueTokenPair({ userId: updatedUser.id, email: updatedUser.email });
    await storeRefreshToken(updatedUser.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: updatedUser.id,
        nickname: updatedUser.nickname,
        profileImageUrl: updatedUser.profileImageUrl,
        isNewUser: true,
        isVerified: true,
        phoneNumber: kcpData.phoneNumber,
      },
      nextRoute: 'profile-setup',
    };
  }

  // ─────────────────────────────────────
  // CI 중복 처리
  // ─────────────────────────────────────

  private async handleDuplicateCi(
    currentUser: User,
    existingUser: User,
    kcpData: KcpRawResult,
  ): Promise<KcpVerifyResult> {
    const userRepo = this.dataSource.getRepository(User);
    const socialAccountRepo = this.dataSource.getRepository(SocialAccount);

    // Case 3: 기존 계정 SUSPENDED → 가입 차단
    if (existingUser.status === UserStatus.SUSPENDED) {
      // 현재 신규 유저 삭제 (트랜잭션)
      await this.dataSource.transaction(async (manager) => {
        await manager.delete(SocialAccount, { userId: currentUser.id });
        await manager.delete(User, { id: currentUser.id });
      });

      throw new AppError(ErrorCode.PHONE_NUMBER_BANNED, 403);
    }

    // Case 2: 기존 계정 WITHDRAWN → 전화번호 변형 후 신규 가입 허용
    if (existingUser.status === UserStatus.WITHDRAWN) {
      // 기존 탈퇴 계정의 phone_number 뒤에 "+0" 추가
      if (existingUser.phoneNumber) {
        await userRepo.update(existingUser.id, {
          phoneNumber: `${existingUser.phoneNumber}+0`,
        });
      }

      const birthDate = this.parseBirthDate(kcpData.birthDate);
      const gender = kcpData.gender === 'M' ? 'MALE' : kcpData.gender === 'F' ? 'FEMALE' : null;

      await userRepo.update(currentUser.id, {
        phoneNumber: kcpData.phoneNumber,
        ci: kcpData.ci,
        di: kcpData.di,
        realName: kcpData.realName,
        carrier: kcpData.carrier,
        isVerified: true,
        verifiedAt: new Date(),
        lastLoginAt: new Date(),
        ...(gender && { gender }),
        ...(birthDate && { birthDate }),
      });

      const updatedUser = await userRepo.findOne({ where: { id: currentUser.id } });
      if (!updatedUser) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

      const tokens = await issueTokenPair({ userId: updatedUser.id, email: updatedUser.email });
      await storeRefreshToken(updatedUser.id, tokens.refreshToken);

      return {
        ...tokens,
        user: {
          id: updatedUser.id,
          nickname: updatedUser.nickname,
          profileImageUrl: updatedUser.profileImageUrl,
          isNewUser: true,
          isVerified: true,
          phoneNumber: kcpData.phoneNumber,
        },
        nextRoute: 'profile-setup',
      };
    }

    // Case 1: 기존 계정 ACTIVE → 기존 계정으로 자동 로그인
    // 현재 신규 유저의 소셜 계정을 기존 유저에 연결 후 신규 유저 삭제
    await this.dataSource.transaction(async (manager) => {
      // 현재 신규 유저의 소셜 계정을 기존 유저에 재연결
      await manager.update(SocialAccount, { userId: currentUser.id }, { userId: existingUser.id });
      // 현재 신규 유저 삭제
      await manager.delete(User, { id: currentUser.id });
    });

    // 기존 계정 lastLoginAt 업데이트
    await userRepo.update(existingUser.id, { lastLoginAt: new Date() });

    const updatedExisting = await userRepo.findOne({ where: { id: existingUser.id } });
    if (!updatedExisting) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

    const tokens = await issueTokenPair({ userId: updatedExisting.id, email: updatedExisting.email });
    await storeRefreshToken(updatedExisting.id, tokens.refreshToken);

    return {
      ...tokens,
      user: {
        id: updatedExisting.id,
        nickname: updatedExisting.nickname,
        profileImageUrl: updatedExisting.profileImageUrl,
        isNewUser: false,
        isVerified: true,
        phoneNumber: updatedExisting.phoneNumber ?? kcpData.phoneNumber,
      },
      nextRoute: 'home',
    };
  }

  // ─────────────────────────────────────
  // KCP 서버 결과 조회 (서버-to-서버)
  // ─────────────────────────────────────

  private async fetchKcpResult(key: string): Promise<KcpRawResult> {
    const now = new Date();
    const kcp_merchant_time = this.formatDateTime(now);

    // 결과 조회용 서명: site_cd + key + kcp_merchant_time
    const signData = `${KCP_SITE_CD}^${key}^${kcp_merchant_time}`;
    const up_hash = createHmac('sha256', KCP_CERT_KEY)
      .update(signData)
      .digest('hex');

    const params = new URLSearchParams({
      site_cd: KCP_SITE_CD,
      up_hash,
      kcp_merchant_time,
      cert_no: key,
      req_tx: 'cert',
      cert_type: 'limit',
    });

    let response: Response;
    try {
      response = await fetch(KCP_RESULT_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
        signal: AbortSignal.timeout(10000),
      });
    } catch (e) {
      console.error('[KCP] fetchKcpResult network error:', e);
      throw new AppError(ErrorCode.KCP_SERVER_ERROR, 502);
    }

    if (!response.ok) {
      console.error('[KCP] fetchKcpResult HTTP error:', response.status);
      throw new AppError(ErrorCode.KCP_SERVER_ERROR, 502);
    }

    // KCP 응답은 URL-encoded 형식
    const rawText = await response.text();
    const result = new URLSearchParams(rawText);

    const res_cd = result.get('res_cd') ?? '';
    const res_msg = result.get('res_msg') ?? '';

    // 성공 코드: 0000
    if (res_cd !== '0000') {
      console.error(`[KCP] cert result error: res_cd=${res_cd}, res_msg=${res_msg}`);
      throw new AppError(ErrorCode.KCP_INVALID_KEY, 400, `KCP 인증 실패: ${res_msg}`);
    }

    const ci = result.get('CI_value') ?? result.get('ci_val') ?? '';
    const di = result.get('DI_value') ?? result.get('di_val') ?? '';
    const phoneNumber = result.get('phone_no') ?? '';
    const gender = result.get('sex_code') ?? '';
    const birthDate = result.get('birth_day') ?? '';
    const realName = result.get('user_name') ?? '';
    const carrier = result.get('local_code') ?? '';

    if (!ci) {
      console.error('[KCP] CI value missing in response');
      throw new AppError(ErrorCode.KCP_INVALID_KEY, 400, 'KCP 인증 결과에서 CI 값을 찾을 수 없습니다.');
    }

    return { ci, di, phoneNumber, gender, birthDate, realName, carrier };
  }

  // ─────────────────────────────────────
  // 헬퍼 메서드
  // ─────────────────────────────────────

  private formatDateTime(date: Date): string {
    const y = date.getFullYear();
    const mo = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const h = String(date.getHours()).padStart(2, '0');
    const mi = String(date.getMinutes()).padStart(2, '0');
    const s = String(date.getSeconds()).padStart(2, '0');
    return `${y}${mo}${d}${h}${mi}${s}`;
  }

  private parseBirthDate(yyyymmdd: string): Date | null {
    if (!yyyymmdd || yyyymmdd.length !== 8) return null;
    const year = parseInt(yyyymmdd.slice(0, 4), 10);
    const month = parseInt(yyyymmdd.slice(4, 6), 10) - 1;
    const day = parseInt(yyyymmdd.slice(6, 8), 10);
    const date = new Date(year, month, day);
    if (isNaN(date.getTime())) return null;
    return date;
  }
}
