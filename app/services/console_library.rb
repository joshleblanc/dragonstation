# One console library, as it will be served to the DragonRuby HTML5 build.
#
# This is the Ruby half of what console/publish-cart does with a shell script.
# The script stages a directory so dragonruby-publish has exactly one cart to
# package; here the library is never a directory at all -- it is a set of blobs
# attached to a ConsoleVersion row, described by path. The rules the script
# enforces are the rules this class reproduces:
#
#   * the library travels with every cart, because a cart is meaningless
#     without it;
#   * the library's own app/main.rb is the require list, read from the stored
#     bytes rather than duplicated, so a library update cannot leave a stale
#     copy of it behind;
#   * the entry point that gets served pins one cart, so a build that is only
#     *able* to run that cart is a property of the build.
#
# One reader serves both a stored library and a candidate that has not been
# stored yet: `entries:` names the bytes directly, which is how an uploaded
# archive is checked before a single row exists for it. The validation below is
# then the same validation that will run again once the bytes land, because it
# is this class doing both.
class ConsoleLibrary
  class Missing < StandardError; end

  # The library's own entry point. It is a template, not something that is
  # ever served verbatim: the served version pins a cart.
  ENTRY_TEMPLATE = "app/main.rb"

  MODULE_PREFIX = "app/console/"

  # Read from the game root by DragonRuby, so they cannot live inside a cart.
  # Which of them exist varies by version, so this is a filter, not a list.
  FONT_CANDIDATES = %w[font.ttf tiny.ttf].freeze

  # A require of a library module, in the exact form app/main.rb writes them.
  REQUIRE_PATTERN = /^require\s+'(app\/console\/[^']+)'\s*$/

  # MAJOR/MINOR/PATCH from app/console/version.rb, used to check that the
  # library is labelled with the version it actually contains.
  VERSION_CONSTANT = /\b([A-Z]+)\s*=\s*(\d+)\b/

  attr_reader :console_version

  # Takes a ConsoleVersion, or a bare version string for callers that are
  # inspecting a library that has no row yet -- the install is exactly that
  # case, since it has to decide which version to create the row under.
  #
  # `entries:` supplies the bytes directly, as path => String. It is how a
  # candidate is read before it is stored, and how a test can hold a library
  # that the database has never seen. With no entries the library is the one
  # stored against the row.
  def initialize(console_version, entries: nil)
    @console_version =
      if console_version.is_a?(ConsoleVersion)
        console_version
      else
        ConsoleVersion.new(version: console_version.to_s)
      end
    @entries = entries&.transform_keys(&:to_s)
  end

  # True when these bytes came from `entries:` rather than from the database.
  def candidate? = !@entries.nil?

  def available? = file?(ENTRY_TEMPLATE)

  def entry_source
    @entry_source ||= read(ENTRY_TEMPLATE)
  end

  # Library modules in require order.
  #
  # Order is load-bearing: the modules reference each other at call time rather
  # than at load time, but main.rb still requires them in an order that has to
  # be preserved exactly. Sorting these alphabetically would be a subtle way to
  # break a library update.
  def require_paths
    @require_paths ||= entry_source.scan(REQUIRE_PATTERN).flatten.freeze
  end

  # Every library file the served tree contains, relative and forward-slashed.
  def file_paths
    @file_paths ||= (require_paths + fonts).freeze
  end

  def fonts
    @fonts ||= FONT_CANDIDATES.select { |f| file?(f) }.freeze
  end

  # Every stored path, sorted. This is what the release bundle walks, in place
  # of the directory listing it used to take.
  def paths
    @paths ||= candidate? ? @entries.keys.sort : records.keys.sort
  end

  # Stored paths directly under a top-level directory, sorted.
  def paths_under(directory)
    prefix = "#{directory}/"

    paths.select { |path| path.start_with?(prefix) }
  end

  def file?(relative)
    lookup(relative) ? true : false
  end

  def size_of(relative)
    entry = lookup(relative) or raise_missing(relative)

    candidate? ? entry.bytesize : entry.byte_size
  end

  def read(relative)
    entry = lookup(relative) or raise_missing(relative)

    candidate? ? entry : entry.read
  end

  # A stable filetime for every file in this library.
  #
  # The loader re-downloads a cached file when filetime moves, so this must not
  # change just because a page was viewed. The version's own creation time is
  # exactly the right granularity: it moves when the library does, and not
  # otherwise.
  def filetime = console_version.created_at.to_i

  # The version string the library itself claims to be, read from version.rb.
  #
  # Checked against the row's version on load. A library stored under a version
  # it does not claim would otherwise be served to every new upload under a
  # label nobody can reconcile with the code, which is the kind of drift that is
  # only noticed much later.
  def declared_version
    return nil unless file?(MODULE_PREFIX + "version.rb")

    constants = read(MODULE_PREFIX + "version.rb").scan(VERSION_CONSTANT).to_h
    %w[MAJOR MINOR PATCH].map { |k| constants[k] }.compact.join(".")
  end

  # True when the row is labelled with the version the library contains.
  def label_matches_contents?
    declared = declared_version
    declared.present? && declared == console_version.version
  end

  private
    # Every stored file, keyed by path.
    def records
      @records ||= console_version.console_library_files.index_by(&:path)
    end

    # The bytes behind one path, from wherever this library is being read.
    #
    # Containment is not re-checked here, because it cannot need checking: a
    # candidate is a hash keyed by the exact path, and a stored library is a
    # row looked up by the same. Neither has a filesystem for a path to escape
    # into, and a path that names nothing is a miss rather than a traversal.
    def lookup(relative)
      path = relative.to_s

      candidate? ? @entries[path] : records[path]
    end

    def raise_missing(relative)
      raise Missing, "console #{console_version.version} has no readable #{relative}"
    end
end