// Configuration guide: https://rstack.rs/config
import { define } from 'rstack';
import { rstack } from '@heyq02/rstack-config/rstack';

// MoonBit stays on `moon`. This preset only covers repo hygiene.
define.extends([
  rstack({
    lib: false,
    lint: false,
    test: false,
    fmt: {
      singleQuote: true,
      sortPackageJson: true,
      ignorePatterns: [
        '.github/**',
        '.cursor/**',
        'docs/**',
        'playground/**',
        'examples/**',
        'benchmark/**',
        'src/**',
        'scripts/**',
        '**/*.md',
        '**/*.mbt',
        'pnpm-lock.yaml',
        '_build/**',
        'target/**',
        '.mooncakes/**',
      ],
    },
    staged: {
      formatAll: true,
      lintFix: false,
    },
  }),
]);
