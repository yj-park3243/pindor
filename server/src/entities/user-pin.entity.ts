import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import type { User } from './user.entity.js';
import type { Pin } from './pin.entity.js';

@Entity('user_pins')
@Unique(['userId', 'pinId'])
export class UserPin {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'is_primary', type: 'boolean', default: false })
  isPrimary!: boolean;

  @Column({ name: 'joined_at', type: 'timestamptz' })
  joinedAt!: Date;

  // Relations
  @ManyToOne('User', 'userPins')
  @JoinColumn({ name: 'user_id' })
  user!: User;

  @ManyToOne('Pin')
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;
}
