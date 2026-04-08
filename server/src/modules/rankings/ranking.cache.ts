import { Redis } from 'ioredis';

// ─────────────────────────────────────
// Redis Sorted Set 랭킹 관리
// PRD 섹션 5.4 Redis 랭킹 구조 구현
// Key: ranking:{pinId}:{sportType}
// ─────────────────────────────────────

const RANKING_TTL = 86400; // 24시간

export class RankingCache {
  constructor(private redis: Redis) {}

  /**
   * 특정 핀/종목 랭킹 점수 업데이트
   */
  async updateScore(
    pinId: string,
    sportType: string,
    sportsProfileId: string,
    score: number,
  ): Promise<void> {
    const key = this.getKey(pinId, sportType);
    await this.redis.zadd(key, score, sportsProfileId);
    await this.redis.expire(key, RANKING_TTL);
  }

  /**
   * 핀/종목 랭킹 조회 (높은 점수 순)
   */
  async getTopRanking(
    pinId: string,
    sportType: string,
    limit = 50,
  ): Promise<Array<{ sportsProfileId: string; score: number; rank: number }>> {
    const key = this.getKey(pinId, sportType);
    const result = await this.redis.zrevrangebyscore(
      key,
      '+inf',
      '-inf',
      'WITHSCORES',
      'LIMIT',
      0,
      limit,
    );

    return this.parseResult(result);
  }

  /**
   * 특정 사용자의 핀 내 랭킹 조회
   */
  async getUserRank(
    pinId: string,
    sportType: string,
    sportsProfileId: string,
  ): Promise<{ rank: number | null; score: number | null }> {
    const key = this.getKey(pinId, sportType);

    const [rankResult, scoreResult] = await Promise.all([
      this.redis.zrevrank(key, sportsProfileId),
      this.redis.zscore(key, sportsProfileId),
    ]);

    return {
      rank: rankResult !== null ? rankResult + 1 : null,
      score: scoreResult !== null ? Number(scoreResult) : null,
    };
  }

  /**
   * 전국 랭킹 (national:${sportType})
   */
  async updateNationalScore(
    sportType: string,
    sportsProfileId: string,
    score: number,
  ): Promise<void> {
    const key = `ranking:national:${sportType}`;
    await this.redis.zadd(key, score, sportsProfileId);
    await this.redis.expire(key, RANKING_TTL * 7); // 7일 TTL
  }

  async getNationalRanking(
    sportType: string,
    offset: number,
    limit: number,
  ): Promise<Array<{ sportsProfileId: string; score: number; rank: number }>> {
    const key = `ranking:national:${sportType}`;
    const result = await this.redis.zrevrangebyscore(
      key,
      '+inf',
      '-inf',
      'WITHSCORES',
      'LIMIT',
      offset,
      limit,
    );
    return this.parseResult(result, offset);
  }

  /**
   * 핀 랭킹 전체 삭제 (재빌드용)
   */
  async clearPinRanking(pinId: string, sportType: string): Promise<void> {
    const key = this.getKey(pinId, sportType);
    await this.redis.del(key);
  }

  /**
   * 사용자를 여러 핀 랭킹에서 제거
   */
  async removeUserFromRankings(
    pinIds: string[],
    sportType: string,
    sportsProfileId: string,
  ): Promise<void> {
    const pipeline = this.redis.pipeline();
    for (const pinId of pinIds) {
      pipeline.zrem(this.getKey(pinId, sportType), sportsProfileId);
    }
    await pipeline.exec();
  }

  // ─────────────────────────────────────
  // Private 헬퍼
  // ─────────────────────────────────────

  private getKey(pinId: string, sportType: string): string {
    return `ranking:${pinId}:${sportType}`;
  }

  private parseResult(
    result: string[],
    offset = 0,
  ): Array<{ sportsProfileId: string; score: number; rank: number }> {
    const entries: Array<{ sportsProfileId: string; score: number; rank: number }> = [];

    for (let i = 0; i < result.length; i += 2) {
      entries.push({
        sportsProfileId: result[i],
        score: Number(result[i + 1]),
        rank: offset + Math.floor(i / 2) + 1,
      });
    }

    return entries;
  }
}
