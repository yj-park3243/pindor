import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  OneToMany,
} from 'typeorm';
import { RoomType, RoomStatus } from './enums.js';
import type { Message } from './message.entity.js';

@Entity('chat_rooms')
export class ChatRoom {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_id', type: 'uuid', nullable: true, unique: true })
  matchId!: string | null;

  @Column({ name: 'room_type', type: 'enum', enum: RoomType, enumName: 'RoomType', default: RoomType.MATCH })
  roomType!: RoomType;

  @Column({ type: 'enum', enum: RoomStatus, enumName: 'RoomStatus', default: RoomStatus.ACTIVE })
  status!: RoomStatus;

  @Column({ name: 'last_message_at', type: 'timestamptz', nullable: true })
  lastMessageAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @OneToMany('Message', 'chatRoom')
  messages!: Message[];
}
