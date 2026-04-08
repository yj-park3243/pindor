import { AppDataSource } from '../../config/database.js';
import {
  Pin,
  Post,
  PostImage,
  PostLike,
  Comment,
} from '../../entities/index.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { findNearbyPins } from '../../shared/utils/geo.js';
import type {
  NearbyPinsQuery,
  ListPostsQuery,
  CreatePostDto,
  UpdatePostDto,
  CreateCommentDto,
} from './pins.schema.js';

export class PinsService {
  constructor(private notificationService?: any) {}

  // ─────────────────────────────────────
  // 핀 데이터 버전 조회
  // ─────────────────────────────────────

  async getPinVersion(): Promise<string> {
    // 핀 테이블의 최신 updated_at을 버전으로 사용
    const result = await AppDataSource.query<Array<{ version: string }>>(
      `SELECT COALESCE(
        TO_CHAR(MAX(created_at), 'YYYYMMDDHH24MISS'),
        '0'
       ) AS version
       FROM pins
       WHERE is_active = TRUE AND level = 'DONG'`
    );
    return result[0]?.version ?? '0';
  }

  // ─────────────────────────────────────
  // 전체 핀 + 버전 (조건부 응답)
  // clientVersion과 서버 버전이 같으면 null 반환
  // ─────────────────────────────────────

  async getAllPinsIfChanged(clientVersion?: string): Promise<{
    version: string;
    pins: ReturnType<typeof this.formatPins> | null;
    changed: boolean;
  }> {
    const serverVersion = await this.getPinVersion();

    if (clientVersion && clientVersion === serverVersion) {
      return { version: serverVersion, pins: null, changed: false };
    }

    const pins = await this.getAllPins();
    return { version: serverVersion, pins, changed: true };
  }

  private formatPins(pins: Array<{
    id: string; name: string; slug: string; level: string;
    centerLat: number; centerLng: number; userCount: number;
  }>) {
    return pins.map((pin) => ({
      id: pin.id,
      name: pin.name,
      slug: pin.slug,
      level: pin.level,
      center: { lat: pin.centerLat, lng: pin.centerLng },
      userCount: pin.userCount,
    }));
  }

  // ─────────────────────────────────────
  // 핀 배치 조회
  // ─────────────────────────────────────

  async getPinsByIds(ids: string[]) {
    if (ids.length === 0) return [];

    const placeholders = ids.map((_, i) => `$${i + 1}`).join(',');
    const pins = await AppDataSource.query<Array<{
      id: string; name: string; slug: string; level: string;
      centerLat: number; centerLng: number; userCount: number;
    }>>(
      `SELECT id, name, slug, level,
              ST_Y(center::geometry) AS "centerLat",
              ST_X(center::geometry) AS "centerLng",
              user_count AS "userCount"
       FROM pins
       WHERE id IN (${placeholders}) AND is_active = TRUE`,
      ids,
    );

    return pins.map((pin) => ({
      id: pin.id,
      name: pin.name,
      slug: pin.slug,
      level: pin.level,
      center: { lat: pin.centerLat, lng: pin.centerLng },
      userCount: pin.userCount,
    }));
  }

  // ─────────────────────────────────────
  // 전체 핀 목록 (DONG 레벨만, 이름순)
  // ─────────────────────────────────────

  async getAllPins() {
    const pins = await AppDataSource.query<Array<{
      id: string; name: string; slug: string; level: string;
      centerLat: number; centerLng: number; userCount: number;
    }>>(
      `SELECT id, name, slug, level,
              ST_Y(center::geometry) AS "centerLat",
              ST_X(center::geometry) AS "centerLng",
              user_count AS "userCount"
       FROM pins
       WHERE is_active = TRUE AND level = 'DONG'
       ORDER BY name ASC`
    );

    return pins.map((pin) => ({
      id: pin.id,
      name: pin.name,
      slug: pin.slug,
      level: pin.level,
      center: { lat: pin.centerLat, lng: pin.centerLng },
      userCount: pin.userCount,
    }));
  }

  // ─────────────────────────────────────
  // 주변 핀 탐색
  // ─────────────────────────────────────

