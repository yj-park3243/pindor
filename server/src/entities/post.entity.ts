import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  OneToMany,
  JoinColumn,
  Index,
} from 'typeorm';
import { PostCategory } from './enums.js';
import type { User } from './user.entity.js';
import type { Pin } from './pin.entity.js';
import type { PostImage } from './post-image.entity.js';
import type { PostLike } from './post-like.entity.js';
import type { Comment } from './comment.entity.js';

@Index(['pinId', 'isDeleted', 'createdAt'])
@Entity('posts')
export class Post {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'pin_id', type: 'uuid' })
  pinId!: string;

  @Column({ name: 'author_id', type: 'uuid' })
  authorId!: string;

  @Column({ type: 'varchar', length: 100 })
  title!: string;

  @Column({ type: 'text' })
  content!: string;

  @Column({ type: 'enum', enum: PostCategory, enumName: 'PostCategory', default: PostCategory.GENERAL })
  category!: PostCategory;

  @Column({ name: 'view_count', type: 'int', default: 0 })
  viewCount!: number;

  @Column({ name: 'like_count', type: 'int', default: 0 })
  likeCount!: number;

  @Column({ name: 'comment_count', type: 'int', default: 0 })
  commentCount!: number;

  @Column({ name: 'is_deleted', type: 'boolean', default: false })
  isDeleted!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;

  // Relations
  @ManyToOne('Pin')
  @JoinColumn({ name: 'pin_id' })
  pin!: Pin;

  @ManyToOne('User', 'posts')
  @JoinColumn({ name: 'author_id' })
  author!: User;

  @OneToMany('PostImage', 'post')
  images!: PostImage[];

  @OneToMany('PostLike', 'post')
  likes!: PostLike[];

  @OneToMany('Comment', 'post')
  comments!: Comment[];
}
