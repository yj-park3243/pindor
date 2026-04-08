import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import type { TeamPost } from './team-post.entity.js';
import type { User } from './user.entity.js';

@Entity('team_post_comments')
export class TeamPostComment {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'team_post_id', type: 'uuid' })
  teamPostId!: string;

  @Column({ name: 'author_id', type: 'uuid' })
  authorId!: string;

  @Column({ name: 'parent_id', type: 'uuid', nullable: true })
  parentId!: string | null;

  @Column({ type: 'text' })
  content!: string;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Relations
  @ManyToOne('TeamPost')
  @JoinColumn({ name: 'team_post_id' })
  teamPost!: TeamPost;

  @ManyToOne('User')
  @JoinColumn({ name: 'author_id' })
  author!: User;
}
