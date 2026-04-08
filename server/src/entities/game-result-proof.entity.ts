import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { ImageType } from './enums.js';
import type { Game } from './game.entity.js';

@Entity('game_result_proofs')
export class GameResultProof {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'game_id', type: 'uuid' })
  gameId!: string;

  @Column({ name: 'uploaded_by', type: 'uuid' })
  uploadedBy!: string;

  @Column({ name: 'image_url', type: 'text' })
  imageUrl!: string;

  @Column({ name: 'image_type', type: 'enum', enum: ImageType, enumName: 'ImageType', nullable: true })
  imageType!: ImageType | null;

  @Column({ name: 'ocr_data', type: 'jsonb', nullable: true })
  ocrData!: Record<string, unknown> | null;

  @Column({ name: 'is_approved', type: 'boolean', nullable: true })
  isApproved!: boolean | null;

  @Column({ name: 'reviewed_by', type: 'uuid', nullable: true })
  reviewedBy!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('Game')
  @JoinColumn({ name: 'game_id' })
  game!: Game;
}
