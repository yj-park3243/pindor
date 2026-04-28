import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';

export type NoshowReportStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'INSUFFICIENT';

@Entity('noshow_reports')
export class NoshowReport {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_id', type: 'uuid' })
  matchId!: string;

  @Column({ name: 'reporter_id', type: 'uuid' })
  reporterId!: string;

  @Column({ name: 'reported_user_id', type: 'uuid' })
  reportedUserId!: string;

  @Column({ name: 'reported_profile_id', type: 'uuid' })
  reportedProfileId!: string;

  @Column({ type: 'varchar', length: 20, default: 'PENDING' })
  status!: NoshowReportStatus;

  @Column({ name: 'evidence_urls', type: 'text', array: true, default: '{}' })
  evidenceUrls!: string[];

  @Column({ name: 'reporter_message', type: 'text', nullable: true })
  reporterMessage!: string | null;

  @Column({ name: 'admin_id', type: 'uuid', nullable: true })
  adminId!: string | null;

  @Column({ name: 'admin_decision_at', type: 'timestamptz', nullable: true })
  adminDecisionAt!: Date | null;

  @Column({ name: 'admin_memo', type: 'text', nullable: true })
  adminMemo!: string | null;

  @Column({ name: 'applied_score_change', type: 'int', nullable: true })
  appliedScoreChange!: number | null;

  @Column({ name: 'applied_ban_hours', type: 'int', nullable: true })
  appliedBanHours!: number | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations (lazy/string reference to avoid circular deps)
  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'reporter_id' })
  reporter!: any;

  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'reported_user_id' })
  reportedUser!: any;

  @ManyToOne('Match', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'match_id' })
  match!: any;
}
