import type { NextConfig } from 'next';
const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? '';
const config: NextConfig = {
  output: 'export', basePath, trailingSlash: true,
  images: {unoptimized: true},
  poweredByHeader: false,
};
export default config;
