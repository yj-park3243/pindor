import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';

export type MannerRatingSource = 'USER' | 'NOSHOW_AUTO';

@Entity('manner_ratings')
// USER 평가와 NOSHOW_AUTO(노쇼 자동 1점)를 같은 매칭에 둘 다 저장 가능하도록 source까지 키에 포함
@Unique(['matchId', 'raterId', 'ratedUserId', 'source'])
export class MannerRating {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'match_id', type: 'uuid' })
  matchId!: string;

  @Column({ name: 'rater_id', type: 'uuid' })
  raterId!: string;

  @Column({ name: 'rated_user_id', type: 'uuid' })
  ratedUserId!: string;

  @Column({ name: 'rated_profile_id', type: 'uuid' })
  ratedProfileId!: string;

  @Column({ type: 'int' })
  score!: number;

  @Column({ type: 'varchar', length: 20, default: 'USER' })
  source!: MannerRatingSource;

  @Column({ name: 'noshow_report_id', type: 'uuid', nullable: true })
  noshowReportId!: string | null;

  @Column({ name: 'voided_at', type: 'timestamptz', nullable: true })
  voidedAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'rater_id' })
  rater!: any;

  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'rated_user_id' })
  ratedUser!: any;

  @ManyToOne('SportsProfile', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'rated_profile_id' })
  ratedProfile!: any;

  @ManyToOne('Match', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'match_id' })
  match!: any;

  @ManyToOne('NoshowReport', { onDelete: 'SET NULL', nullable: true })
  @JoinColumn({ name: 'noshow_report_id' })
  noshowReport!: any;
}
