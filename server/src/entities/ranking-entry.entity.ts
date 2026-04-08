import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import { SportType, Tier } from './enums.js';
import type { Pin } from './pin.entity.js';
import type { SportsProfile } from './sports-profile.entity.js';

@Entity('ranking_entries')
@Unique(['pinId', 'sportsProfileId', 'sportType'])
export class RankingEntry {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'sports_profile_id', type: 'uuid' })
  sportsProfileId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ type: 'int' })
  rank!: number;

  @Column({ type: 'int' })
  score!: number;

  @Column({ type: 'enum', enum: Tier, enumName: 'Tier' })
  tier!: Tier;

  @Column({ name: 'games_played', type: 'int', default: 0 })
  gamesPlayed!: number;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('Pin')
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;

  @ManyToOne('SportsProfile')
  @JoinColumn({ name: 'sports_profile_id' })
  sportsProfile!: SportsProfile;
}
