import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import type { Match } from './match.entity.js';
import type { User } from './user.entity.js';

@Entity('match_acceptances')
@Unique(['matchId', 'userId'])
export class MatchAcceptance {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_id', type: 'uuid' })
  matchId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ type: 'boolean', nullable: true })
  accepted!: boolean | null;

  @Column({ name: 'responded_at', type: 'timestamptz', nullable: true })
  respondedAt!: Date | null;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('Match')
  @JoinColumn({ name: 'match_id' })
  match!: Match;

  @ManyToOne('User', 'matchAcceptances')
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
