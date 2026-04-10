import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { SportType, RequestType, TimeSlot, MatchRequestStatus } from './enums.js';
import type { User } from './user.entity.js';
import type { SportsProfile } from './sports-profile.entity.js';
import type { Pin } from './pin.entity.js';

@Index(['requesterId', 'status', 'expiresAt'])
@Entity('match_requests')
export class MatchRequest {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'requester_id', type: 'uuid' })
  requesterId!: string;

  @Column({ name: 'sports_profile_id', type: 'uuid' })
  sportsProfileId!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ name: 'request_type', type: 'enum', enum: RequestType, enumName: 'RequestType', default: RequestType.SCHEDULED })
  requestType!: RequestType;

  @Column({ name: 'desired_date', type: 'date', nullable: true })
  desiredDate!: Date | null;

  @Column({ name: 'desired_time_slot', type: 'enum', enum: TimeSlot, enumName: 'TimeSlot', nullable: true })
  desiredTimeSlot!: TimeSlot | null;

  @Column({
    name: 'location_point',
    type: 'geography',
    spatialFeatureType: 'Point',
    srid: 4326,
    nullable: true,
  })
  locationPoint!: object | null;

  @Column({ name: 'location_name', type: 'varchar', length: 255, nullable: true })
  locationName!: string | null;

  @Column({ name: 'min_opponent_score', type: 'int', default: 800 })
  minOpponentScore!: number;

  @Column({ name: 'max_opponent_score', type: 'int', default: 1200 })
  maxOpponentScore!: number;

  @Column({ name: 'gender_preference', type: 'varchar', length: 10, default: 'ANY' })
  genderPreference!: string;

  @Column({ name: 'min_age', type: 'int', nullable: true })
  minAge!: number | null;

  @Column({ name: 'max_age', type: 'int', nullable: true })
  maxAge!: number | null;

  @Column({ type: 'text', nullable: true })
  message!: string | null;

  @Column({ type: 'enum', enum: MatchRequestStatus, enumName: 'MatchRequestStatus', default: MatchRequestStatus.WAITING })
  status!: MatchRequestStatus;

  @Column({ name: 'is_casual', type: 'boolean', default: false })
  isCasual!: boolean;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('User', 'matchRequests')
  @JoinColumn({ name: 'requester_id' })
  requester!: User;

  @ManyToOne('SportsProfile')
  @JoinColumn({ name: 'sports_profile_id' })
  sportsProfile!: SportsProfile;

  @ManyToOne('Pin')
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;
}
