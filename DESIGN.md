---
version: "1.0"
name: "VPP Digital Control Room — 新能源数字控制舱"
description: "深海蓝黑背景 + 冷色能量流 + 半透明玻璃面板 + 精细数据动效。专业、克制、实时、能源流动、数字孪生、控制中心。Built from shadcn/ui Luma geometry, Impeccable Operate mode, Taste Skill anti-slop rules, and ui-ux-pro-max accessibility guidelines."
colors:
  canvas: "#090d14"
  surface: "#111620"
  overlay: "#161b28"
  line: "#1c2533"
  accent: "#3b82f6"
  accentHover: "#2563eb"
  accentMuted: "rgba(59,130,246,0.12)"
  ink: "#e8ecf2"
  muted: "#8b95a5"
  faint: "#545d6b"
  green: "#10b981"
  red: "#ef4444"
  amber: "#f59e0b"
  indigo: "#6366f1"
typography:
  display:
    fontFamily: "Outfit"
    fontWeight: 800
    letterSpacing: "-0.035em"
  heading:
    fontFamily: "Outfit"
    fontWeight: 600
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Outfit"
    fontWeight: 400
    lineHeight: 1.6
  mono:
    fontFamily: "JetBrains Mono"
    fontWeight: 400
  CJB:
    fontFamily: "PingFang SC, Microsoft YaHei, Hiragino Sans GB"
rounded:
  sm: "6px"
  md: "10px"
  lg: "14px"
  xl: "20px"
  full: "9999px"
spacing:
  base: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  "2xl": "48px"
  "3xl": "64px"
motion:
  base: "200ms cubic-bezier(0.16, 1, 0.3, 1)"
  slow: "400ms cubic-bezier(0.16, 1, 0.3, 1)"
  spring: "spring(1, 100, 20)"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#ffffff"
    rounded: "{rounded.full}"
    padding: "10px 24px"
    fontSize: "0.875rem"
    fontWeight: 600
  card:
    backgroundColor: "{colors.surface}"
    borderColor: "{colors.line}"
    rounded: "{rounded.lg}"
    padding: "20px"
  kpi-card:
    backgroundColor: "{colors.surface}"
    borderColor: "{colors.line}"
    rounded: "{rounded.lg}"
    padding: "20px"
    hoverBorderColor: "{colors.accent}"
---

# VPP Control Room — Design System

## 1. Visual Theme & Atmosphere

**Mood**: Control room. Late-night grid operations. Calm precision under pressure.
**Density**: Medium-high (dashboard) / Medium (landing). Information breathes but never wastes space.
**Philosophy**: Data is the product. Every pixel of decoration must earn its place. The interface recedes; the numbers speak.

Key aesthetic anchors:
- Dark canvas (`#090d14`) — deep enough to make glowing data pop, never pure black
- Single accent (`#3b82f6` blue) — reserved for action, selection, and critical data highlights
- Monospace for numbers, sans for labels — the boundary between reading and scanning
- Particle network background — a living energy grid, ambient but never distracting
- No glassmorphism, no gradients on UI surfaces — solid cards with 1px borders, elevation via shadow not blur

## 2. Color Palette & Roles

| Token | Hex | Role |
|-------|-----|------|
| `canvas` | `#090d14` | Page background |
| `surface` | `#111620` | Cards, elevated containers |
| `overlay` | `#161b28` | Hover states, headers, tooltips |
| `line` | `#1c2533` | Borders, dividers, grid lines |
| `accent` | `#3b82f6` | CTAs, active nav, selected state, KPI highlights |
| `accentHover` | `#2563eb` | Button hover, link hover |
| `accentMuted` | `rgba(59,130,246,0.12)` | Selected backgrounds, focus rings |
| `ink` | `#e8ecf2` | Primary text, headlines, KPI values |
| `muted` | `#8b95a5` | Secondary text, descriptions, chart labels |
| `faint` | `#545d6b` | Tertiary text, placeholders, disabled |
| `green` | `#10b981` | Positive metrics, success, safe zone |
| `red` | `#ef4444` | Alerts, errors, danger zone |
| `amber` | `#f59e0b` | Warnings, cost metrics |
| `indigo` | `#6366f1` | Auxiliary accent (charts only) |

**One-accent discipline**: `accent` blue is the ONLY accent on UI surfaces. Green/red/amber are SEMANTIC colors — used exclusively for metric values and alert states, never for decoration. Indigo is chart-only.

## 3. Typography Rules

| Level | Family | Size | Weight | Line-height | Usage |
|-------|--------|------|--------|-------------|-------|
| Display | Outfit | `clamp(2.25rem, 6vw, 4rem)` | 800 | 1.08 | Hero headline only |
| H1 | Outfit | `1.75rem` | 700 | 1.15 | Section titles |
| H2 | Outfit | `1.25rem` | 600 | 1.2 | Card titles |
| H3 | Outfit | `1.0625rem` | 600 | 1.25 | Subsection headers |
| Body | Outfit | `0.9375rem` | 400 | 1.6 | Paragraphs, descriptions |
| Body-sm | Outfit | `0.8125rem` | 400 | 1.55 | Card body, secondary info |
| Caption | Outfit | `0.6875rem` | 500 | 1.4 | Labels, eyebrows, meta |
| KPI | Outfit | `1.875rem` | 700 | 1.1 | Dashboard metric values |
| Mono | JetBrains Mono | `0.75rem` | 400 | 1.5 | Data, logs, code, timestamps |

