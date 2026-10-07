# One vendored copy of the console library, as it will be served to the
# DragonRuby HTML5 build.
#
# This is the Ruby half of what console/publish-cart does with a shell script.
# The script stages a directory so dragonruby-publish has exactly one cart to
# package; here the staged tree is never written to disk -- it is described,
# and the description is served as the loader's manifest. The rules the script
# enforces are the rules this class reproduces:
#
#   * the library travels with every cart, because a cart is meaningless
#     without it;
#   * the library's own app/main.rb is the require list, read from the real
#     file rather than duplicated, so a library update cannot leave a stale
#     copy of it behind;
#   * the entry point that gets served pins one cart, so a build that is only
#     *able* to run that cart is a property of the build.
class ConsoleLibrary
  class Missing < StandardError; end

  ROOT = Rails.root.join("vendor/console")

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
  # directory is labelled with the version it actually contains.
  VERSION_CONSTANT = /\b([A-Z]+)\s*=\s*(\d+)\b/

  attr_reader :console_version

  # Where the vendored libraries live. A method rather than a bare constant so
  # a test can point it at a fixture directory and prove that two cartridges
  # pinned to two versions really do keep serving two different libraries.
  def self.root = ROOT

  # Takes a ConsoleVersion, or a bare version string for callers that are
  # inspecting a directory that has no row yet -- the install task is exactly
  # that case, since it has to decide whether to create the row.
  def initialize(console_version)
    @console_version =
      if console_version.is_a?(ConsoleVersion)
        console_version
      else
        ConsoleVersion.new(version: console_version.to_s)
      end
  end

  def directory = self.class.root.join(console_version.version)

  def entry_path = directory.join(ENTRY_TEMPLATE)

  def available? = entry_path.file?

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

  def file?(relative) = absolute(relative).file?

  def size_of(relative) = absolute(relative).size

  def read(relative)
    absolute(relative).binread
  rescue SystemCallError => e
    raise Missing, "console #{console_version.version} has no readable #{relative}: #{e.message}"
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
  # Checked against the directory name on load. A directory copied to the wrong
  # version name would otherwise be served to every new upload under a label
  # nobody can reconcile with the code, which is the kind of drift that is only
  # noticed much later.
  def declared_version
    return nil unless file?(MODULE_PREFIX + "version.rb")

    constants = read(MODULE_PREFIX + "version.rb").scan(VERSION_CONSTANT).to_h
    %w[MAJOR MINOR PATCH].map { |k| constants[k] }.compact.join(".")
  end

  # True when the directory is labelled with the version it contains.
  def label_matches_contents?
    declared = declared_version
    declared.present? && declared == console_version.version
  end

  private
    def absolute(relative)
      base = directory.expand_path.to_s
      candidate = Pathname.new(base).join(relative.to_s).expand_path.to_s

      # Containment check. The manifest and the runtime both turn a path from
      # these lists into a read, and a path that escaped the library directory
      # would read arbitrary files off the server.
      unless candidate == base || candidate.start_with?(base + File::SEPARATOR)
        raise Missing, "console library path escapes the library: #{relative}"
      end

      Pathname.new(candidate)
    end
end
