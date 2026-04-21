import {
  createCipheriv,
  createDecipheriv,
  pbkdf2Sync,
  randomBytes,
} from 'crypto';

// KCP 본인확인 V2 (NODE_KCP_API_PERSON_VERIFICATION_V2) 암호화 로직 TS 포팅
// - PBKDF2(SHA-256, 10000 iter, 256-bit)으로 key/iv 유도
// - AES-256-CBC + 수동 PKCS 패딩

const ITERATIONS = 10000;
const KEY_BYTES = 32; // 256 bit

function pbkdf2(password: Buffer, salt: Buffer): Buffer {
  return pbkdf2Sync(password, salt, ITERATIONS, KEY_BYTES, 'sha256');
}

function encryptAes(data: Buffer, key: Buffer, iv: Buffer): Buffer {
  const BLOCK = 16;
  const padLen = BLOCK - (data.length % BLOCK);
  const padded = Buffer.concat([data, Buffer.alloc(padLen, padLen)]);
  const cipher = createCipheriv('aes-256-cbc', key, iv);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(padded), cipher.final()]);
}

function decryptAes(data: Buffer, key: Buffer, iv: Buffer): Buffer {
  const decipher = createDecipheriv('aes-256-cbc', key, iv);
  decipher.setAutoPadding(false);
  const dec = Buffer.concat([decipher.update(data), decipher.final()]);
  const padLen = dec[dec.length - 1];
  return dec.subarray(0, dec.length - padLen);
}

export function encryptJson(
  payload: unknown,
  encKey: string,
  siteCd: string,
): { enc_data: string; rv: string } {
  const str = typeof payload === 'string' ? payload : JSON.stringify(payload);
  const rv = randomBytes(16);
  const key = pbkdf2(Buffer.from(encKey, 'utf8'), rv);
  const ivFull = pbkdf2(Buffer.from(siteCd, 'utf8'), rv);
  const iv = ivFull.subarray(0, 16);
  const enc = encryptAes(Buffer.from(str, 'utf8'), key, iv);
  return {
    enc_data: enc.toString('base64'),
    rv: rv.toString('base64'),
  };
}

export function decryptJson<T = Record<string, unknown>>(
  encData: string,
  rvBase64: string,
  encKey: string,
  siteCd: string,
): T {
  const rv = Buffer.from(rvBase64, 'base64');
  const key = pbkdf2(Buffer.from(encKey, 'utf8'), rv);
  const ivFull = pbkdf2(Buffer.from(siteCd, 'utf8'), rv);
  const iv = ivFull.subarray(0, 16);
  const enc = Buffer.from(encData, 'base64');
  const dec = decryptAes(enc, key, iv);
  return JSON.parse(dec.toString('utf8')) as T;
}