  async getNearbyPins(query: NearbyPinsQuery) {
    const pins = await findNearbyPins(query.latitude, query.longitude, query.radius);

    return pins.map((pin) => ({
      id: pin.id,
      name: pin.name,
      slug: pin.slug,
      level: pin.level,
      center: { lat: pin.centerLat, lng: pin.centerLng },
      userCount: pin.userCount,
      distanceKm: Math.round(pin.distanceMeters / 100) / 10,
    }));
  }

  // ─────────────────────────────────────
  // 핀 상세 조회
  // ─────────────────────────────────────

  async getPin(pinId: string) {
    const pinRepo = AppDataSource.getRepository(Pin);
    const postRepo = AppDataSource.getRepository(Post);

    const pin = await pinRepo.findOne({ where: { id: pinId } });

    if (!pin) {
      throw AppError.notFound(ErrorCode.PIN_NOT_FOUND);
    }

    if (!pin.isActive) {
      throw AppError.badRequest(ErrorCode.PIN_NOT_ACTIVE);
    }

    // 핀 중심 좌표 조회 (PostGIS)
    const centerRows = await AppDataSource.query<Array<{ lat: number; lng: number }>>(
      `
      SELECT
        ST_Y(center::geometry) AS lat,
        ST_X(center::geometry) AS lng
      FROM pins
      WHERE id = $1::uuid
      LIMIT 1
      `,
      [pinId],
    );

    const center = centerRows[0] ?? null;

    // 게시글 수 조회
    const postCount = await postRepo.count({ where: { pinId, isDeleted: false } });

    // 랭킹 엔트리 수 조회
    const [{ rankingCount }] = await AppDataSource.query<Array<{ rankingCount: string }>>(
      `SELECT COUNT(*) AS "rankingCount" FROM ranking_entries WHERE pin_id = $1::uuid`,
      [pinId],
    );

    return {
      id: pin.id,
      name: pin.name,
      slug: pin.slug,
      level: pin.level,
      userCount: pin.userCount,
      center: center ? { lat: center.lat, lng: center.lng } : null,
      postCount,
      rankingCount: parseInt(rankingCount, 10),
      createdAt: pin.createdAt,
    };
  }

  // ─────────────────────────────────────
  // 게시글 목록
  // ─────────────────────────────────────

