import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';
import { ScoreChangeType } from './enums.js';

@Entity('score_histories')
export class ScoreHistory {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'sports_profile_id', type: 'uuid' })
  sportsProfileId!: string;

  @Column({ name: 'game_id', type: 'uuid', nullable: true })
  gameId!: string | null;

  @Column({ name: 'change_type', type: 'enum', enum: ScoreChangeType, enumName: 'ScoreChangeType' })
  changeType!: ScoreChangeType;

  @Column({ name: 'score_before', type: 'int' })
  scoreBefore!: number;

  @Column({ name: 'score_change', type: 'int' })
  scoreChange!: number;

  @Column({ name: 'score_after', type: 'int' })
  scoreAfter!: number;

  @Column({ name: 'opponent_score', type: 'int', nullable: true })
  opponentScore!: number | null;

  @Column({ name: 'k_factor', type: 'int', nullable: true })
  kFactor!: number | null;

  // Glicko-2 details
  @Column({ name: 'rd_before', type: 'float', nullable: true })
  rdBefore!: number | null;

  @Column({ name: 'rd_after', type: 'float', nullable: true })
  rdAfter!: number | null;

  @Column({ name: 'volatility_before', type: 'float', nullable: true })
  volatilityBefore!: number | null;

  @Column({ name: 'volatility_after', type: 'float', nullable: true })
  volatilityAfter!: number | null;

  @Column({ name: 'is_placement_game', type: 'boolean', default: false })
  isPlacementGame!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;
}
