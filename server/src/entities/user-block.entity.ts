import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn, Unique } from 'typeorm';
import { User } from './user.entity.js';

@Entity('user_blocks')
@Unique(['blockerId', 'blockedId'])
export class UserBlock {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'blocker_id', type: 'uuid' })
  blockerId!: string;

  @Column({ name: 'blocked_id', type: 'uuid' })
  blockedId!: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'blocker_id' })
  blocker!: User;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'blocked_id' })
  blocked!: User;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;
}
