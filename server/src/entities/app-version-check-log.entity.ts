import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';

@Entity('app_version_check_logs')
@Index(['createdAt'])
@Index(['userId'])
export class AppVersionCheckLog {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid', nullable: true })
  userId!: string | null;

  @Column({ name: 'nickname', type: 'varchar', length: 50, nullable: true })
  nickname!: string | null;

  @Column({ name: 'email', type: 'varchar', length: 255, nullable: true })
  email!: string | null;

  @Column({ name: 'phone_number', type: 'varchar', length: 30, nullable: true })
  phoneNumber!: string | null;

  @Column({ type: 'varchar', length: 10 })
  platform!: string;

  @Column({ name: 'app_version', type: 'varchar', length: 20, nullable: true })
  appVersion!: string | null;

  @Column({ type: 'double precision', nullable: true })
  latitude!: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude!: number | null;

  @Column({ name: 'ip_address', type: 'varchar', length: 64, nullable: true })
  ipAddress!: string | null;

  @Column({ name: 'user_agent', type: 'text', nullable: true })
  userAgent!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @ManyToOne('User', { nullable: true })
  @JoinColumn({ name: 'user_id' })
  user!: any;
}
