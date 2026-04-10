import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import { SportType, Tier } from './enums.js';
import type { User } from './user.entity.js';

@Entity('sports_profiles')
@Unique(['userId', 'sportType'])
export class SportsProfile {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ name: 'display_name', type: 'varchar', length: 50, nullable: true })
  displayName!: string | null;

  @Column({ name: 'match_message', type: 'varchar', length: 100, nullable: true })
  matchMessage!: string | null;

  @Column({ name: 'g_handicap', type: 'decimal', precision: 4, scale: 1, nullable: true })
  gHandicap!: number | null;

  @Column({ name: 'initial_score', type: 'int', default: 1000 })
  initialScore!: number;

  @Column({ name: 'current_score', type: 'int', default: 1000 })
  currentScore!: number;

  @Column({ type: 'enum', enum: Tier, enumName: 'Tier', default: Tier.BRONZE })
  tier!: Tier;

  @Column({ name: 'is_verified', type: 'boolean', default: false })
  isVerified!: boolean;

  @Column({ name: 'games_played', type: 'int', default: 0 })
  gamesPlayed!: number;

  @Column({ type: 'int', default: 0 })
  wins!: number;

  @Column({ type: 'int', default: 0 })
  losses!: number;

  @Column({ type: 'int', default: 0 })
  draws!: number;

  @Column({ name: 'win_streak', type: 'int', default: 0 })
  winStreak!: number;

  @Column({ name: 'no_show_count', type: 'int', default: 0 })
  noShowCount!: number;

  @Column({ name: 'match_ban_until', type: 'timestamptz', nullable: true })
  matchBanUntil!: Date | null;

  @Column({ name: 'casual_score', type: 'int', default: 1000 })
  casualScore!: number;

  @Column({ name: 'casual_win', type: 'int', default: 0 })
  casualWin!: number;

  @Column({ name: 'casual_loss', type: 'int', default: 0 })
  casualLoss!: number;

  @Column({ name: 'extra_data', type: 'jsonb', default: {} })
  extraData!: Record<string, unknown>;

  // Glicko-2 rating parameters
  @Column({ name: 'glicko_rating', type: 'float', default: 1000.0 })
  glickoRating!: number;

  @Column({ name: 'glicko_rd', type: 'float', default: 350.0 })
  glickoRd!: number;

  @Column({ name: 'glicko_volatility', type: 'float', default: 0.06 })
  glickoVolatility!: number;

  @Column({ name: 'glicko_last_updated_at', type: 'timestamptz', nullable: true })
  glickoLastUpdatedAt!: Date | null;

  @Column({ name: 'display_score', type: 'int', default: 1000 })
  displayScore!: number;

  @Column({ name: 'is_placement', type: 'boolean', default: true })
  isPlacement!: boolean;

  @Column({ name: 'loss_streak', type: 'int', default: 0 })
  lossStreak!: number;

  @Column({ name: 'recent_opponent_ids', type: 'uuid', array: true, default: '{}' })
  recentOpponentIds!: string[];

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive!: boolean;

  @Column({ name: 'manner_total', type: 'int', default: 0 })
  mannerTotal!: number;

  @Column({ name: 'manner_count', type: 'int', default: 0 })
  mannerCount!: number;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('User', 'sportsProfiles', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
