import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../../config/env.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { randomUUID } from 'crypto';

// ─────────────────────────────────────
// 업로드 타입별 설정
// ─────────────────────────────────────

const UPLOAD_CONFIGS: Record<
  string,
  { maxSize: number; allowedTypes: string[]; prefix: string }
> = {
  PROFILE_IMAGE: {
    maxSize: 5 * 1024 * 1024, // 5MB
    allowedTypes: ['image/jpeg', 'image/png', 'image/webp'],
    prefix: 'profiles',
  },
  GAME_RESULT: {
    maxSize: 10 * 1024 * 1024, // 10MB
    allowedTypes: ['image/jpeg', 'image/png'],
    prefix: 'game-results',
  },
  POST_IMAGE: {
    maxSize: 10 * 1024 * 1024, // 10MB
    allowedTypes: ['image/jpeg', 'image/png', 'image/webp'],
    prefix: 'posts',
  },
  CHAT_IMAGE: {
    maxSize: 10 * 1024 * 1024, // 10MB
    allowedTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp'],
    prefix: 'chat',
  },
};

export class UploadsService {
  private s3Client: S3Client;

  constructor() {
    this.s3Client = new S3Client({
      region: env.AWS_REGION,
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }

  async getPresignedUrl(
    userId: string,
    dto: {
      fileType: string;
      contentType: string;
      fileSize: number;
    },
  ): Promise<{
    uploadUrl: string;
    fileUrl: string;
    thumbnailUrl: string | null;
    expiresIn: number;
    key: string;
  }> {
    const config = UPLOAD_CONFIGS[dto.fileType];

    if (!config) {
      throw AppError.badRequest(
        ErrorCode.UPLOAD_INVALID_TYPE,
        `지원하지 않는 파일 타입입니다: ${dto.fileType}`,
      );
    }

    // 파일 크기 검증
    if (dto.fileSize > config.maxSize) {
      throw AppError.badRequest(
        ErrorCode.UPLOAD_FILE_TOO_LARGE,
        `파일 크기가 초과되었습니다. 최대 ${config.maxSize / 1024 / 1024}MB`,
      );
    }

    // Content-Type 검증
    if (!config.allowedTypes.includes(dto.contentType)) {
      throw AppError.badRequest(
        ErrorCode.UPLOAD_INVALID_TYPE,
        `허용되지 않는 파일 형식입니다. 허용: ${config.allowedTypes.join(', ')}`,
      );
    }

    const ext = this.getExtension(dto.contentType);
    const key = `${config.prefix}/${userId}/${randomUUID()}${ext}`;
    const expiresIn = 300; // 5분

    const command = new PutObjectCommand({
      Bucket: env.AWS_S3_BUCKET,
      Key: key,
      ContentType: dto.contentType,
      ContentLength: dto.fileSize,
      Metadata: {
        userId,
        fileType: dto.fileType,
      },
    });

    const uploadUrl = await getSignedUrl(this.s3Client, command, { expiresIn });

    const cdnDomain = env.AWS_CLOUDFRONT_DOMAIN
      ? `https://${env.AWS_CLOUDFRONT_DOMAIN}`
      : `https://${env.AWS_S3_BUCKET}.s3.${env.AWS_REGION}.amazonaws.com`;

    const fileUrl = `${cdnDomain}/${key}`;

    // 이미지 파일인 경우 썸네일 URL 생성
    // 규칙: 원본 key에서 확장자 앞에 _thumb 삽입
    // 예: posts/user123/abc.jpg → posts/user123/abc_thumb.jpg
    // CloudFront + Lambda@Edge 또는 S3 Object Lambda에서 리사이징 처리
    const isImage = dto.contentType.startsWith('image/');
    let thumbnailUrl: string | null = null;
    if (isImage) {
      const thumbKey = key.replace(/(\.\w+)$/, '_thumb$1');
      thumbnailUrl = `${cdnDomain}/${thumbKey}`;
    }

    return { uploadUrl, fileUrl, thumbnailUrl, expiresIn, key };
  }

  private getExtension(contentType: string): string {
    const map: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
    };
    return map[contentType] ?? '';
  }
}
