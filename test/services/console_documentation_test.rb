require "test_helper"
require "ripper"
require "test_helper"

# The documentation, exercised against the real library on disk.
#
# These assertions are about extraction, not about the library: that a method's
# comment lands on that method, that the library's own section headings survive,
# and that a cart author's first page is built from something true. The samples
# are the part that can lie quietly, so each one is parsed as Ruby -- a sample
# that does not compile is worse than no sample.
class ConsoleDocumentationTest < ActiveSupport::TestCase
  setup do
    console_version!
    @docs = ConsoleDocumentation.new(ConsoleVersion.default)
  end

  test "every module the library requires gets a page" do
    library = ConsoleVersion.default.library

    assert_operator @docs.modules.size, :>=, 15
    assert_equal library.require_paths.size, @docs.modules.size
    assert_equal library.require_paths.map { |p| File.basename(p, ".rb") }.sort,
      @docs.slugs.sort
  end

  test "pages are in require order, because each module builds on the ones above it" do
    # Read from app/main.rb rather than hard-coded: that order is load-bearing
    # to the library, and a test that pins it to today's list would fail on a
    # library update instead of telling you the ordering was lost.
    required = ConsoleVersion.default.library.require_paths.map { |p| File.basename(p, ".rb") }

    assert_equal required, @docs.slugs
    assert_operator @docs.slugs.index("str"), :<, @docs.slugs.index("geom")
    assert_operator @docs.slugs.index("assets"), :<, @docs.slugs.index("sprites")
    assert_equal "core", @docs.slugs.last
  end

  test "a module's page knows what it defines and what it is for" do
    sprites = @docs.find("sprites")

    assert_equal "Console::Sprites", sprites.name
    assert_match(/Console::Sprites -- name -> texture resolution/, sprites.summary)
    assert_operator sprites.line_count, :>, 100
  end

  # The summary is the one line the index shows, and it is what a reader decides
  # to open the page on. A header that wraps is reflowed and cut at the end of
  # its first sentence, not read as a source line -- which would leave half a
  # sentence in the list.
  test "a summary is a whole sentence, even when the header wraps" do
    @docs.modules.each do |mod|
      next if mod.summary.blank?

      assert mod.summary.end_with?("."), "#{mod.slug}'s summary is cut short: #{mod.summary}"
    end
  end

  test "a method carries the comment written above it" do
    path = @docs.find("sprites").sections.flat_map(&:methods).find { |m| m.name == "frames" }

    assert_equal "def frames(group)", path.signature
    assert_match(/Collect a numbered directory of frames/, path.doc.join(" "))
    assert_match(/sprites\/hero\/run\/0\.png/, path.doc.join(" "))
  end

  test "a signature is read as written, default arguments and all" do
    auto = @docs.find("sprites").sections.flat_map(&:methods).find { |m| m.name == "auto" }

    assert_equal "def auto(args, name, w = 16, h = 16, color = :accent, pattern = :solid)",
      auto.signature
  end

  test "the library's own section headings survive" do
    titles = @docs.find("sprites").sections.map(&:title)

    assert_includes titles, "indexing"
    assert_includes titles, "resolution"
    assert_includes titles, "procedural generation"
  end

  # The library groups with two different rules and both mean the same thing.
  test "an opening-only divider is a heading too, not a method's documentation" do
    methods = @docs.find("sprites").sections.flat_map(&:methods)
    rgba = methods.find { |m| m.name == "rgba" }

    refute_match(/^-{3,}/, rgba.doc.join)
    assert methods.none? { |m| m.doc.any? { |line| line.match?(/\A\s*-{3,}/) } },
      "a divider leaked into a method's documentation"
  end

  test "an undocumented method is listed rather than hidden" do
    names = @docs.find("sprites").sections.flat_map(&:methods).map(&:name)

    assert_includes names, "indexed?"
    assert_includes names, "exists?"
    refute @docs.find("sprites").sections.flat_map(&:methods).find { |m| m.name == "indexed?" }.documented?
  end

  test "methods nested inside a class are found as well as module methods" do
    names = @docs.find("core").sections.flat_map(&:methods).map(&:name)

    assert_includes names, "spawn"
    assert_includes names, "goto"
    assert_includes names, "every"
  end

  test "classes count as modules, so a class-only file still names itself" do
    draw = @docs.find("draw")

    assert_equal "Console::Draw", draw.name
    assert_match(/rendering helper layer/, draw.summary)
  end

  # The header of cart_loader.rb *is* the cart contract, and it is indented in
  # the comment. Rendered as prose it would read as a run-on paragraph, which is
  # the whole difference between documentation and a wall of text.
  test "a usage sample indented in a comment is read as code, not as prose" do
    doc = @docs.find("cart_loader").summary_doc
    blocks = ConsoleDocumentation.blocks(doc)
    code = blocks.select(&:code?).map(&:text).join("\n")

    assert code.present?, "expected the contract's indented runs to be read as code"
    assert_match(/def self\.assets/, code)
    assert_match(/def setup/, code)
    assert_match(/scene :title, TitleScene/, code)
    assert blocks.any? { |b| !b.code? && b.text.include?("A \"cart\" is a directory") }
  end

  test "one unindented line makes a block prose again" do
    blocks = ConsoleDocumentation.blocks([ [ "  draw.text 'READY'", "and then some prose." ] ])

    assert_equal 1, blocks.size
    assert_not blocks.first.code?
  end

  test "a paragraph continued with a backslash is not cut in half" do
    blocks = ConsoleDocumentation.blocks([ "one half \\", "and the other half" ])

    assert_equal 1, blocks.size
    assert_match(/one half and the other half/, blocks.first.text)
  end

  test "an unknown slug is nil rather than an exception" do
    assert_nil @docs.find("no-such-module")
  end

  # A section is linked by its title, so a reader can jump to the half of a
  # module they want. Two sections with the same title would share an id, and
  # the second link would jump to the first.
  test "every section has an anchor of its own, taken from its title" do
    sections = @docs.find("sprites").sections
    anchors = sections.map(&:anchor)

    assert_equal anchors.uniq, anchors
    assert_includes anchors, "indexing"
    assert_includes anchors, "procedural-generation"
  end

  # Two methods with the same name in one module are two elements with the same
  # id: invalid HTML, and a link to it jumps to the first and stops there. The
  # library does this -- `update` is defined in both Console::Anim and its
  # sprite class -- so the anchor has to be made unique rather than the
  # library rewritten.
  test "a method defined twice gets a second anchor rather than a duplicate id" do
    docs = ConsoleDocumentation.new(
      candidate_library("dupes",
        "app/main.rb" => "require 'app/console/dupes.rb'\n",
        "app/console/dupes.rb" => <<~RUBY)
          module Console
            module Dupes
              def update; end
            end

            class Thing
              def update; end
            end
          end
        RUBY
    )

    mod = docs.find("dupes")
    updates = mod.sections.flat_map(&:methods).select { |m| m.name == "update" }
    anchors = updates.map { |m| mod.anchor_for(m) }

    assert_equal 2, updates.size
    assert_equal anchors.uniq, anchors, "two methods share one anchor"
  end

  test "a module that will not parse yields a page that explains itself" do
    # A candidate rather than an installed library: a module that does not parse
    # cannot be installed, which is the whole reason this path exists.
    docs = ConsoleDocumentation.new(
      candidate_library("broken", "app/main.rb" => "require 'app/console/broken.rb'\n",
        "app/console/broken.rb" => "module Broken\n  def oops(\nend\n")
    )

    mod = docs.find("broken")

    assert_equal "broken", mod.slug
    assert_predicate mod.error, :present?
    assert_empty mod.sections
  end

  test "the library's version is stated, so a reader can tell what it matches" do
    assert_equal ConsoleVersion.default.version, @docs.console_version.version
  end

  # --- cost -----------------------------------------------------------------
  #
  # These pages were the slowest thing on the site by a wide margin, and none of
  # it showed up as a slow query. It was the same work repeated: the library read
  # twice over, once per file, and each file parsed three times to answer one
  # question. The assertions below are the shape of the work, which is what
  # regresses -- a query here and there reads as fine right up until it does not.

  # One blob per file, and reading a blob is two queries -- the attachment row
  # and then the blob row -- unless they came back with the file rows. Twenty
  # library files came to cost forty-four queries for one page view.
  test "reading the library does not query per file" do
    files = ConsoleLibrary.new(ConsoleVersion.default).require_paths.size

    # Cold: build the reader's file list and read every file in it.
    cold = count_queries do
      library = ConsoleLibrary.new(ConsoleVersion.default)
      library.require_paths.each { |path| library.read(path) }
    end

    # Warm: the same reader, files already loaded.
    warm_reader = ConsoleLibrary.new(ConsoleVersion.default)
    warm_reader.require_paths
    warm = count_queries { warm_reader.require_paths.each { |path| warm_reader.read(path) } }

    # The rows, the attachments and the blobs, once. An N+1 would put this in
    # the forties for twenty files, which is what it was.
    assert_operator cold, :<, files, "loading #{files} files cost #{cold} queries"
    assert_equal 0, warm, "reading files the reader already holds should cost nothing"
  end

  # Ripper built the whole tree three times per file: once to prove the file
  # parsed, once for the module names, once for the method definitions. Three
  # live parse trees at once is also why this was 180ms of garbage per request.
  test "each file is parsed once, however many questions are asked of it" do
    version = ConsoleVersion.default
    parses = count_parses { ConsoleDocumentation.new(version).modules }

    assert_equal version.library.require_paths.size, parses
  end

  # String#lines builds a fresh array of the whole file, and the two methods
  # that wanted "what is on line 4" each built one -- per method, 436 times
  # over, which is 343,000 line strings to describe a 5,460 line library.
  test "each file is split into lines once, not once per method" do
    version = ConsoleVersion.default
    splits = count_splits { ConsoleDocumentation.new(version).modules }

    assert_equal version.library.require_paths.size, splits
  end

  # --- caching --------------------------------------------------------------

  # What the cache is actually for. A blob read is a download, so on the network
  # storage service this site uses in production it is a round trip, and there is
  # no SQL to count: twenty of them is what made these pages the slowest thing
  # on the site, and a query count cannot see it at all.
  test "a second read of the same library does not read its bytes again" do
    with_cache do
      ConsoleDocumentation.new(ConsoleVersion.default).modules

      # A fresh object per request is what a real second request looks like.
      reads = count_file_reads { ConsoleDocumentation.new(ConsoleVersion.default).modules }

      assert_equal 0, reads, "the library was downloaded again despite being cached"
    end
  end

  test "an uncached read does download the library" do
    with_cache do
      reads = count_file_reads { ConsoleDocumentation.new(ConsoleVersion.default).modules }

      assert_operator reads, :>, 0, "nothing was cached, so this proves nothing"
    end
  end

  # The cache is a database that outlives the process that wrote to it, so what
  # comes back out has to be the same objects that went in -- nested Structs,
  # keyword-init, the lot. A serializer that flattened them to arrays would
  # serve pages that rendered, and rendered wrong.
  test "what comes back out of the cache is the documentation that went in" do
    with_cache do
      fresh = ConsoleDocumentation.new(ConsoleVersion.default).modules

      cached = ConsoleDocumentation.new(ConsoleVersion.default).modules

      assert_equal fresh.map(&:slug), cached.map(&:slug)
      assert_equal fresh.map { |m| m.line_count }, cached.map { |m| m.line_count }
      assert_equal fresh.first.class, cached.first.class
      assert_equal fresh.first.sections.map(&:title), cached.first.sections.map(&:title)
      assert_equal fresh.flat_map { |m| m.sections.flat_map { |s| s.methods.map(&:signature) } },
        cached.flat_map { |m| m.sections.flat_map { |s| s.methods.map(&:signature) } }
    end
  end

  # console:install's restore! is the only thing that writes files behind an
  # installed version, and it replaces the rows and their blobs wholesale. The
  # version row does not move, so a cache keyed on the version would go on
  # describing code that is no longer there -- which is the entire failure
  # restore! exists to repair.
  test "a library whose files are replaced is not served from the old entry" do
    with_cache do
      version = install_console_library("9.9.9")
      version.update!(default: true)

      # Asserted on module_names rather than name: a file that defines nothing
      # but the Console namespace is titled with its file name on purpose, since
      # a page called "Console" would say nothing about what it is for.
      assert_equal [ "Console" ], ConsoleDocumentation.new(ConsoleVersion.default).find("core").module_names

      ConsoleLibraryInstall.restore!(
        console_library_entries("9.9.9", "app/console/core.rb" => "module Console\n  class Late; end\nend\n"),
        version.reload
      )

      assert_includes ConsoleDocumentation.new(ConsoleVersion.default).find("core").module_names,
        "Console::Late",
        "the cache still described the files this library had before it was restored"
    end
  end

  # A candidate is an unpersisted version reading bytes out of a hash, which is
  # what a test holds. Caching one would key every test's throwaway library off
  # the same entry.
  test "a candidate library is never cached" do
    with_cache do
      library = candidate_library("broken", "app/console/broken.rb" => "module Broken\n  def oops(\nend\n")

      # Counted rather than read back out of the store, because what matters is
      # that the work happened twice -- not that some particular store kept its
      # bookkeeping tidy.
      first = count_parses { ConsoleDocumentation.new(library).modules }

      second = count_parses { ConsoleDocumentation.new(library).modules }

      assert_operator first, :>, 0, "the candidate was never parsed at all, so this proves nothing"
      assert_equal first, second, "a candidate was served from the cache"
    end
  end

  private
    # The app runs on :null_store in tests, which is right -- it stops one test's
    # library from answering another -- but it also means the cache is inert
    # unless a test asks for it by name.
    def with_cache
      previous = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous
    end

    def count_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        count += 1 unless payload[:name] == "SCHEMA"
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def count_parses(&block) = counted(:parses, &block)

    def count_splits(&block) = counted(:splits, &block)

    # Counted on ConsoleLibraryFile#read rather than on a download notification,
    # because this is the method every blob read in the app goes through and the
    # assertion is about the library's files, not about a storage service's
    # internals.
    def count_file_reads(&block) = counted(:file_reads, &block)

    # Ripper, String and ConsoleLibraryFile are each patched once, here, rather
    # than once per assertion: prepending inside the helper would stack another
    # module onto the class every time a test asked for a count.
    COUNTED = { parses: 0, splits: 0, file_reads: 0 }

    Ripper.singleton_class.prepend(Module.new do
      define_method(:sexp) { |*args, **kwargs, &block| COUNTED[:parses] += 1; super(*args, **kwargs, &block) }
    end)

    String.prepend(Module.new do
      define_method(:lines) { COUNTED[:splits] += 1; super() }
    end)

    ConsoleLibraryFile.prepend(Module.new do
      def read = (COUNTED[:file_reads] += 1; super())
    end)

    # Only the work inside the block is counted. String#lines is called by
    # plenty of things the documentation build does not do, and the point of
    # these counts is what this code asks of the file it is reading.
    def counted(key)
      COUNTED[key] = 0
      yield
      COUNTED[key]
    end
end
