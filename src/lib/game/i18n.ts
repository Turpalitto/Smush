export type Lang = "ru" | "en";

const dict = {
  ru: {
    appTitle: "SLIME RUSH: EVOLUTION",
    play: "Играть",
    upgrades: "Улучшения",
    collection: "Коллекция",
    shop: "Магазин",
    settings: "Настройки",
    privacy: "Конфиденциальность",
    classicMode: "Классический забег",
    practiceMode: "Тренировка",
    back: "Назад",
    pause: "Пауза",
    resume: "Продолжить",
    exitToMenu: "В меню",
    restart: "Начать заново",
    victory: "Победа!",
    defeat: "Поражение",
    mass: "Масса",
    time: "Время",
    currencyEarned: "Получено эссенции",
    watchAdDouble: "Удвоить награду (реклама)",
    watchAdRevive: "Продолжить за рекламу",
    skip: "Пропустить",
  },
  en: {
    appTitle: "SLIME RUSH: EVOLUTION",
    play: "Play",
    upgrades: "Upgrades",
    collection: "Collection",
    shop: "Shop",
    settings: "Settings",
    privacy: "Privacy",
    classicMode: "Classic run",
    practiceMode: "Practice",
    back: "Back",
    pause: "Pause",
    resume: "Resume",
    exitToMenu: "Main menu",
    restart: "Restart",
    victory: "Victory!",
    defeat: "Defeat",
    mass: "Mass",
    time: "Time",
    currencyEarned: "Essence earned",
    watchAdDouble: "Double reward (ad)",
    watchAdRevive: "Continue (watch ad)",
    skip: "Skip",
  },
} as const;

export type DictKey = keyof (typeof dict)["ru"];

export function t(key: DictKey, lang: Lang): string {
  return dict[lang][key] ?? dict.ru[key];
}
