import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
  Index,
} from 'typeorm';
import { SportType } from './enums.js';
import type { Pin } from './pin.entity.js';
import type { SportsProfile } from './sports-profile.entity.js';
import type { User } from './user.entity.js';

// ─────────────────────────────────────
// 핀 랭킹 일일 스냅샷
// - 매일 KST 00:00(UTC 15:00)에 ranking_entries를 복사
// - 다음 날 18:00 rank-drop 워커가 어제 vs 오늘 비교에 사용
// ─────────────────────────────────────
@Unique(['pinId', 'sportsProfileId', 'sportType', 'snapshotDate'])
@Index('idx_prs_user_date', ['userId', 'snapshotDate'])
@Entity('pin_ranking_snapshots')
export class PinRankingSnapshot {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'sports_profile_id', type: 'uuid' })
  sportsProfileId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ type: 'int' })
  rank!: number;

  @Column({ type: 'int' })
  score!: number;

  @Column({ name: 'snapshot_date', type: 'date' })
  snapshotDate!: string; // "YYYY-MM-DD"

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('Pin', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;

  @ManyToOne('SportsProfile', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'sports_profile_id' })
  sportsProfile!: SportsProfile;

  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
