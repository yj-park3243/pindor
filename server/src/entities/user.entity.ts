import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToMany,
  OneToOne,
} from 'typeorm';
import { UserStatus } from './enums.js';
import type { SocialAccount } from './social-account.entity.js';
import type { UserLocation } from './user-location.entity.js';
import type { SportsProfile } from './sports-profile.entity.js';
import type { MatchRequest } from './match-request.entity.js';
import type { Message } from './message.entity.js';
import type { Post } from './post.entity.js';
import type { Comment } from './comment.entity.js';
import type { Notification } from './notification.entity.js';
import type { DeviceToken } from './device-token.entity.js';
import type { NotificationSettings } from './notification-settings.entity.js';
import type { Report } from './report.entity.js';
import type { UserPin } from './user-pin.entity.js';
import type { AdminProfile } from './admin-profile.entity.js';
import type { TeamMember } from './team-member.entity.js';
import type { MatchAcceptance } from './match-acceptance.entity.js';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 255, nullable: true, unique: true })
  email!: string | null;

  @Column({ type: 'varchar', length: 20, unique: true })
  nickname!: string;

  @Column({ name: 'profile_image_url', type: 'text', nullable: true })
  profileImageUrl!: string | null;

  @Column({ type: 'varchar', length: 20, nullable: true })
  phone!: string | null;

  @Column({ type: 'varchar', length: 10, nullable: true })
  gender!: string | null;

  @Column({ name: 'birth_date', type: 'date', nullable: true })
  birthDate!: Date | null;

  @Column({ name: 'rejection_count', type: 'int', default: 0 })
  rejectionCount!: number;

  @Column({ name: 'rejection_cooldown_until', type: 'timestamptz', nullable: true })
  rejectionCooldownUntil!: Date | null;

  @Column({ type: 'enum', enum: UserStatus, enumName: 'UserStatus', default: UserStatus.ACTIVE })
  status!: UserStatus;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  @Column({ name: 'last_login_at', type: 'timestamptz', nullable: true })
  lastLoginAt!: Date | null;

  @Column({ name: 'preferred_sport_type', type: 'varchar', length: 50, nullable: true, default: null })
  preferredSportType!: string | null;

  // KCP 본인인증 컬럼
  @Column({ name: 'phone_number', type: 'varchar', length: 30, nullable: true })
  phoneNumber!: string | null;

  @Column({ name: 'ci', type: 'varchar', length: 100, nullable: true })
  ci!: string | null;

  @Column({ name: 'di', type: 'varchar', length: 100, nullable: true })
  di!: string | null;

  @Column({ name: 'real_name', type: 'varchar', length: 50, nullable: true })
  realName!: string | null;

  @Column({ name: 'carrier', type: 'varchar', length: 20, nullable: true })
  carrier!: string | null;

  @Column({ name: 'is_verified', type: 'boolean', default: false })
  isVerified!: boolean;

  @Column({ name: 'verified_at', type: 'timestamptz', nullable: true })
  verifiedAt!: Date | null;

  // Relations
  @OneToMany('SocialAccount', 'user')
  socialAccounts!: SocialAccount[];

  @OneToOne('UserLocation', 'user')
  location!: UserLocation;

  @OneToMany('SportsProfile', 'user')
  sportsProfiles!: SportsProfile[];

  @OneToMany('MatchRequest', 'requester')
  matchRequests!: MatchRequest[];

  @OneToMany('Message', 'sender')
  sentMessages!: Message[];

  @OneToMany('Post', 'author')
  posts!: Post[];

  @OneToMany('Comment', 'author')
  comments!: Comment[];

  @OneToMany('Notification', 'user')
  notifications!: Notification[];

  @OneToMany('DeviceToken', 'user')
  deviceTokens!: DeviceToken[];

  @OneToOne('NotificationSettings', 'user')
  notificationSettings!: NotificationSettings;

  @OneToMany('Report', 'reporter')
  reports!: Report[];

  @OneToMany('UserPin', 'user')
  userPins!: UserPin[];

  @OneToOne('AdminProfile', 'user')
  adminProfile!: AdminProfile;

  @OneToMany('TeamMember', 'user')
  teamMembers!: TeamMember[];

  @OneToMany('MatchAcceptance', 'user')
  matchAcceptances!: MatchAcceptance[];
}
