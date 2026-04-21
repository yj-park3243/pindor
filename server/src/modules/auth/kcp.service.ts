import { DataSource } from 'typeorm';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { issueTokenPair } from '../../shared/utils/jwt.js';
import { redis } from '../../config/redis.js';
import { User, SocialAccount } from '../../entities/index.js';
import { UserStatus } from '../../entities/enums.js';
import type { KcpRawResult, KcpVerifyResult } from './kcp.schema.js';
import { encryptJson, decryptJson } from './kcp-crypto.js';

// KCP 본인확인 V2 (API 기반)
// - 1단계: certDataReg.do로 거래등록 → call_url, reg_cert_key 수신
// - 2단계: WebView가 call_url로 form submit → KCP 인증창 → Ret_URL 콜백
// - 3단계: getCertData.do로 결과 조회 → decryptJson으로 CI/DI 복호화
const KCP_SITE_CD = 'ALQ1Q';
const KCP_ENC_KEY =
  'eaa433b5da2ae426aa0d637e46c5644436c104870fa1eabd4af6e7f26e9536df';
const KCP_CERT_REG_URL =
  'https://cert.kcp.co.kr/api/reg/certDataReg.do';
const KCP_CERT_GET_URL =
  'https://cert.kcp.co.kr/api/query/getCertData.do';
const KCP_RET_URL = 'https://api.pins.kr/v1/auth/kcp/callback';

export class KcpService {
  constructor(private dataSource: DataSource) {}

  // ─────────────────────────────────────
  // 1. 거래등록 + WebView용 HTML form 반환
  // ─────────────────────────────────────

  async generateCertForm(userId: string, returnUrl: string): Promise<string> {
    const ordr_idxx = `ORD${Date.now()}${Math.floor(Math.random() * 1000)}`;

    // KCP Ret_URL 콜백은 res_cd만 담고 ordr_idxx/reg_cert_key는 주지 않음 →
    // Ret_URL에 ordr_idxx를 쿼리로 붙여 식별자 유지
    const baseRet = returnUrl.startsWith('http') ? returnUrl : KCP_RET_URL;
    const ret = `${baseRet}${baseRet.includes('?') ? '&' : '?'}ordr_idxx=${ordr_idxx}`;

    // KCP 거래등록 요청 (암호화된 body)
    const regPayload = {
      site_cd: KCP_SITE_CD,
      ordr_idxx,
      Ret_URL: ret,
      web_siteid: '',
      param_opt_1: '',
      param_opt_2: '',
      param_opt_3: '',
    };
    const { enc_data, rv } = encryptJson(regPayload, KCP_ENC_KEY, KCP_SITE_CD);

    let regResponse: Response;
    try {
      regResponse = await fetch(KCP_CERT_REG_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          site_cd: KCP_SITE_CD,
          rv,
        },
        body: enc_data,
        signal: AbortSignal.timeout(10000),
      });
    } catch (e: any) {
      console.error('[KCP CertReg] network error:', e);
      throw new AppError(
        ErrorCode.KCP_SERVER_ERROR,
        502,
        'KCP 거래등록 서버에 연결할 수 없습니다.',
      );
    }

    const regResult = (await regResponse.json()) as Record<string, any>;
    console.info('[KCP CertReg] response:', JSON.stringify(regResult));

    if (regResult.res_cd !== '0000') {
      throw new AppError(
        ErrorCode.KCP_SERVER_ERROR,
        502,
        `KCP 거래등록 실패: ${regResult.res_msg || regResult.res_cd}`,
      );
    }

    const call_url: string = regResult.call_url;
    const reg_cert_key: string = regResult.reg_cert_key;

    // ordr_idxx → {userId, reg_cert_key} 매핑 저장 (30분 TTL)
    // 콜백 시점에 reg_cert_key를 Redis에서 복원해 getCertData.do 호출
    await redis.setex(
      `kcp:order:${ordr_idxx}`,
      30 * 60,
      JSON.stringify({ userId, reg_cert_key }),
    );

    // WebView가 자동으로 submit할 HTML form
    // (KCP 인증창이 form post 받아 KCP 인증 UI 표시)
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>본인인증</title>
</head>
<body>
  <form id="form_auth" name="form_auth" method="post" action="${call_url}">
    <input type="hidden" name="call_url" value="${call_url}">
    <input type="hidden" name="reg_cert_key" value="${reg_cert_key}">
    <input type="hidden" name="kcp_page_submit_yn" value="Y">
  </form>
  <script>document.getElementById('form_auth').submit();</script>
