import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import type { User } from './user.entity.js';

// 캠페인 타입 (notification_campaign_logs.campaign_type)
export type CampaignType = 'INACTIVE_2D' | 'NEW_USER_NUDGE' | 'RANK_DROP';

// ─────────────────────────────────────
// 캠페인 알림 발송 이력
// - 쿨다운 계산 + KPI 측정용
// ─────────────────────────────────────
@Index(['userId', 'campaignType', 'sentAt'])
@Entity('notification_campaign_logs')
export class NotificationCampaignLog {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'campaign_type', type: 'varchar', length: 40 })
  campaignType!: CampaignType;

  /**
   * 발송 컨텍스트 예시:
   * - INACTIVE_2D:   { lastActivityAt }
   * - NEW_USER_NUDGE: { sendCount, createdAt }
   * - RANK_DROP:     { sportType, pinId, rankAtSend, rankBefore, rankAfter }
   */
  @Column({ type: 'jsonb', default: {} })
  context!: Record<string, unknown>;

  // 발송 시각 (created_at 용도)
  @CreateDateColumn({ name: 'sent_at', type: 'timestamptz' })
  sentAt!: Date;

  // 효과 측정: 유저가 푸시를 클릭한 시각
  @Column({ name: 'push_clicked_at', type: 'timestamptz', nullable: true })
  pushClickedAt!: Date | null;

  // 효과 측정: 알림 받고 24h 내 매칭 신청 ID
  @Column({ name: 'resulting_match_request_id', type: 'uuid', nullable: true })
  resultingMatchRequestId!: string | null;

  // Relations
  @ManyToOne('User', { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
