# One console library, read either from the blobs stored against a
# ConsoleVersion or -- with `entries:` -- from path => bytes in hand, which is
# how an upload is validated before any row exists for it.
class ConsoleLibrary
  class Missing < StandardError; end

  # Never served verbatim: it is the require list, and the served entry point
  # is generated to pin one cart.
  ENTRY_TEMPLATE = "app/main.rb"
  MODULE_PREFIX = "app/console/"

  # Read from the game root, so they cannot live in a cart. Varies by version.
  FONT_CANDIDATES = %w[font.ttf tiny.ttf].freeze

  REQUIRE_PATTERN = %r{^require\s+'(app/console/[^']+)'\s*$}
  VERSION_CONSTANT = /\b([A-Z]+)\s*=\s*(\d+)\b/

  attr_reader :console_version

  # Takes a ConsoleVersion, or a version string for a library with no row yet.
  def initialize(console_version, entries: nil)
    @console_version = console_version.is_a?(ConsoleVersion) ? console_version : ConsoleVersion.new(version: console_version.to_s)
    @entries = entries&.transform_keys(&:to_s)
  end

  def candidate? = !@entries.nil?

  # Whether the entry point's *bytes* can be fetched, not just whether its row
  # exists. Rows outlive their blobs when the storage service changes, and a
  # version that answered "available" while every read raised took down every
  # page that merely listed versions.
  def available?
    return @available unless @available.nil?

    @available = candidate? ? file?(ENTRY_TEMPLATE) : !!records[ENTRY_TEMPLATE]&.readable?
  end

  def entry_source = @entry_source ||= read(ENTRY_TEMPLATE)

  # In require order, which is load-bearing: never sort this.
  def require_paths = @require_paths ||= entry_source.scan(REQUIRE_PATTERN).flatten.freeze

  # Every library file the served tree contains.
  def file_paths = @file_paths ||= (require_paths + fonts).freeze

  def fonts = @fonts ||= FONT_CANDIDATES.select { |f| file?(f) }.freeze

  # Every stored path, sorted.
  def paths = @paths ||= (candidate? ? @entries.keys : records.keys).sort

  def file?(relative) = !lookup(relative).nil?

  def size_of(relative)
    entry = lookup(relative) or raise_missing(relative)
    candidate? ? entry.bytesize : entry.byte_size
  end

  def read(relative)
    entry = lookup(relative) or raise_missing(relative)
    candidate? ? entry : entry.read
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, ActiveRecord::RecordNotFound
    # A row without bytes is the same as no row: every caller already rescues Missing.
    raise_missing(relative)
  end

  # The loader re-downloads when filetime moves; the version's creation time
  # moves exactly when the library does.
  def filetime = console_version.created_at.to_i

  # Changes exactly when the stored bytes do. Keyed on blob ids, not created_at,
  # because console:install can refill a row without moving it. SHA rather than
  # #hash, which is seeded per process.
  def content_token
    @content_token ||= Digest::SHA256.hexdigest(
      records.map { |path, file| "#{path}\0#{file.blob&.id}" }.sort.join("\n")
    )
  end

  # MAJOR.MINOR.PATCH from app/console/version.rb, or nil when unreadable.
  def declared_version
    path = MODULE_PREFIX + "version.rb"
    return nil unless file?(path)

    constants = read(path).scan(VERSION_CONSTANT).to_h
    %w[MAJOR MINOR PATCH].filter_map { |k| constants[k] }.join(".")
  rescue Missing
    nil
  end

  def label_matches_contents?
    declared = declared_version
    declared.present? && declared == console_version.version
  end

  private
    # with_attached_blob: reading bytes is the point, and without it each file
    # costs two extra queries (and a network round trip per query on Spaces).
    def records
      @records ||= console_version.console_library_files.with_attached_blob.index_by(&:path)
    end

    # Exact-key lookup into a hash or rows, so there is no filesystem for a
    # path to escape into.
    def lookup(relative)
      candidate? ? @entries[relative.to_s] : records[relative.to_s]
    end

    def raise_missing(relative)
      raise Missing, "console #{console_version.version} has no readable #{relative}"
    end
end
