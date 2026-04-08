import { S3Client, GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';
import { env } from '../config/env.js';

const THUMB_WIDTH = 300;
const THUMB_QUALITY = 80;

const s3 = new S3Client({
  region: env.AWS_REGION,
  credentials: {
    accessKeyId: env.AWS_ACCESS_KEY_ID,
    secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
  },
});

/**
 * S3의 원본 이미지를 다운로드 → sharp로 리사이징 → _thumb 키로 재업로드
 */
export async function generateThumbnail(key: string): Promise<string | null> {
  // _thumb 이미 포함된 키는 스킵
  if (key.includes('_thumb')) return null;

  // 이미지 확장자가 아니면 스킵
  if (!/\.(jpg|jpeg|png|webp|gif)$/i.test(key)) return null;

  try {
    // 1. 원본 다운로드
    const getCmd = new GetObjectCommand({
      Bucket: env.AWS_S3_BUCKET,
      Key: key,
    });
    const response = await s3.send(getCmd);
    const body = await response.Body?.transformToByteArray();
    if (!body) return null;

    // 2. sharp로 리사이징
    const thumbBuffer = await sharp(Buffer.from(body))
      .resize(THUMB_WIDTH, undefined, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: THUMB_QUALITY })
      .toBuffer();

    // 3. 썸네일 키 생성: abc.jpg → abc_thumb.jpg
    const thumbKey = key.replace(/(\.\w+)$/, '_thumb.jpg');

    // 4. 썸네일 업로드
    const putCmd = new PutObjectCommand({
      Bucket: env.AWS_S3_BUCKET,
      Key: thumbKey,
      Body: thumbBuffer,
      ContentType: 'image/jpeg',
      CacheControl: 'public, max-age=31536000',
    });
    await s3.send(putCmd);

    console.log(`[Thumbnail] 생성 완료: ${thumbKey} (${thumbBuffer.length} bytes)`);
    return thumbKey;
  } catch (err) {
    console.error(`[Thumbnail] 생성 실패 (${key}):`, err);
    return null;
  }
}
