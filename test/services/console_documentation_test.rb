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
end
