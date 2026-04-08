import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { MessageType } from './enums.js';
import type { TeamChatRoom } from './team-chat-room.entity.js';
import type { User } from './user.entity.js';

@Entity('team_chat_messages')
export class TeamChatMessage {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_chat_room_id', type: 'uuid' })
  teamChatRoomId!: string;

  @Column({ name: 'sender_id', type: 'uuid' })
  senderId!: string;

  @Column({ name: 'message_type', type: 'enum', enum: MessageType, enumName: 'MessageType', default: MessageType.TEXT })
  messageType!: MessageType;

  @Column({ type: 'text', nullable: true })
  content!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('TeamChatRoom')
  @JoinColumn({ name: 'team_chat_room_id' })
  teamChatRoom!: TeamChatRoom;

  @ManyToOne('User')
  @JoinColumn({ name: 'sender_id' })
  sender!: User;
}
