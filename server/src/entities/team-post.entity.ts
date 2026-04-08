import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { TeamPostCategory } from './enums.js';
import type { Team } from './team.entity.js';
import type { User } from './user.entity.js';

@Entity('team_posts')
export class TeamPost {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_id', type: 'uuid' })
  teamId!: string;

  @Column({ name: 'author_id', type: 'uuid' })
  authorId!: string;

  @Column({ type: 'varchar', length: 100 })
  title!: string;

  @Column({ type: 'text' })
  content!: string;

  @Column({ type: 'enum', enum: TeamPostCategory, enumName: 'TeamPostCategory', default: TeamPostCategory.FREE })
  category!: TeamPostCategory;

  @Column({ name: 'is_pinned', type: 'boolean', default: false })
  isPinned!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('Team')
  @JoinColumn({ name: 'team_id' })
  team!: Team;

  @ManyToOne('User')
  @JoinColumn({ name: 'author_id' })
  author!: User;
}
