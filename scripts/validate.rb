# Validate EPUB structure, links, original content/images and AZW3 fidelity.
require 'zip'
require 'nokogiri'
require 'digest'
require 'pathname'
require 'uri'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
BOOK = 'from-javascript-to-rust'
DC_NAMESPACE = { 'dc' => 'http://purl.org/dc/elements/1.1/' }.freeze

def xml(data)
  Nokogiri::XML(data) { |config| config.strict.nonet }
end

def archive(path)
  system('unzip', '-tq', path, exception: true)

  Zip::File.open(path) do |zip|
    unless zip.first.name == 'mimetype' && zip.first.compression_method.zero?
      raise 'Invalid EPUB mimetype entry'
    end

    files = zip.reject(&:directory?).to_h do |entry|
      [entry.name, entry.get_input_stream.read]
    end

    raise 'Invalid EPUB mimetype' unless files['mimetype'] == 'application/epub+zip'

    files
  end
end

def pages(files, strict: false)
  files.filter_map do |name, data|
    next unless name.match?(/\.(?:x?html|htm)$/i)

    document = strict ? xml(data) : Nokogiri::HTML(data)
    [name, document.remove_namespaces!]
  end.to_h
end

def content(documents)
  %w[heading pre].to_h do |kind|
    selector = kind == 'heading' ? 'h1,h2,h3,h4,h5,h6' : 'pre'
    texts = documents.values.flat_map do |doc|
      doc.css(selector).map do |node|
        node.text.unicode_normalize(:nfkc).delete("\u00ad\u200b").split.join(' ')
      end
    end

    [kind, texts]
  end
end

def preserves(before, after)
  before.each do |kind, texts|
    counts = after.fetch(kind).tally
    missing = texts.tally.select { |text, count| counts.fetch(text, 0) < count }

    raise "Missing #{kind}: #{missing.inspect}" unless missing.empty?

    puts "#{kind}: #{texts.size} original, #{after[kind].size} rebuilt, none lost"
  end
end

def links(files, documents)
  ids = documents.transform_values do |doc|
    doc.xpath('//@id | //a/@name').map(&:value)
  end
  refs = documents.flat_map do |name, doc|
    doc.xpath('//@href | //@src').map { |attr| [name, attr.value] }
  end

  files.each do |name, data|
    next unless name.end_with?('.ncx')

    doc = xml(data).remove_namespaces!
    refs.concat(doc.xpath('//content/@src').map { |attr| [name, attr.value] })
  end

  refs.each do |name, raw|
    next if raw.empty? || raw.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|//)}i)

    target, fragment = raw.split('#', 2)
    target = URI::DEFAULT_PARSER.unescape(target.split('?', 2).first.to_s)
    fragment = URI::DEFAULT_PARSER.unescape(fragment.to_s)
    target = if target.empty?
      name
    else
      Pathname.new(File.join(File.dirname(name), target)).cleanpath.to_s
    end

    raise "Missing resource: #{name} -> #{raw}" unless files.key?(target)

    if !fragment.empty? && ids.key?(target) && !ids[target].include?(fragment)
      raise "Missing anchor: #{name} -> #{raw}"
    end
  end

  puts "#{refs.size} links/resources checked; none broken"
end

def validate_metadata(epub)
  container = xml(epub.fetch('META-INF/container.xml')).remove_namespaces!
  metadata = xml(epub.fetch(container.at_xpath('//rootfile')['full-path']))
  expected_fields = {
    'title' => 'Go From JavaScript to Rust',
    'creator' => 'Jarrod Overson',
    'language' => 'en'
  }

  expected_fields.each do |field, expected|
    actual = metadata.at_xpath("//dc:#{field}", DC_NAMESPACE)&.text
    raise "Incorrect #{field}: #{actual.inspect}" unless actual == expected
  end
end

def validate_images(epub)
  images = ['cover.png'] + Dir['book/chapters/*.adoc'].flat_map do |file|
    File.read(file).scan(/image::([^\[]+)\[/).flatten
  end
  hashes = epub.values.map { |data| Digest::SHA256.hexdigest(data) }

  images.uniq.each do |name|
    source_hash = Digest::SHA256.file("book/images/#{name}").hexdigest
    raise "Source image changed/missing: #{name}" unless hashes.include?(source_hash)
  end

  puts "All #{images.uniq.size} source images and title/author/language preserved"
end

def validate_azw3(converter, epub, documents)
  Dir.mktmpdir('node-to-rust-azw3-') do |folder|
    target = File.join(folder, 'book')
    system(converter, '--explode-book', "output/#{BOOK}.azw3", target, exception: true)

    files = Dir.glob('**/*', base: target).filter_map do |name|
      path = File.join(target, name)
      [name, File.binread(path)] if File.file?(path)
    end.to_h

    preserves(content(documents), content(pages(files)))
    image_count = epub.keys.count { |name| name.match?(/\.(png|gif|jpe?g|svg)$/i) }
    raise 'AZW3 images lost' unless Dir.glob("#{target}/images/*").size >= image_count

    puts "AZW3 preserves EPUB headings/code and #{image_count} images"
  end
end

def validate(converter = nil)
  Dir.chdir(ROOT) do
    epub = archive("output/#{BOOK}.epub")
    documents = pages(epub, strict: true)
    links(epub, documents)

    before = content(pages(archive("#{BOOK}.epub")))
    # The original converter leaked AsciiDoc's {pp} instead of emitting ++.
    before['pre'].map! { |text| text.gsub('{pp}', '++') }
    preserves(before, content(documents))

    validate_metadata(epub)
    validate_images(epub)
    validate_azw3(converter, epub, documents) if converter
  end
end

validate(ARGV[0]) if $PROGRAM_NAME == __FILE__
