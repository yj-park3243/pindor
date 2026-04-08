import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import type { TeamChatRoom } from './team-chat-room.entity.js';
import type { Team } from './team.entity.js';
import type { User } from './user.entity.js';

@Entity('team_chat_room_members')
@Unique(['teamChatRoomId', 'userId'])
export class TeamChatRoomMember {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_chat_room_id', type: 'uuid' })
  teamChatRoomId!: string;

  @Column({ name: 'team_id', type: 'uuid' })
  teamId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'joined_at', type: 'timestamptz' })
  joinedAt!: Date;

  // Relations
  @ManyToOne('TeamChatRoom')
  @JoinColumn({ name: 'team_chat_room_id' })
  teamChatRoom!: TeamChatRoom;

  @ManyToOne('Team')
  @JoinColumn({ name: 'team_id' })
  team!: Team;

  @ManyToOne('User')
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
