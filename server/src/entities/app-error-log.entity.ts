import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';

@Entity('app_error_logs')
export class AppErrorLog {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid', nullable: true })
  userId!: string | null;

  @Column({ name: 'error_message', type: 'text' })
  errorMessage!: string;

  @Column({ name: 'stack_trace', type: 'text', nullable: true })
  stackTrace!: string | null;

  @Column({ name: 'device_info', type: 'jsonb', nullable: true })
  deviceInfo!: Record<string, unknown> | null;

  @Column({ name: 'screen_name', type: 'varchar', length: 100, nullable: true })
  screenName!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @ManyToOne('User', { nullable: true })
  @JoinColumn({ name: 'user_id' })
  user!: any;
}
