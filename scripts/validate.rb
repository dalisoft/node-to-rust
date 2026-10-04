# Validate EPUB structure, links, original content/images and AZW3 fidelity.
require 'zip'
require 'nokogiri'
require 'digest'
require 'pathname'
require 'uri'
require 'tmpdir'
Dir.chdir(File.expand_path('..', __dir__))
BOOK = 'from-javascript-to-rust'

def archive(path)
  system('unzip', '-tq', path, exception: true)
  Zip::File.open(path) do |zip|
    raise 'Invalid EPUB mimetype entry' unless zip.first.name == 'mimetype' && zip.first.compression_method.zero?
    files = zip.reject(&:directory?).to_h { |entry| [entry.name, entry.get_input_stream.read] }
    raise 'Invalid EPUB mimetype' unless files['mimetype'] == 'application/epub+zip'
    files
  end
end

def pages(files, strict: false)
  files.filter_map do |name, data|
    next unless name.match?(/\.(?:x?html|htm)$/i)
    document = strict ? Nokogiri::XML(data) { |config| config.strict.nonet } : Nokogiri::HTML(data)
    [name, document.remove_namespaces!]
  end.to_h
end

def content(documents)
  %w[heading pre].to_h do |kind|
    selector = kind == 'heading' ? 'h1,h2,h3,h4,h5,h6' : 'pre'
    texts = documents.values.flat_map do |doc|
      doc.css(selector).map { |node| node.text.unicode_normalize(:nfkc).delete("\u00ad\u200b").split.join(' ') }
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
  ids = documents.transform_values { |doc| doc.xpath('//@id | //a/@name').map(&:value) }
  refs = documents.flat_map { |name, doc| doc.xpath('//@href | //@src').map { |attr| [name, attr.value] } }
  files.each do |name, data|
    next unless name.end_with?('.ncx')
    doc = Nokogiri::XML(data) { |config| config.strict.nonet }.remove_namespaces!
    refs.concat(doc.xpath('//content/@src').map { |attr| [name, attr.value] })
  end
  refs.each do |name, raw|
    next if raw.empty? || raw.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|//)}i)
    target, fragment = raw.split('#', 2)
    target = URI::DEFAULT_PARSER.unescape(target.split('?', 2).first.to_s)
    fragment = URI::DEFAULT_PARSER.unescape(fragment.to_s)
    target = target.empty? ? name : Pathname.new(File.join(File.dirname(name), target)).cleanpath.to_s
    raise "Missing resource: #{name} -> #{raw}" unless files.key?(target)
    raise "Missing anchor: #{name} -> #{raw}" if fragment && !fragment.empty? && ids.key?(target) && !ids[target].include?(fragment)
  end
  puts "#{refs.size} links/resources checked; none broken"
end

epub = archive("output/#{BOOK}.epub")
documents = pages(epub, strict: true)
links(epub, documents)
before = content(pages(archive("#{BOOK}.epub")))
before['pre'].map! { |text| text.gsub('{pp}', '++') }
preserves(before, content(documents))
container = Nokogiri::XML(epub.fetch('META-INF/container.xml')) { |config| config.strict.nonet }.remove_namespaces!
metadata = Nokogiri::XML(epub.fetch(container.at_xpath('//rootfile')['full-path'])) { |config| config.strict.nonet }
{ 'title' => 'Go From JavaScript to Rust', 'creator' => 'Jarrod Overson', 'language' => 'en' }.each do |field, expected|
  raise "Incorrect #{field}" unless metadata.at_xpath("//dc:#{field}", 'dc' => 'http://purl.org/dc/elements/1.1/')&.text == expected
end
images = ['cover.png'] + Dir['book/chapters/*.adoc'].flat_map { |file| File.read(file).scan(/image::([^\[]+)\[/).flatten }
hashes = epub.values.map { |data| Digest::SHA256.hexdigest(data) }
images.uniq.each { |name| raise "Source image changed/missing: #{name}" unless hashes.include?(Digest::SHA256.file("book/images/#{name}").hexdigest) }
puts "All #{images.uniq.size} source images and title/author/language preserved"

if ARGV[0]
  Dir.mktmpdir('node-to-rust-azw3-') do |folder|
    target = File.join(folder, 'book')
    system(ARGV.fetch(0), '--explode-book', "output/#{BOOK}.azw3", target, exception: true)
    files = Dir.glob('**/*', base: target).reject { |name| File.directory?(File.join(target, name)) }.to_h { |name| [name, File.binread(File.join(target, name))] }
    preserves(content(documents), content(pages(files)))
    image_count = epub.keys.count { |name| name.match?(/\.(png|gif|jpe?g|svg)$/i) }
    raise 'AZW3 images lost' unless Dir.glob("#{target}/images/*").size >= image_count
    puts "AZW3 preserves EPUB headings/code and #{image_count} images"
  end
end