</body>
</html>`;
  }

  // ─────────────────────────────────────
  // 2. 인증 완료 콜백 — Ret_URL로 POST 받음
  // ─────────────────────────────────────

  async handleCallback(
    body: Record<string, any>,
    query: Record<string, any> = {},
  ): Promise<{ userId: string; kcpData: KcpRawResult }> {
    const { res_cd, res_msg } = body;
    // KCP는 Ret_URL 콜백 body에 res_cd만 담아 보냄.
    // ordr_idxx는 Ret_URL 쿼리로 유지한 값을 사용한다.
    const ordr_idxx: string | undefined = query.ordr_idxx || body.ordr_idxx;

    console.info(
      `[KCP Callback] res_cd=${res_cd}, ordr_idxx=${ordr_idxx}, bodyKeys=${Object.keys(body)}`,
    );

    // 사용자 취소
    if (res_cd === '9999') {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        '사용자가 본인인증을 취소했습니다.',
      );
    }

    if (res_cd !== '0000') {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        `KCP 인증 실패: ${res_msg || res_cd}`,
      );
    }

    if (!ordr_idxx) {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        'KCP 콜백 ordr_idxx가 누락되었습니다.',
      );
    }

    const cached = await redis.get(`kcp:order:${ordr_idxx}`);
    if (!cached) {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        '인증 세션이 만료되었습니다.',
      );
    }

    let userId: string;
    let reg_cert_key: string;
    try {
      const parsed = JSON.parse(cached) as {
        userId: string;
        reg_cert_key: string;
      };
      userId = parsed.userId;
      reg_cert_key = parsed.reg_cert_key;
    } catch {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        '인증 세션 데이터가 손상되었습니다.',
      );
    }

    if (!reg_cert_key) {
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        '거래등록 키가 없습니다.',
      );
    }

    const decrypted = await this.fetchAndDecryptCertData(
      ordr_idxx,
      reg_cert_key,
    );

    await redis.del(`kcp:order:${ordr_idxx}`);

    return { userId, kcpData: decrypted };
  }

  // ─────────────────────────────────────
  // 3. 결과 조회 + 복호화
  // ─────────────────────────────────────

  private async fetchAndDecryptCertData(
    ordr_idxx: string,
    reg_cert_key: string,
  ): Promise<KcpRawResult> {
    const reqBody = {
      site_cd: KCP_SITE_CD,
      reg_cert_key,
      ordr_idxx,
    };

    let response: Response;
    try {
      response = await fetch(KCP_CERT_GET_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          site_cd: KCP_SITE_CD,
        },
        body: JSON.stringify(reqBody),
        signal: AbortSignal.timeout(10000),
      });
    } catch (e: any) {
      console.error('[KCP CertGet] network error:', e);
      throw new AppError(
        ErrorCode.KCP_SERVER_ERROR,
        502,
        'KCP 결과 조회 서버에 연결할 수 없습니다.',
      );
    }

    const result = (await response.json()) as Record<string, any>;
    console.info(
      '[KCP CertGet] res_cd=',
      result.res_cd,
      'res_msg=',
      result.res_msg,
    );

    if (result.res_cd !== '0000') {
      throw new AppError(
        ErrorCode.KCP_SERVER_ERROR,
        502,
        `KCP 결과 조회 실패: ${result.res_msg || result.res_cd}`,
      );
    }

    // 복호화
    const decrypted = decryptJson<Record<string, string>>(
      result.enc_cert_data,
      result.rv,
      KCP_ENC_KEY,
      KCP_SITE_CD,
    );

    const ci = decrypted.CI || '';
    const di = decrypted.DI || '';
    const phoneNumber = decrypted.phone_no || '';
    const realName = decrypted.user_name || '';
    const birthDate = decrypted.birth_day || '';
    const gender = decrypted.gender || decrypted.sex_code || '';
    const carrier = decrypted.comm_id || decrypted.local_code || '';

    if (!ci && !phoneNumber) {
      console.error(
        '[KCP CertGet] No CI/phone in decrypted data:',
        Object.keys(decrypted),
      );
      throw new AppError(
        ErrorCode.KCP_INVALID_KEY,
        400,
        'KCP 인증 결과에서 사용자 정보를 찾을 수 없습니다.',
      );
    }

    return { ci, di, phoneNumber, gender, birthDate, realName, carrier };
  }

  // ─────────────────────────────────────
  // 4. 유저 정보 저장 + CI 중복 처리
  // ─────────────────────────────────────

  async verifyCert(
    userId: string,
    kcpData: KcpRawResult,
  ): Promise<KcpVerifyResult> {
    const userRepo = this.dataSource.getRepository(User);

    const existingUser = kcpData.ci
      ? await userRepo.findOne({ where: { ci: kcpData.ci } })
      : null;

    const currentUser = await userRepo.findOne({ where: { id: userId } });
    if (!currentUser) {
      throw new AppError(ErrorCode.USER_NOT_FOUND, 404);
    }

    if (existingUser && existingUser.id !== userId) {
      return await this.handleDuplicateCi(currentUser, existingUser, kcpData);
    }

    const birthDate = this.parseBirthDate(kcpData.birthDate);
    const gender =
      kcpData.gender === 'M' || kcpData.gender === '1'
        ? 'MALE'
        : kcpData.gender === 'F' || kcpData.gender === '0'
          ? 'FEMALE'
          : null;

    await userRepo.update(userId, {
      phoneNumber: kcpData.phoneNumber,
      ci: kcpData.ci || undefined,
      di: kcpData.di || undefined,
      realName: kcpData.realName || undefined,
      carrier: kcpData.carrier || undefined,
      isVerified: true,
      verifiedAt: new Date(),
      lastLoginAt: new Date(),
      ...(gender && { gender }),
      ...(birthDate && { birthDate }),
    });

    const updatedUser = await userRepo.findOne({ where: { id: userId } });
    if (!updatedUser) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

    const tokens = await issueTokenPair({
      userId: updatedUser.id,
      email: updatedUser.email,
    });
    await redis.setex(
      `refresh_token:${updatedUser.id}`,
      30 * 24 * 3600,
      tokens.refreshToken,
    );

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
  // CI 중복 처리 (기존과 동일)
  // ─────────────────────────────────────

  private async handleDuplicateCi(
    currentUser: User,
    existingUser: User,
    kcpData: KcpRawResult,
  ): Promise<KcpVerifyResult> {
    const userRepo = this.dataSource.getRepository(User);

    if (existingUser.status === UserStatus.SUSPENDED) {
      await this.dataSource.transaction(async (manager) => {
        await manager.delete(SocialAccount, { userId: currentUser.id });
        await manager.delete(User, { id: currentUser.id });
      });
      throw new AppError(ErrorCode.PHONE_NUMBER_BANNED, 403);
    }

    if (existingUser.status === UserStatus.WITHDRAWN) {
      if (existingUser.phoneNumber) {
        await userRepo.update(existingUser.id, {
          phoneNumber: `${existingUser.phoneNumber}+0`,
        });
      }

      const birthDate = this.parseBirthDate(kcpData.birthDate);
      const gender =
        kcpData.gender === 'M' || kcpData.gender === '1'
          ? 'MALE'
          : kcpData.gender === 'F' || kcpData.gender === '0'
            ? 'FEMALE'
            : null;

      await userRepo.update(currentUser.id, {
        phoneNumber: kcpData.phoneNumber,
        ci: kcpData.ci || undefined,
        di: kcpData.di || undefined,
        realName: kcpData.realName || undefined,
        carrier: kcpData.carrier || undefined,
        isVerified: true,
        verifiedAt: new Date(),
        lastLoginAt: new Date(),
        ...(gender && { gender }),
        ...(birthDate && { birthDate }),
      });

      const updatedUser = await userRepo.findOne({
        where: { id: currentUser.id },
      });
      if (!updatedUser) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

      const tokens = await issueTokenPair({
        userId: updatedUser.id,
        email: updatedUser.email,
      });
      await redis.setex(
        `refresh_token:${updatedUser.id}`,
        30 * 24 * 3600,
        tokens.refreshToken,
      );

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

    // ACTIVE → 기존 계정으로 자동 로그인
    await this.dataSource.transaction(async (manager) => {
      await manager.update(
        SocialAccount,
        { userId: currentUser.id },
        { userId: existingUser.id },
      );
      await manager.delete(User, { id: currentUser.id });
    });

    await userRepo.update(existingUser.id, { lastLoginAt: new Date() });

    const updatedExisting = await userRepo.findOne({
      where: { id: existingUser.id },
    });
    if (!updatedExisting) throw new AppError(ErrorCode.USER_NOT_FOUND, 404);

    const tokens = await issueTokenPair({
      userId: updatedExisting.id,
      email: updatedExisting.email,
    });
    await redis.setex(
      `refresh_token:${updatedExisting.id}`,
      30 * 24 * 3600,
      tokens.refreshToken,
    );

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
