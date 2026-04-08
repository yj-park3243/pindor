import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

@Entity('app_versions')
export class AppVersion {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 10 })
  platform!: string; // IOS, ANDROID

  @Column({ name: 'min_version', type: 'varchar', length: 20 })
  minVersion!: string; // 최소 필수 버전 (예: 1.0.0)

  @Column({ name: 'latest_version', type: 'varchar', length: 20 })
  latestVersion!: string; // 최신 버전

  @Column({ name: 'latest_build', type: 'int', default: 1 })
  latestBuild!: number;

  @Column({ name: 'force_update', type: 'boolean', default: false })
  forceUpdate!: boolean; // 강제 업데이트 여부

  @Column({ name: 'update_message', type: 'text', nullable: true })
  updateMessage!: string | null;

  @Column({ name: 'store_url', type: 'text', nullable: true })
  storeUrl!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
