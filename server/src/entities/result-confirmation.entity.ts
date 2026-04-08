import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
} from 'typeorm';
import type { Game } from './game.entity.js';
import type { User } from './user.entity.js';

@Entity('result_confirmations')
@Unique(['gameId', 'userId'])
export class ResultConfirmation {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'game_id', type: 'uuid' })
  gameId!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'is_confirmed', type: 'boolean' })
  isConfirmed!: boolean;

  @Column({ type: 'text', nullable: true })
  comment!: string | null;

  @Column({ name: 'confirmed_at', type: 'timestamptz' })
  confirmedAt!: Date;

  // Relations
  @ManyToOne('Game')
  @JoinColumn({ name: 'game_id' })
  game!: Game;

  @ManyToOne('User')
  @JoinColumn({ name: 'user_id' })
  user!: User;
}
