import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { SportType, GameResultStatus } from './enums.js';
import type { Match } from './match.entity.js';

@Entity('games')
export class Game {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_id', type: 'uuid', unique: true })
  matchId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ name: 'venue_name', type: 'varchar', length: 255, nullable: true })
  venueName!: string | null;

  @Column({
    name: 'venue_location',
    type: 'geography',
    spatialFeatureType: 'Point',
    srid: 4326,
    nullable: true,
  })
  venueLocation!: object | null;

  @Column({ name: 'played_at', type: 'timestamptz', nullable: true })
  playedAt!: Date | null;

  @Column({ name: 'score_data', type: 'jsonb', default: {} })
  scoreData!: Record<string, unknown>;

  @Column({ name: 'result_status', type: 'enum', enum: GameResultStatus, enumName: 'GameResultStatus', default: GameResultStatus.PENDING })
  resultStatus!: GameResultStatus;

  @Column({ name: 'winner_profile_id', type: 'uuid', nullable: true })
  winnerProfileId!: string | null;

  @Column({ name: 'requester_score', type: 'int', nullable: true })
  requesterScore!: number | null;

  @Column({ name: 'opponent_score', type: 'int', nullable: true })
  opponentScore!: number | null;

  @Column({ name: 'result_input_deadline', type: 'timestamptz', nullable: true })
  resultInputDeadline!: Date | null;

  @Column({ name: 'requester_claimed_result', type: 'varchar', length: 10, nullable: true })
  requesterClaimedResult!: string | null; // WIN, LOSS, DRAW

  @Column({ name: 'opponent_claimed_result', type: 'varchar', length: 10, nullable: true })
  opponentClaimedResult!: string | null; // WIN, LOSS, DRAW

  @Column({ name: 'proof_image_urls', type: 'jsonb', default: '[]' })
  proofImageUrls!: string[];

  @Column({ name: 'verified_at', type: 'timestamptz', nullable: true })
  verifiedAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('Match')
  @JoinColumn({ name: 'match_id' })
  match!: Match;
}
