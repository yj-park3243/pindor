import {
  Entity,
  PrimaryColumn,
  Column,
  UpdateDateColumn,
  OneToOne,
  JoinColumn,
} from 'typeorm';
import type { User } from './user.entity.js';

@Entity('notification_settings')
export class NotificationSettings {
  @PrimaryColumn({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'chat_message', type: 'boolean', default: true })
  chatMessage!: boolean;

  @Column({ name: 'match_found', type: 'boolean', default: true })
  matchFound!: boolean;

  @Column({ name: 'match_request', type: 'boolean', default: true })
  matchRequest!: boolean;

  @Column({ name: 'game_result', type: 'boolean', default: true })
  gameResult!: boolean;

  @Column({ name: 'score_change', type: 'boolean', default: true })
  scoreChange!: boolean;

  @Column({ name: 'community_reply', type: 'boolean', default: true })
  communityReply!: boolean;

  @Column({ name: 'do_not_disturb_start', type: 'time', nullable: true })
  doNotDisturbStart!: string | null;

  @Column({ name: 'do_not_disturb_end', type: 'time', nullable: true })
  doNotDisturbEnd!: string | null;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @OneToOne('User', 'notificationSettings', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
