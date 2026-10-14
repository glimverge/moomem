import { defineConfig } from 'bumpp';

// package.json is the version bumpp reads. moon.mod and MOOMEM_VERSION
// must already contain that same string; bumpp then replaces it in both.
// SNAPSHOT_VERSION and playground/moon.mod stay out of this list.
export default defineConfig({
  files: ['package.json', 'moon.mod', 'src/lib.mbt'],
  commit: 'chore: release v{version}',
  tag: 'v{version}',
});
