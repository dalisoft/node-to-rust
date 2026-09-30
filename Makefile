# Enforce bash as the shell for consistency
SHELL := bash
# Use bash strict mode
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.PHONY: book
book:
	bundle exec asciidoctor-pdf -a source-highlighter=rouge book/book.adoc --o from-javascript-to-rust.pdf

.PHONY: book-epub
book-epub:
	sh scripts/ebooks.sh epub

.PHONY: ebooks
ebooks:
	sh scripts/ebooks.sh build

.PHONY: deps
deps:
	sh scripts/ebooks.sh deps
