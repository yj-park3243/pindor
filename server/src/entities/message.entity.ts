import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { MessageType } from './enums.js';
import type { ChatRoom } from './chat-room.entity.js';
import type { User } from './user.entity.js';

@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'chat_room_id', type: 'uuid' })
  chatRoomId!: string;

  @Column({ name: 'sender_id', type: 'uuid' })
  senderId!: string;

  @Column({ name: 'message_type', type: 'enum', enum: MessageType, enumName: 'MessageType', default: MessageType.TEXT })
  messageType!: MessageType;

  @Column({ type: 'text', nullable: true })
  content!: string | null;

  @Column({ name: 'image_url', type: 'text', nullable: true })
  imageUrl!: string | null;

  @Column({ name: 'extra_data', type: 'jsonb', default: {} })
  extraData!: Record<string, unknown>;

  @Column({ name: 'is_deleted', type: 'boolean', default: false })
  isDeleted!: boolean;

  @Column({ name: 'read_at', type: 'timestamptz', nullable: true, default: null })
  readAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('ChatRoom', 'messages')
  @JoinColumn({ name: 'chat_room_id' })
  chatRoom!: ChatRoom;

  @ManyToOne('User', 'sentMessages')
  @JoinColumn({ name: 'sender_id' })
  sender!: User;
}
