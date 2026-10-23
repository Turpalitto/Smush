"use client";

import { useRef, useState, useCallback } from "react";

interface JoystickProps {
  mode: "fixed" | "floating";
  onChange: (x: number, y: number) => void;
  onDashTap?: () => void;
}

const MAX_RADIUS = 52;

export function Joystick({ mode, onChange, onDashTap }: JoystickProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [origin, setOrigin] = useState<{ x: number; y: number } | null>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const activePointer = useRef<number | null>(null);
  const lastTap = useRef(0);

  const updateFromPoint = useCallback(
    (clientX: number, clientY: number, base: { x: number; y: number }) => {
      let dx = clientX - base.x;
      let dy = clientY - base.y;
      const dist = Math.hypot(dx, dy);
      if (dist > MAX_RADIUS) {
        dx = (dx / dist) * MAX_RADIUS;
        dy = (dy / dist) * MAX_RADIUS;
      }
      setKnob({ x: dx, y: dy });
      onChange(dx / MAX_RADIUS, dy / MAX_RADIUS);
    },
    [onChange],
  );

  const handlePointerDown = (e: React.PointerEvent) => {
    e.preventDefault();
    const now = Date.now();
    if (now - lastTap.current < 280) {
      onDashTap?.();
    }
    lastTap.current = now;

    activePointer.current = e.pointerId;
    const rect = containerRef.current?.getBoundingClientRect();
    let base = { x: e.clientX, y: e.clientY };
    if (mode === "fixed" && rect) {
      base = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
    } else {
      setOrigin({ x: e.clientX, y: e.clientY });
    }
    if (mode === "fixed") setOrigin(base);
    updateFromPoint(e.clientX, e.clientY, base);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (activePointer.current !== e.pointerId || !origin) return;
    updateFromPoint(e.clientX, e.clientY, origin);
  };

  const endTouch = (e: React.PointerEvent) => {
    if (activePointer.current !== e.pointerId) return;
    activePointer.current = null;
    setKnob({ x: 0, y: 0 });
    onChange(0, 0);
    if (mode === "floating") setOrigin(null);
  };

  const basePos =
    mode === "fixed"
      ? { left: "50%", top: "50%", transform: "translate(-50%,-50%)" }
      : origin
        ? { left: 0, top: 0, transform: `translate(${origin.x - 60}px, ${origin.y - 60}px)` }
        : { left: "50%", top: "50%", transform: "translate(-50%,-50%)" };

  return (
    <div
      ref={containerRef}
      className="absolute inset-0 touch-none select-none"
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={endTouch}
      onPointerCancel={endTouch}
      onPointerLeave={endTouch}
    >
      {(mode === "fixed" || origin) && (
        <div
          className="pointer-events-none absolute h-[120px] w-[120px] rounded-full border-2 border-white/25 bg-white/5 backdrop-blur-sm"
          style={basePos}
        >
          <div
            className="absolute h-[52px] w-[52px] rounded-full bg-emerald-300/70 shadow-[0_0_18px_rgba(110,231,183,0.7)]"
            style={{
              left: "50%",
              top: "50%",
              transform: `translate(calc(-50% + ${knob.x}px), calc(-50% + ${knob.y}px))`,
            }}
          />
        </div>
      )}
    </div>
  );
}
