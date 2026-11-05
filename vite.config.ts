import { defineConfig } from 'vite';

// `base: './'` keeps the production build relocatable (any folder or static host).
export default defineConfig({
  base: './',
  build: { outDir: 'dist', sourcemap: true },
});
