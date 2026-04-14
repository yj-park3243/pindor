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
import { SportType, MatchStatus, TimeSlot } from './enums.js';
import type { SportsProfile } from './sports-profile.entity.js';
import type { Pin } from './pin.entity.js';

@Index(['status', 'createdAt'])
@Index(['requesterProfileId', 'status'])
@Index(['opponentProfileId', 'status'])
@Entity('matches')
export class Match {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_request_id', type: 'uuid', nullable: true, unique: true })
  matchRequestId!: string | null;

  @Column({ name: 'requester_profile_id', type: 'uuid' })
  requesterProfileId!: string;

  @Column({ name: 'opponent_profile_id', type: 'uuid' })
  opponentProfileId!: string;

  @Column({ name: 'pin_id', type: 'uuid', nullable: true })
  pinId!: string | null;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ name: 'desired_date', type: 'date', nullable: true })
  desiredDate!: Date | null;

  @Column({ name: 'desired_time_slot', type: 'enum', enum: TimeSlot, enumName: 'TimeSlot', nullable: true })
  desiredTimeSlot!: TimeSlot | null;

  @Column({ name: 'scheduled_date', type: 'date', nullable: true })
  scheduledDate!: Date | null;

  @Column({ name: 'scheduled_time', type: 'time', nullable: true })
  scheduledTime!: string | null;

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

  @Column({ type: 'enum', enum: MatchStatus, enumName: 'MatchStatus', default: MatchStatus.CHAT })
  status!: MatchStatus;

  @Column({ name: 'chat_room_id', type: 'uuid', nullable: true, unique: true })
  chatRoomId!: string | null;

  @Column({ name: 'confirmed_at', type: 'timestamptz', nullable: true })
  confirmedAt!: Date | null;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt!: Date | null;

  @Column({ name: 'requester_verification_code', type: 'varchar', length: 4, nullable: true })
  requesterVerificationCode!: string | null;

  @Column({ name: 'opponent_verification_code', type: 'varchar', length: 4, nullable: true })
  opponentVerificationCode!: string | null;

  @Column({ name: 'cancelled_by', type: 'uuid', nullable: true })
  cancelledBy!: string | null;

  @Column({ name: 'cancel_reason', type: 'text', nullable: true })
  cancelReason!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('SportsProfile')
  @JoinColumn({ name: 'requester_profile_id' })
  requesterProfile!: SportsProfile;

  @ManyToOne('SportsProfile')
  @JoinColumn({ name: 'opponent_profile_id' })
  opponentProfile!: SportsProfile;

  @ManyToOne('Pin', { nullable: true })
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin | null;
}
