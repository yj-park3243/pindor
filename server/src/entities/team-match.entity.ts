import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { SportType, MatchStatus, GameResultStatus } from './enums.js';
import type { Team } from './team.entity.js';

@Entity('team_matches')
export class TeamMatch {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_match_request_id', type: 'uuid', nullable: true, unique: true })
  teamMatchRequestId!: string | null;

  @Column({ name: 'home_team_id', type: 'uuid' })
  homeTeamId!: string;

  @Column({ name: 'away_team_id', type: 'uuid' })
  awayTeamId!: string;

  @Column({ name: 'sport_type', type: 'enum', enum: SportType, enumName: 'SportType' })
  sportType!: SportType;

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

  @Column({ name: 'home_score', type: 'int', nullable: true })
  homeScore!: number | null;

  @Column({ name: 'away_score', type: 'int', nullable: true })
  awayScore!: number | null;

  @Column({ name: 'winner_team_id', type: 'uuid', nullable: true })
  winnerTeamId!: string | null;

  @Column({ name: 'result_status', type: 'enum', enum: GameResultStatus, enumName: 'GameResultStatus', default: GameResultStatus.PENDING })
  resultStatus!: GameResultStatus;

  @Column({ name: 'confirmed_at', type: 'timestamptz', nullable: true })
  confirmedAt!: Date | null;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('Team')
  @JoinColumn({ name: 'home_team_id' })
  homeTeam!: Team;

  @ManyToOne('Team')
  @JoinColumn({ name: 'away_team_id' })
  awayTeam!: Team;
}
