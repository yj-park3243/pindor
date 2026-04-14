import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import type { User } from './user.entity.js';
import type { Pin } from './pin.entity.js';

@Entity('pin_activities')
@Unique(['pinId', 'userId'])
export class PinActivity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('Pin')
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;

  @ManyToOne('User')
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
