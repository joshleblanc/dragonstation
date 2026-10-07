require "test_helper"

# The vendored HTML5 build is game-independent except for the seven
# GDragonRuby* variables dragonruby-publish writes per game. Everything after
# them is generic, which is what lets this app serve a cartridge it never
# bundled.
class Html5BuildTest < ActiveSupport::TestCase
  setup do
    console_version!
    @cartridge = ingest(space_cart, user: users(:one), title: "Space Rocks")
    @loader = @cartridge.stager.build.loader
  end

  test "the build this app serves is present and complete" do
    assert Html5Build.available?, "public/dragonruby is missing files"
  end

  test "names the cartridge in its header" do
    assert_match(/var GDragonRubyGameId = "space";/, @loader)
    assert_match(/var GDragonRubyGameTitle = "Space Rocks";/, @loader)
  end

  test "takes the developer title and version from the cartridge's metadata" do
    assert_match(/var GDragonRubyDevTitle = "Console";/, @loader)
    assert_match(/var GDragonRubyGameVersion = "1.0";/, @loader)
  end

  test "gives each cartridge its own save directory" do
    # Otherwise two cartridges share one IndexedDB store and read each other's
    # saves.
    assert_match(/var GDragonRubyWriteDir = "\/dragonruby-space";/, @loader)
  end

  test "points the icon at the metadata this app serves" do
    assert_match %r{var GDragonRubyIcon = "/metadata/icon\.png";}, @loader
  end

  test "is the vendored loader with only its header replaced" do
    vendored = Html5Build::ROOT.join(Html5Build::LOADER).read

    # Everything after the header is byte-identical to what DragonRuby shipped,
    # which is what makes the vendored file checkable against a real build.
    strip = ->(s) { s.sub(Html5Build::HEADER_PATTERN, "") }

    assert_equal strip.call(vendored), strip.call(@loader)
  end

  test "still fetches the manifest and gamedata generically" do
    # The whole design rests on this: the loader is not baked with a file list.
    assert_match(/manifest\.json/, @loader)
    assert_match(/loadDataFiles\(GDragonRubyGameId, 'gamedata\//, @loader)
  end

  test "two cartridges get different loaders" do
    other = ingest(named_cart("widgets"), user: users(:two), title: "Widgets")

    refute_equal @loader, other.stager.build.loader
    assert_match(/var GDragonRubyGameId = "widgets";/, other.stager.build.loader)
    assert_match(/var GDragonRubyWriteDir = "\/dragonruby-widgets";/, other.stager.build.loader)
  end

  test "a hostile title cannot break out of the generated string" do
    # The title is user-supplied and lands in a generated JavaScript file. A
    # quote in it would otherwise close the literal and the rest of the title
    # would be parsed as code.
    hostile = ingest(
      space_cart,
      user: users(:two),
      title: "evil\"); alert(\"pwned\"); var x=\""
    )

    loader = hostile.stager.build.loader
    header = loader.lines.first(7).join

    assert_equal 7, header.lines.size, "the header leaked extra statements:\n#{header}"
    assert_includes header, '\\"'
    assert_includes header, "alert("
  end

  test "refuses to guess when the vendored loader has no header block" do
    build = Html5Build.new(@cartridge)
    build.instance_variable_set(:@template, "function noHeader() {}")

    error = assert_raises(Html5Build::Missing) { build.loader }

    assert_match(/GDragonRuby header/, error.message)
  end

  test "reports a missing build rather than serving nothing" do
    build = Html5Build.new(@cartridge)

    # Point the template read at a file that is not there, which is what a
    # half-finished vendor copy looks like.
    build.define_singleton_method(:template) do
      raise Html5Build::Missing, "no HTML5 build at #{Html5Build::ROOT.join('nope.js')}"
    end

    error = assert_raises(Html5Build::Missing) { build.loader }

    assert_match(/no HTML5 build/, error.message)
  end
end
