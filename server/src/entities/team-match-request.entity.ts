import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { SportType, TimeSlot, MatchRequestStatus } from './enums.js';
import type { Team } from './team.entity.js';
import type { User } from './user.entity.js';

@Entity('team_match_requests')
export class TeamMatchRequest {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'requester_team_id', type: 'uuid' })
  requesterTeamId!: string;

  @Column({ name: 'requested_by', type: 'uuid' })
  requestedBy!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

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

  @Column({ name: 'radius_km', type: 'float', default: 20 })
  radiusKm!: number;

  @Column({ type: 'text', nullable: true })
  message!: string | null;

  @Column({ type: 'enum', enum: MatchRequestStatus, enumName: 'MatchRequestStatus', default: MatchRequestStatus.WAITING })
  status!: MatchRequestStatus;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('Team')
  @JoinColumn({ name: 'requester_team_id' })
  requesterTeam!: Team;

  @ManyToOne('User')
  @JoinColumn({ name: 'requested_by' })
  requestedByUser!: User;
}
