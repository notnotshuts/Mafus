# Mafus website

Next.js App Router + React + TypeScript. Static export for GitHub Pages and Sites. Tailwind CSS v4, shadcn/ui (Radix primitives), Lucide, Motion and next-themes. Inter is self-hosted; supported Apple devices use the system font.

```sh
npm ci
npm run dev
npm run typecheck
npm test
NEXT_PUBLIC_BASE_PATH=/Mafus npm run build
```

`dist/` is generated, not checked in. GitHub Pages builds with `/Mafus`; Sites builds with an empty base path. Release metadata comes from the public GitHub API. Cached data is a network-error fallback; every page load revalidates. No credentials, tracking or build-time version strings are shipped to the browser.

Duck/Utya assets and attribution are in `public/ducks`; the GIFs always appear. Other motion follows the system Reduce Motion preference.
