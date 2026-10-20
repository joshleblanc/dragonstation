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

    assert_select "#structure", /setup/
    ConsoleGuide::HOOKS.each do |hook|
      assert_select "#structure td", text: /#{Regexp.escape(hook[:when])}/
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

  # The page is a manual now, so it opens with its contents. A link to a section
  # that is not on the page is a dead end.
  test "the page opens with its contents, and every section is there" do
    get docs_path

    ConsoleGuide::SECTIONS.each_with_index do |section, i|
      assert_select "nav.doc-toc a[href=?]", "##{section[:id]}", text: "#{i + 1}. #{section[:title]}"
      assert_select "##{section[:id]}"
    end
  end

  # The API reference is grouped by what a reader is looking for. Every module must
  # still be linked exactly once: a module linked twice is two entries, and one
  # linked not at all is a module that does not exist as far as the page goes.
  test "the API reference is grouped, and every module is still linked once" do
    get docs_path

    assert_select ".doc-subsystem"
    ConsoleVersion.default.library.require_paths.each do |path|
      slug = File.basename(path, ".rb")
      assert_select "a[href=?]", doc_path(slug), count: 1, message: "no link for #{slug}"
    end
  end

  # The reference is on one page, so every method of the library is on one page.
  # A reader looking for how to play a sound should not have to know which
  # module it lives in first.
  test "every method in the library is listed on the reference page" do
    get docs_path

    docs = ConsoleDocumentation.new(ConsoleVersion.default)

    docs.modules.each do |mod|
      mod.sections.flat_map(&:methods).each do |method|
        assert_select "a[href=?]", doc_path(mod.slug, anchor: mod.anchor_for(method)),
          count: 1, message: "no listing for #{mod.slug}##{method.name}"
      end
    end
  end

  # The guide's notes are written with identifiers in backticks, like the
  # library's own comments. Rendered as plain text they put a literal backtick
  # on the page around every method name in every sample.
  test "a guide note renders its identifier as code, not as a literal backtick" do
    get docs_path

    assert_select ".doc-sample p.doc code", /auto_sprite/
    assert_no_match(/`auto_sprite`/, response.body)
  end

  # The one rule about a cart that cannot be bent: the directory name is the
  # class name. It is the thing a reader has to get right before anything else
  # on the page works.
  test "the page states the rule that names a cart" do
    get docs_path

    assert_select "#start", /app\/mine\.rb/
    assert_select "#start p.doc code", /Mine/
  end

  # The console resolves a cart's class by trying the folder name, the folder
  # name camelized, and the camelized name with a Cart prefix. Saying only
  # "the folder name is the class name" would rule out a working cart.
  test "the naming rule says which class names the console accepts" do
    get docs_path

    assert_select "#start p.doc code", /CartMine/
  end

  # A reader who knows some programming but not Ruby needs the language before
  # the API, and the page is the only place that can teach it.
  test "the page teaches the language and the cart's structure" do
    get docs_path

    assert_select "#primer .doc-topic", minimum: 8
    assert_select "#structure .doc-topic", minimum: 4
    assert_select "#structure .doc-table", /setup/
  end

  # A module page has to offer a way back, and a way onward: the API index is
  # twenty modules, and arriving at one of them is not the end of the reading.
  test "a module page links back to the API index and onward to its neighbours" do
    slugs = ConsoleVersion.default.library.require_paths.map { |path| File.basename(path, ".rb") }
    index = slugs.index("sprites")

    get doc_path("sprites")

    assert_select "a[href=?]", docs_path, text: /back to the API index/
    assert_select ".doc-pager a[href=?]", doc_path(slugs[index - 1])
    assert_select ".doc-pager a[href=?]", doc_path(slugs[index + 1])
  end

  # A module page is long, and its sections are the library's own, so the way
  # into them is a list of them.
  test "a module page lists its own sections" do
    get doc_path("sprites")

    assert_select "nav.doc-nav a[href=?]", "#indexing"
    assert_select "section#indexing h2", text: "indexing"
  end

  # Two methods with the same name in one module would be two elements with the
  # same id: invalid HTML, and a link to it would jump to the first and stop
  # there. The library defines `update` twice in animation.rb and tween.rb.
  test "every method on a page has an id of its own" do
    %w[animation tween scene].each do |slug|
      get doc_path(slug)

      ids = css_select(".doc-method").map { |element| element["id"] }
      assert_equal ids.uniq, ids, "#{slug} has two methods with the same id"
    end
  end

  # An identifier in the guide's prose is written in backticks, the way the
  # library's own comments are. Rendered as plain text it puts a literal
  # backtick on the page, and the reader is left guessing whether the marks
  # are part of the name.
  test "no backtick reaches the page as text" do
    get docs_path

    assert_no_match(/`[^`<]{1,60}`/, response.body)
  end

  test "the source page offers a way back to the API index too" do
    get doc_source_path("draw")

    assert_select "a[href=?]", docs_path, text: /the API index/
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
