import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  OneToMany,
  JoinColumn,
} from 'typeorm';
import { PinLevel } from './enums.js';

@Entity('pins')
export class Pin {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 100 })
  name!: string;

  @Column({ type: 'varchar', length: 100, unique: true })
  slug!: string;

  @Column({
    name: 'center',
    type: 'geography',
    spatialFeatureType: 'Point',
    srid: 4326,
  })
  center!: object;

  @Column({
    name: 'boundary',
    type: 'geography',
    spatialFeatureType: 'Polygon',
    srid: 4326,
    nullable: true,
  })
  boundary!: object | null;

  @Column({ type: 'enum', enum: PinLevel, enumName: 'PinLevel' })
  level!: PinLevel;

  @Column({ name: 'parent_pin_id', type: 'uuid', nullable: true })
  parentPinId!: string | null;

  @Column({ name: 'region_code', type: 'varchar', length: 10, nullable: true })
  regionCode!: string | null;

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive!: boolean;

  @Column({ name: 'user_count', type: 'int', default: 0 })
  userCount!: number;

  @Column({ type: 'jsonb', default: {} })
  metadata!: Record<string, unknown>;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // Self-referencing relations
  @ManyToOne('Pin', 'childPins', { nullable: true })
  @JoinColumn({ name: 'parent_pin_id' })
  parentPin!: Pin | null;

  @OneToMany('Pin', 'parentPin')
  childPins!: Pin[];
}
