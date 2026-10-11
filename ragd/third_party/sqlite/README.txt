Optional offline vendoring location.

Put SQLite's official amalgamation files here:
  sqlite3.c
  sqlite3.h

Then configure with:
  cmake -S . -B build -DRAGD_SQLITE_MODE=vendored

Without these files, the default build uses system SQLite on Unix when available,
and downloads the pinned official SQLite 3.53.4 amalgamation on Windows / fallback.
