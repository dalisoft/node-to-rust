#!/bin/sh
# All downloaded gems and Bundler state stay inside this project.
set -eu

cd "$(dirname "$0")/.."

export GEM_HOME="$PWD/vendor/gems"
export GEM_PATH="$GEM_HOME"
export BUNDLE_USER_HOME="$PWD/vendor/bundler-home"
export BUNDLE_PATH="$PWD/vendor/bundle"
export BUNDLE_GEMFILE="$PWD/Gemfile"
export PATH="$GEM_HOME/bin:$PATH"

ruby -e 'abort "Ruby >= 3.3 required (see .ruby-version)" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")'

case "${1:-build}" in
  deps)
    gem install bundler -v 4.0.22 --no-document
    make deps
    ;;

  epub|build)
    bundle check
    mkdir -p output

    # Keep the upstream reference EPUB intact while using its Makefile.
    temp_dir=$(mktemp -d)
    trap 'rm -r "$temp_dir"' EXIT
    ln -s "$PWD/book" "$temp_dir/book"

    make --no-print-directory -f "$PWD/Makefile" -C "$temp_dir" book-epub \
      > output/epub-build.log 2>&1
    cat output/epub-build.log
    if grep -E 'asciidoctor: (ERROR|WARNING)' output/epub-build.log; then
      exit 1
    fi

    mv "$temp_dir/from-javascript-to-rust.epub" output/from-javascript-to-rust.epub
    bundle exec ruby scripts/validate.rb
    if [ "${1:-build}" = epub ]; then
      exit 0
    fi

    converter=${EBOOK_CONVERT:-$(command -v ebook-convert || true)}
    if [ -z "$converter" ] && [ -x /Applications/calibre.app/Contents/MacOS/ebook-convert ]; then
      converter=/Applications/calibre.app/Contents/MacOS/ebook-convert
    fi

    if [ -z "$converter" ]; then
      echo 'Set EBOOK_CONVERT to an existing/project-local converter; no library is used.' >&2
      exit 1
    fi

    export CALIBRE_CONFIG_DIRECTORY="$temp_dir/config"
    export CALIBRE_CACHE_DIRECTORY="$temp_dir/cache"

    "$converter" output/from-javascript-to-rust.epub output/from-javascript-to-rust.azw3 \
      --cover book/images/cover.png \
      --output-profile kindle_pw3 --disable-font-rescaling --disable-remove-fake-margins \
      --minimum-line-height 0 --margin-top -1 --margin-bottom -1 --margin-left -1 --margin-right -1 \
      --chapter-mark none --page-breaks-before /
    "$(dirname "$converter")/ebook-meta" output/from-javascript-to-rust.azw3
    bundle exec ruby scripts/validate.rb "$(dirname "$converter")/calibre-debug"
    ;;

  *)
    echo 'Usage: sh scripts/ebooks.sh deps|epub|build' >&2
    exit 2
    ;;
esac
