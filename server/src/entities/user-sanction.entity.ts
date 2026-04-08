import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('user_sanctions')
export class UserSanction {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ type: 'varchar', length: 20 })
  type!: string; // WARNING, SUSPEND, BAN

  @Column({ type: 'text' })
  reason!: string;

  @Column({ name: 'report_id', type: 'uuid', nullable: true })
  reportId!: string | null;

  @Column({ name: 'issued_by', type: 'uuid', nullable: true })
  issuedBy!: string | null; // null = auto

  @Column({ name: 'expires_at', type: 'timestamptz', nullable: true })
  expiresAt!: Date | null;

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;
}
