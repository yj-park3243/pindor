import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';
import { RoomType, RoomStatus } from './enums.js';

@Entity('team_chat_rooms')
export class TeamChatRoom {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_match_id', type: 'uuid', nullable: true, unique: true })
  teamMatchId!: string | null;

  @Column({ name: 'team_id', type: 'uuid', nullable: true })
  teamId!: string | null;

  @Column({ name: 'room_type', type: 'enum', enum: RoomType, enumName: 'RoomType', default: RoomType.TEAM_MATCH })
  roomType!: RoomType;

  @Column({ type: 'enum', enum: RoomStatus, enumName: 'RoomStatus', default: RoomStatus.ACTIVE })
  status!: RoomStatus;

  @Column({ name: 'last_message_at', type: 'timestamptz', nullable: true })
  lastMessageAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;
}
