---
name: ui-design
description: Design-first UI/UX workflow. Use Stitch MCP to preview layouts, Figma MCP to pull design specs, and generate production-ready components with proper responsive design, accessibility, and design system tokens. Always design before you code.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# UI/UX Design-First Workflow

Design before you code. This skill enforces a design-first approach where you preview, validate, and iterate on the UI before writing production code.

## Philosophy

1. **See it first** — Use Stitch to generate a visual preview of the layout
2. **Match the spec** — Pull design tokens, spacing, colors from Figma
3. **Build it right** — Generate accessible, responsive, production-ready components
4. **Validate it** — Preview the result and iterate

## Step 1: Understand the Design Intent

Before touching any code, clarify:
- What is the user trying to accomplish on this page/screen?
- What is the information hierarchy? (What's most important?)
- What interactions exist? (Clicks, hovers, forms, modals, transitions)
- What states need handling? (Loading, empty, error, success, disabled)

Read existing design files if available:
```bash
# Check for Figma links in docs
grep -r "figma.com" . --include="*.md" 2>/dev/null
# Check for design tokens
find . -name "*.css" -o -name "tailwind.config*" -o -name "theme*" 2>/dev/null | head -10
```

## Step 2: Preview with Stitch

Use the Stitch MCP to generate a visual preview BEFORE writing code:

1. Describe the layout you want to build
2. Let Stitch generate a preview
3. Iterate on the preview until it matches the intent
4. Only then proceed to code

This saves hours of back-and-forth between code and browser.

## Step 3: Pull Design Specs from Figma

If a Figma file exists, use the Figma MCP to extract:
- **Colors**: Exact hex/rgb values, not approximations
- **Typography**: Font family, size, weight, line-height
- **Spacing**: Margins, padding, gaps (map to design system tokens)
- **Components**: Existing component patterns to reuse
- **Responsive breakpoints**: Mobile, tablet, desktop layouts

## Step 4: Build Components

### Design System Tokens
Always use the project's design system. Never hardcode values:
```css
/* BAD */
color: #3b82f6;
padding: 16px;

/* GOOD */
color: var(--color-primary);
padding: var(--spacing-4);
```

### Accessibility Checklist
Every component MUST have:
- [ ] Semantic HTML (`<nav>`, `<main>`, `<section>`, `<button>`, not `<div>` for everything)
- [ ] ARIA labels on interactive elements without visible text
- [ ] Keyboard navigation (tab order, Enter/Space activation, Escape to close)
- [ ] Color contrast: 4.5:1 minimum for text, 3:1 for large text
- [ ] Focus indicators: visible focus ring on all interactive elements
- [ ] Alt text on images (descriptive, not "image of...")
- [ ] Screen reader announcements for dynamic content changes

### Responsive Design
Build mobile-first, then scale up:
```
1. Mobile: < 640px  — Single column, stacked layout
2. Tablet: 640-1024px — Two columns, sidebar collapses
3. Desktop: > 1024px — Full layout with sidebars
```

### Component States
Every interactive component needs ALL states:
- **Default** — Normal appearance
- **Hover** — Visual feedback on mouse over
- **Active/Pressed** — Click/tap feedback
- **Focus** — Keyboard navigation indicator
- **Disabled** — Greyed out, non-interactive
- **Loading** — Skeleton or spinner
- **Error** — Red border, error message
- **Empty** — Placeholder content, call to action

## Step 5: Validate

After building:
1. Use Playwright to take screenshots at different viewport sizes
2. Compare against the Stitch preview or Figma spec
3. Check accessibility with automated tools
4. Verify all states render correctly

## Anti-Patterns to Avoid
- Building UI without seeing a preview first
- Hardcoding colors, fonts, or spacing values
- Ignoring mobile layout ("we'll make it responsive later")
- Missing loading/error/empty states
- Using `<div>` and `<span>` for everything
- "Pixel perfect" at the cost of accessibility
- Building custom components when the design system has one