**Font stack**: `'Outfit', 'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB', system-ui, sans-serif`
**Mono stack**: `'JetBrains Mono', 'SF Mono', 'Cascadia Code', Consolas, monospace`
**No Inter. No serif displays. No emoji as icons.**

## 4. Component Stylings

### Buttons
- **Primary**: `bg-accent text-white rounded-full px-5 py-2.5 font-semibold text-sm`
  - Hover: `bg-accentHover shadow-[0_0_24px_rgba(59,130,246,0.25)]`
  - Active: `scale-[0.97]`
  - Focus: `ring-2 ring-accent/50 ring-offset-2 ring-offset-canvas`
- **Secondary**: `border border-line text-ink rounded-full px-5 py-2.5 text-sm`
  - Hover: `border-accent bg-overlay`
- **Ghost**: `text-muted text-sm` → hover `text-ink`

### Cards
- All cards: `bg-surface border border-line rounded-lg p-5`
- Hover: `border-accent/30 shadow-[0_4px_24px_rgba(0,0,0,0.3)]`
- KPI cards additionally: metric value in semantic color, label in `muted` uppercase caption

### Charts
- Canvas background: transparent (inherits card background)
- Grid lines: `line` at 0.5px, dashed
- Data colors: accent blue, indigo, green, amber — never all at once; pick what the data needs
- Tooltip: `bg-overlay border border-line rounded-md text-xs`

### Inputs (future)
- `bg-surface border border-line rounded-md px-3 py-2 text-ink`
- Focus: `border-accent ring-1 ring-accent/30`
- Placeholder: `faint`

### Navigation
- Active item: `bg-accentMuted text-accent`
- Inactive: `text-muted` → hover `text-ink`

## 5. Layout Principles

### Spacing Scale (4px base)
`4, 8, 12, 16, 20, 24, 32, 48, 64, 96`

### Grid
- Dashboard: 6-column bento grid, `gap: 16px`
- Landing: single-column centered, `max-width: 960px` for content, `max-width: 1200px` for feature grids
- Cards use `padding: 20px` (5× base unit)

### Container widths
- Landing content: `max-w-3xl` (768px)
- Landing feature grid: `max-w-5xl` (1024px)
- Dashboard: `max-w-[1520px]`

### Whitespace philosophy
- Section gaps: `py-20` to `py-28` on landing
- Card gaps: `gap-4` (16px)
- KPI row to first chart: same gap as card-to-card
- Never use empty cards as spacers

## 6. Depth & Elevation

**No drop shadows on static cards.** Cards separate via 1px borders + background contrast.

Shadow used ONLY for:
- Sticky header: `shadow-[0_1px_0_rgba(28,37,51,0.8)]` (subtle bottom edge)
- Hover lift: `shadow-[0_4px_24px_rgba(0,0,0,0.3)]`
- CTA glow: `shadow-[0_0_24px_rgba(59,130,246,0.25)]`

Z-index scale:
- `0`: Particle canvas
- `1`: Page content
- `10`: Sticky header
- `50`: Modal/overlay

## 7. Do's and Don'ts

### DO
- Use monospace for ALL numbers, timestamps, log entries
- Use `font-variant-numeric: tabular-nums` for KPI values
- Provide skeleton loaders matching final layout shape
- Honor `prefers-reduced-motion` — particle system and all animations
- Use WCAG AA contrast (4.5:1) for all text
- Use 44×44px minimum touch targets on mobile
- Use semantic color naming — never `blue-500`, always `accent`

### DON'T
- NO emoji as icons or design elements
- NO AI-purple gradients or shimmer text on headlines
- NO Inter font family
- NO serif displays
- NO glassmorphism on dashboard cards
- NO `h-screen` — use `min-h-[100dvh]`
- NO `window.addEventListener('scroll')` for animation
- NO fake dashboard screenshots built from divs
- NO 3-equal-card feature rows
- NO decorative status dots (unless conveying real semantic state)
- NO centered hero when DESIGN_VARIANCE > 4
- NO em-dashes (—) anywhere

## 8. Responsive Behavior

| Breakpoint | Grid | Notes |
|-----------|------|-------|
| ≥ 1024px | 6 columns | Full bento dashboard |
| 768–1023px | 2 columns | KPI cards 2-wide, charts full-width |
| < 768px | 1 column | All cards stack, nav collapses |
| < 480px | 1 column | Reduced font sizes, full-width buttons |

Touch targets: minimum 44×44px with 8px spacing between interactive elements.

## 9. Agent Prompt Guide

### Quick color reference (Tailwind custom colors)
```
surface: { DEFAULT:'#090d14', raised:'#111620', overlay:'#161b28', border:'#1c2533' }
accent: { DEFAULT:'#3b82f6', hover:'#2563eb', muted:'rgba(59,130,246,0.12)' }
content: { primary:'#e8ecf2', secondary:'#8b95a5', muted:'#545d6b' }
metric: { green:'#10b981', red:'#ef4444', amber:'#f59e0b', info:'#6366f1' }
```

### One-line design read
"Dark tech control-room dashboard for grid operators, Outfit + JetBrains Mono, single blue accent, data-forward with particle network ambient background."

### Build prompt for agents
```
Build a {page type} for a virtual power plant monitoring platform.
Design system: DESIGN.md at project root.
Mode: Operate (dashboard) / Persuade (landing).
Dials: VARIANCE=6, MOTION=4, DENSITY=7 (dashboard) / VARIANCE=7, MOTION=5, DENSITY=4 (landing).
```
