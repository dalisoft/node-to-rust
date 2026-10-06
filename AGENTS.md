# Project guidance

- Build with the existing Makefile through `sh scripts/ebooks.sh build`; dependencies and converter configuration stay project-local.
- Use the Ruby version in `.ruby-version` and the locked gems. Validate with `ruby -c scripts/validate.rb`, `sh -n scripts/ebooks.sh`, and the existing ebook validator.
- Preserve the author's cover, content, images, links and styling. Never read or package a personal Calibre library in CI.
- Keep changes focused and clean only identified task-created temporary files.
