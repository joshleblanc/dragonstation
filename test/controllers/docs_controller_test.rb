require "test_helper"

# The documentation pages, over real HTTP.
#
# These are public pages describing a library that lives on disk, so the things
# worth asserting are the ones a reader would notice going wrong: a page that
# renders nothing, a module with no name, a sample that does not appear, and a
# source link that 404s. None of that needs a signed-in user, which is the point
# -- these pages are how someone finds out the site exists.
class DocsControllerTest < ActionDispatch::IntegrationTest
  setup { console_version! }

  test "the documentation is readable without an account" do
    get docs_path

    assert_response :success
    assert_select "h1", /console library/i
  end

  test "the navigation links to the documentation" do
    get root_path

    assert_select "nav a[href=?]", docs_path, text: "Docs"
  end

  test "the guide shows a sample for each thing a first cart needs" do
    get docs_path

    assert_response :success
    ConsoleGuide.new.samples.each do |sample|
      assert_select "##{sample.id}", text: /#{Regexp.escape(sample.title)}/
    end
  end

  test "the samples are shown as highlighted code, not as prose" do
    get docs_path

    # A sample that rendered as an unhighlighted wall of text would still pass a
    # "does it contain the sample" check, so this asks for the token markup.
    assert_select ".doc-sample pre.source span.k", /class/
    assert_select ".doc-sample pre.source span.nc", /Mine/
  end

  test "the guide says when each hook runs" do
    get docs_path

    assert_select "#hooks", /setup/
    ConsoleGuide::HOOKS.each do |hook|
      assert_select "#hooks td", text: /#{Regexp.escape(hook[:when])}/
    end
  end

  test "every module the library requires is linked from the index" do
    get docs_path

    ConsoleVersion.default.library.require_paths.each do |path|
      slug = File.basename(path, ".rb")
      assert_select "a[href=?]", doc_path(slug), count: 1, message: "no link for #{slug}"
    end
  end

  test "a module page names the module and describes its methods" do
    get doc_path("sprites")

    assert_response :success
    assert_select "h1", /Console::Sprites/
    assert_select ".doc-signature", /def path\(name\)/
    assert_select ".doc-method", text: /Resolve a sprite reference/
  end

  # The whole point of reading the library's comments: a method's explanation
  # arrives with the method rather than being maintained beside it.
  test "a method's documentation comes from the comment above it" do
    get doc_path("sprites")

    assert_select "#frames", text: /Collect a numbered directory of frames/
    assert_select "code", /sprites\/hero\/run\/0\.png/
  end

  # A `code` span is the one piece of markup a doc comment is allowed, so it is
  # the one place escaping can go wrong twice: escaped once into &#39; and again
  # by the tag helper, which is how an apostrophe turns into visible entities.
  test "a comment's own punctuation is escaped once, not twice" do
    get doc_path("sprites")

    assert_includes response.body, "<code>:&#39;misc/star&#39;</code>"
    assert_no_match(/&amp;#39;|&amp;quot;|&amp;amp;#39;/, response.body)
  end

  test "the library's own section headings are kept" do
    get doc_path("sprites")

    assert_select "h2", text: "indexing"
    assert_select "h2", text: "resolution"
    assert_select "h2", text: "procedural generation"
  end

  test "a module page offers the source it is describing" do
    get doc_path("sprites")

    assert_select "a[href=?]", doc_source_path("sprites"), text: "view source"
  end

  test "an undocumented method is still listed, by name" do
    get doc_path("sprites")

    assert_select ".doc-signature", /def indexed\?/
  end

  test "the page says which version of the library it describes" do
    get doc_path("sprites")

    assert_select ".lede", /console #{Regexp.escape(ConsoleVersion.default.version)}/
  end

  # Docs that cannot be checked against the implementation are a guess, so the
  # implementation is one click away -- and it is the same file the game runs.
  test "the source page shows the library's own file, highlighted" do
    get doc_source_path("sprites")

    assert_response :success
    assert_select "pre.source.full span"
    assert_includes response.body, "Console::Sprites"
  end

  test "the source page links back to the module" do
    get doc_source_path("draw")

    assert_select "a[href=?]", doc_path("draw"), text: /back to/
  end

  test "a module that does not exist is a 404, not an empty page" do
    get doc_path("no-such-module")

    assert_response :not_found
  end

  test "there is no source for a module that does not exist" do
    get doc_source_path("no-such-module")

    assert_response :not_found
  end

  test "a module's own name is used rather than its file name" do
    # animation.rb defines Console::Anim, ui.rb defines Console::UI. A page
    # titled from the filename would send people looking for Console::Animation.
    get doc_path("ui")

    assert_select "h1", /Console::UI/
    assert_select "h1", text: /Console::UI/,
      count: 1
    assert_no_match(/<h1><code>ui<\/code>/, response.body)
  end

  # A cart author needs these before they have an account, so a failure to load
  # the library must not look like an invitation to sign in.
  # The same trap as on the settings page: a download has to be a GET, and a
  # button that POSTs matches no route.
  test "a signed-in reader's download is a link, not a form that posts" do
    sign_in_as users(:one)

    get docs_path

    assert_select "a[href=?]", console_bundle_path
    assert_select "form[action=?]", console_bundle_path, count: 0

    get console_bundle_path
    assert_response :success
  end

  test "the pages do not ask an anonymous visitor to sign in" do
    get docs_path
    assert_response :success

    get doc_path("draw")
    assert_response :success
  end

  test "there are no pages to show when no library is installed" do
    # destroy_all, not delete_all: a version's files hang off the row now, so
    # deleting the rows outright leaves the files behind and trips the foreign key.
    ConsoleVersion.destroy_all

    get docs_path
    assert_response :not_found

    get doc_path("sprites")
    assert_response :not_found
  end
end