  async getPosts(pinId: string, query: ListPostsQuery) {
    const pinRepo = AppDataSource.getRepository(Pin);
    const postRepo = AppDataSource.getRepository(Post);

    const pin = await pinRepo.findOne({ where: { id: pinId } });
    if (!pin) throw AppError.notFound(ErrorCode.PIN_NOT_FOUND);

    const qb = postRepo
      .createQueryBuilder('post')
      .leftJoinAndSelect('post.author', 'author')
      .leftJoinAndSelect('post.images', 'images', 'images.sortOrder = 0')
      .where('post.pinId = :pinId', { pinId })
      .andWhere('post.isDeleted = false');

    if (query.category) {
      qb.andWhere('post.category = :category', { category: query.category });
    }
    if (query.cursor) {
      qb.andWhere('post.createdAt < :cursor', { cursor: new Date(query.cursor) });
    }

    qb.orderBy('post.createdAt', 'DESC').take(query.limit + 1);

    const posts = await qb.getMany();

    // 댓글 수 조회 (isDeleted = false 조건)
    const postIds = posts.map((p) => p.id);
    const commentCounts: Record<string, number> = {};
    if (postIds.length > 0) {
      const rows = await AppDataSource.query<Array<{ postId: string; count: string }>>(
        `SELECT post_id AS "postId", COUNT(*) AS count
         FROM comments
         WHERE post_id = ANY($1::uuid[]) AND is_deleted = false
         GROUP BY post_id`,
        [postIds],
      );
      for (const row of rows) {
        commentCounts[row.postId] = parseInt(row.count, 10);
      }
    }

    const hasMore = posts.length > query.limit;
    const items = hasMore ? posts.slice(0, query.limit) : posts;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    const result = items.map((p) => ({
      ...p,
      commentCount: commentCounts[p.id] ?? 0,
    }));

    return { items: result, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 게시글 상세
  // ─────────────────────────────────────

  async getPost(pinId: string, postId: string, userId?: string) {
    const postRepo = AppDataSource.getRepository(Post);
    const postLikeRepo = AppDataSource.getRepository(PostLike);

    const post = await postRepo
      .createQueryBuilder('post')
      .leftJoinAndSelect('post.author', 'author')
      .leftJoinAndSelect('post.images', 'images')
      .where('post.id = :postId', { postId })
      .andWhere('post.pinId = :pinId', { pinId })
      .andWhere('post.isDeleted = false')
      .orderBy('images.sortOrder', 'ASC')
      .getOne();

    if (!post) throw AppError.notFound(ErrorCode.POST_NOT_FOUND);

    // 조회수 증가
    await postRepo
      .createQueryBuilder()
      .update(Post)
      .set({ viewCount: () => 'view_count + 1' })
      .where('id = :postId', { postId })
      .execute();

    // 댓글 수 조회 (isDeleted = false)
    const [{ commentCount }] = await AppDataSource.query<Array<{ commentCount: string }>>(
      `SELECT COUNT(*) AS "commentCount" FROM comments WHERE post_id = $1::uuid AND is_deleted = false`,
      [postId],
    );

    // 좋아요 수 조회
    const likeCount = await postLikeRepo.count({ where: { postId } });

    // 내가 좋아요 눌렀는지 확인
    let isLiked = false;
    if (userId) {
      const like = await postLikeRepo.findOne({
        where: { postId, userId },
      });
      isLiked = !!like;
    }

    return {
      ...post,
      isLiked,
      commentCount: parseInt(commentCount, 10),
      likeCount,
    };
  }

  // ─────────────────────────────────────
  // 게시글 작성
  // ─────────────────────────────────────

  async createPost(pinId: string, userId: string, dto: CreatePostDto) {
    const pinRepo = AppDataSource.getRepository(Pin);
    const postRepo = AppDataSource.getRepository(Post);
    const postImageRepo = AppDataSource.getRepository(PostImage);

    const pin = await pinRepo.findOne({ where: { id: pinId } });
    if (!pin || !pin.isActive) throw AppError.notFound(ErrorCode.PIN_NOT_FOUND);

    const post = postRepo.create({
      pinId,
      authorId: userId,
      title: dto.title,
      content: dto.content,
      category: dto.category,
    });

    const savedPost = await postRepo.save(post);

    // 이미지 저장
    if (dto.imageUrls && dto.imageUrls.length > 0) {
      const images = dto.imageUrls.map((url, idx) =>
        postImageRepo.create({
          postId: savedPost.id,
          imageUrl: url,
          sortOrder: idx,
        }),
      );
      await postImageRepo.save(images);
    }

    // 관계 포함하여 재조회
    const result = await postRepo.findOne({
      where: { id: savedPost.id },
      relations: ['author', 'images'],
    });

    return result;
  }

  // ─────────────────────────────────────
  // 게시글 수정
  // ─────────────────────────────────────

  async updatePost(
    pinId: string,
    postId: string,
    userId: string,
    dto: UpdatePostDto,
  ) {
    const postRepo = AppDataSource.getRepository(Post);

    const post = await postRepo.findOne({
      where: { id: postId, pinId, isDeleted: false },
    });

    if (!post) throw AppError.notFound(ErrorCode.POST_NOT_FOUND);
    if (post.authorId !== userId) throw AppError.forbidden(ErrorCode.POST_NOT_AUTHOR);

    const updateData: Partial<Post> = {};
    if (dto.title) updateData.title = dto.title;
    if (dto.content) updateData.content = dto.content;
    if (dto.category) updateData.category = dto.category;

    await postRepo.update(postId, updateData);

    return postRepo.findOne({ where: { id: postId } });
  }

  // ─────────────────────────────────────
  // 게시글 삭제 (소프트 삭제)
  // ─────────────────────────────────────

  async deletePost(pinId: string, postId: string, userId: string) {
    const postRepo = AppDataSource.getRepository(Post);

    const post = await postRepo.findOne({
      where: { id: postId, pinId, isDeleted: false },
    });

    if (!post) throw AppError.notFound(ErrorCode.POST_NOT_FOUND);
    if (post.authorId !== userId) throw AppError.forbidden(ErrorCode.POST_NOT_AUTHOR);

    await postRepo.update(postId, { isDeleted: true });
  }

  // ─────────────────────────────────────
  // 댓글 작성
  // ─────────────────────────────────────

  async createComment(
    pinId: string,
    postId: string,
    userId: string,
    dto: CreateCommentDto,
  ) {
    const postRepo = AppDataSource.getRepository(Post);
    const commentRepo = AppDataSource.getRepository(Comment);

    const post = await postRepo.findOne({
      where: { id: postId, pinId, isDeleted: false },
    });

    if (!post) throw AppError.notFound(ErrorCode.POST_NOT_FOUND);

    // 대댓글 깊이 제한 (2depth)
    if (dto.parentId) {
      const parent = await commentRepo.findOne({ where: { id: dto.parentId } });

      if (!parent) throw AppError.notFound(ErrorCode.COMMENT_NOT_FOUND);

      if (parent.parentId) {
        throw AppError.badRequest(
          ErrorCode.COMMENT_DEPTH_EXCEEDED,
          '대댓글에는 답글을 달 수 없습니다.',
        );
      }
    }

    const comment = commentRepo.create({
      postId,
      authorId: userId,
      content: dto.content,
      parentId: dto.parentId,
    });

    const [savedComment] = await Promise.all([
      commentRepo.save(comment),
      // 댓글 수 증가
      postRepo
        .createQueryBuilder()
        .update(Post)
        .set({ commentCount: () => 'comment_count + 1' })
        .where('id = :postId', { postId })
        .execute(),
    ]);

    // 관계 포함하여 재조회
    const result = await commentRepo.findOne({
      where: { id: savedComment.id },
      relations: ['author'],
    });

    // 게시글 작성자에게 알림 (자신의 글이 아닐 경우)
    if (post.authorId !== userId && this.notificationService) {
      await this.notificationService.send({
        userId: post.authorId,
        type: 'COMMUNITY_REPLY',
        title: '댓글이 달렸습니다',
        body: dto.content.substring(0, 100),
        data: {
          pinId,
          postId,
          deepLink: `/pins/${pinId}/posts/${postId}`,
        },
      });
    }

    return result;
  }

  // ─────────────────────────────────────
  // 댓글 목록
  // ─────────────────────────────────────

  async getComments(
    postId: string,
    opts: { cursor?: string; limit?: number } = {},
  ) {
    const { cursor, limit = 20 } = opts;
    const commentRepo = AppDataSource.getRepository(Comment);

    const qb = commentRepo
      .createQueryBuilder('comment')
      .leftJoinAndSelect('comment.author', 'author')
      .leftJoinAndSelect('comment.replies', 'replies', 'replies.isDeleted = false')
      .leftJoinAndSelect('replies.author', 'repliesAuthor')
      .where('comment.postId = :postId', { postId })
      .andWhere('comment.isDeleted = false')
      .andWhere('comment.parentId IS NULL')
      .orderBy('comment.createdAt', 'ASC')
      .addOrderBy('replies.createdAt', 'ASC')
      .take(limit + 1);

    if (cursor) {
      qb.andWhere('comment.createdAt > :cursor', { cursor: new Date(cursor) });
    }

    const comments = await qb.getMany();

    const hasMore = comments.length > limit;
    const items = hasMore ? comments.slice(0, limit) : comments;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 게시글 좋아요 토글
  // ─────────────────────────────────────

  async toggleLike(pinId: string, postId: string, userId: string) {
    const postRepo = AppDataSource.getRepository(Post);
    const postLikeRepo = AppDataSource.getRepository(PostLike);

    const post = await postRepo.findOne({
      where: { id: postId, pinId, isDeleted: false },
    });

    if (!post) throw AppError.notFound(ErrorCode.POST_NOT_FOUND);

    const existing = await postLikeRepo.findOne({ where: { postId, userId } });

    if (existing) {
      // 좋아요 취소
      await AppDataSource.transaction(async (manager) => {
        await manager.delete(PostLike, { postId, userId });
        await manager
          .createQueryBuilder()
          .update(Post)
          .set({ likeCount: () => 'like_count - 1' })
          .where('id = :postId', { postId })
          .execute();
      });
      return { liked: false };
    } else {
      // 좋아요 추가
      await AppDataSource.transaction(async (manager) => {
        await manager.save(PostLike, manager.create(PostLike, { postId, userId }));
        await manager
          .createQueryBuilder()
          .update(Post)
          .set({ likeCount: () => 'like_count + 1' })
          .where('id = :postId', { postId })
          .execute();
      });
      return { liked: true };
    }
  }
}
