import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { SportType, TeamStatus } from './enums.js';

@Entity('teams')
export class Team {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 50 })
  name!: string;

  @Column({ type: 'varchar', length: 50, unique: true })
  slug!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

  @Column({ name: 'logo_url', type: 'text', nullable: true })
  logoUrl!: string | null;

  @Column({ type: 'text', nullable: true })
  description!: string | null;

  @Column({ name: 'home_pin_id', type: 'uuid', nullable: true })
  homePinId!: string | null;

  @Column({
    name: 'home_point',
    type: 'geography',
    spatialFeatureType: 'Point',
    srid: 4326,
    nullable: true,
  })
  homePoint!: object | null;

  @Column({ name: 'activity_region', type: 'varchar', length: 100, nullable: true })
  activityRegion!: string | null;

  @Column({ name: 'min_members', type: 'int', default: 3 })
  minMembers!: number;

  @Column({ name: 'max_members', type: 'int', default: 11 })
  maxMembers!: number;

  @Column({ name: 'current_members', type: 'int', default: 0 })
  currentMembers!: number;

  @Column({ type: 'int', default: 0 })
  wins!: number;

  @Column({ type: 'int', default: 0 })
  losses!: number;

  @Column({ type: 'int', default: 0 })
  draws!: number;

  @Column({ name: 'team_score', type: 'int', default: 1000 })
  teamScore!: number;

  @Column({ name: 'is_recruiting', type: 'boolean', default: true })
  isRecruiting!: boolean;

  @Column({ type: 'enum', enum: TeamStatus, enumName: 'TeamStatus', default: TeamStatus.ACTIVE })
  status!: TeamStatus;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
