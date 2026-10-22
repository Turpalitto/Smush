import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "Slime Rush: Evolution",
  description:
    "Мобильная 2D-игра про слизь, которая поглощает мир и эволюционирует. Играбельный веб-прототип на Next.js.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  themeColor: "#022c22",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ru">
      <body className="overscroll-none bg-slate-950 text-slate-100 antialiased">{children}</body>
    </html>
  );
}
