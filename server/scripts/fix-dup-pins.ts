import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  // 서울 25구 중복 — 자식 핀이 있는 쪽을 남기고, 없는 쪽의 자식을 이전 후 삭제
  const allPins: any[] = await prisma.$queryRaw`
    SELECT id, name, slug, level, created_at,
           (SELECT count(*) FROM pins AS c WHERE c.parent_pin_id = p.id) as child_count
    FROM pins p
    WHERE level = 'GU'
    ORDER BY name, created_at ASC
  `;

  const groups: Record<string, any[]> = {};
  for (const p of allPins) {
    if (!groups[p.name]) groups[p.name] = [];
    groups[p.name].push(p);
  }

  let fixed = 0;
  for (const [name, pins] of Object.entries(groups)) {
    if (pins.length <= 1) continue;

    // 자식이 가장 많은 핀을 keep
    pins.sort((a: any, b: any) => Number(b.child_count) - Number(a.child_count));
    const keep = pins[0];

    for (let i = 1; i < pins.length; i++) {
      const dup = pins[i];
      // 자식 핀을 keep으로 이전
      if (Number(dup.child_count) > 0) {
        await prisma.$executeRaw`
          UPDATE pins SET parent_pin_id = ${keep.id}::uuid
          WHERE parent_pin_id = ${dup.id}::uuid
        `;
        console.log(`${name}: 자식 ${dup.child_count}개를 ${keep.slug}으로 이전`);
      }
      // 중복 삭제
      try {
        await prisma.pin.delete({ where: { id: dup.id } });
        fixed++;
      } catch (e: any) {
        console.log(`${name} 삭제 실패:`, e.message?.substring(0, 80));
      }
    }
  }

  console.log(`\n추가 삭제: ${fixed}개`);
  const finalCount = await prisma.pin.count();
  console.log(`최종 핀 수: ${finalCount}`);

  const byLevel = await prisma.pin.groupBy({ by: ['level'], _count: { id: true } });
  console.log('레벨별:', JSON.stringify(byLevel));

  await prisma.$disconnect();
}

main();
