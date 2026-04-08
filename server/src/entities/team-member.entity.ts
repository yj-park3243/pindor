import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import { TeamRole, TeamMemberStatus } from './enums.js';
import type { Team } from './team.entity.js';
import type { User } from './user.entity.js';

@Entity('team_members')
@Unique(['teamId', 'userId'])
export class TeamMember {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_id', type: 'uuid' })
  teamId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ type: 'enum', enum: TeamRole, enumName: 'TeamRole', default: TeamRole.MEMBER })
  role!: TeamRole;

  @Column({ type: 'enum', enum: TeamRole, enumName: 'TeamRole', nullable: true })
  position!: string | null;

  @Column({ name: 'joined_at', type: 'timestamptz' })
  joinedAt!: Date;

  @Column({ type: 'enum', enum: TeamMemberStatus, enumName: 'TeamMemberStatus', default: TeamMemberStatus.ACTIVE })
  status!: TeamMemberStatus;

  // Relations
  @ManyToOne('Team')
  @JoinColumn({ name: 'team_id' })
  team!: Team;

  @ManyToOne('User', 'teamMembers')
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
