export interface BossPhaseDef {
  index: number;
  nameRu: string;
  nameEn: string;
  hpThreshold: number; // phase active while hp fraction >= this value
  moveSpeed: number;
  slamCooldown: number;
  telegraphSec: number;
  slamDamage: number;
  slamRadius: number;
  summonsAdds: boolean;
  addsCooldown?: number;
}

export const BOSS_DEF = {
  id: "ancient_guardian",
  nameRu: "Древний страж леса",
  nameEn: "Ancient forest guardian",
  baseMass: 900,
  maxHp: 420,
  radius: 95,
  contactDamage: 22,
  rewardCurrency: 120,
  phases: [
    {
      index: 0,
      nameRu: "Преследование",
      nameEn: "Pursuit",
      hpThreshold: 0.66,
      moveSpeed: 70,
      slamCooldown: 4.5,
      telegraphSec: 1.1,
      slamDamage: 22,
      slamRadius: 140,
      summonsAdds: false,
    },
    {
      index: 1,
      nameRu: "Призыв существ",
      nameEn: "Summoning",
      hpThreshold: 0.33,
      moveSpeed: 85,
      slamCooldown: 3.6,
      telegraphSec: 0.95,
      slamDamage: 26,
      slamRadius: 150,
      summonsAdds: true,
      addsCooldown: 7,
    },
    {
      index: 2,
      nameRu: "Ярость стража",
      nameEn: "Guardian's rage",
      hpThreshold: 0,
      moveSpeed: 110,
      slamCooldown: 2.6,
      telegraphSec: 0.7,
      slamDamage: 32,
      slamRadius: 165,
      summonsAdds: true,
      addsCooldown: 5,
    },
  ] as BossPhaseDef[],
};

export function bossPhaseForHp(hpFraction: number): BossPhaseDef {
  for (const phase of BOSS_DEF.phases) {
    if (hpFraction >= phase.hpThreshold) return phase;
  }
  return BOSS_DEF.phases[BOSS_DEF.phases.length - 1];
}
