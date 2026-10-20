require "test_helper"

# Rendering a doc comment.
#
# The library is vendored source rather than user input, so this is not about an
# attacker. It is about the one place markup is assembled by hand: escaping
# twice turns every apostrophe in the library's prose into a visible `&#39;`,
# which is the kind of thing that ships because nobody looked at the page.
class DocsHelperTest < ActionView::TestCase
  test "prose is escaped" do
    html = doc_inline(%q{passes "<script>alert(1)</script>" through})

    assert_includes html, "&lt;script&gt;"
    assert_not_includes html, "<script>"
  end

  test "a backtick span becomes code, escaped exactly once" do
    html = doc_inline(%q(use `:'misc/star'` here))

    # Escaped once. Twice would be &amp;#39;, and the browser would render that
    # literally as `&#39;` in the middle of the library's prose.
    assert_includes html, "<code>:&#39;misc/star&#39;</code>"
    assert_not_includes html, "&amp;#39;"
    assert_not_includes html, "&amp;quot;"
  end

  test "a span with no closing backtick is left as text" do
    html = doc_inline("an unmatched ` backtick")

    assert_not_includes html, "<code>"
  end

  test "an indented run renders as highlighted code" do
    html = doc_blocks([ "Prose.", "", "  draw.text 'READY', x: 10" ])

    assert_includes html, "<p"
    assert_includes html, "<pre"
    # Rouge's own markup: the sample is lexed, not escaped into a blob.
    assert_includes html, "<span"
    assert_includes html, "READY"
  end

  test "prose and code in one comment come out in order" do
    html = doc_blocks([ "First paragraph.", "", "  second_argument", "", "Third paragraph." ])

    assert html.index("First paragraph") < html.index("second_argument")
    assert html.index("second_argument") < html.index("Third paragraph")
  end

  # Rouge's output is the only html_safe string on this page, so it is worth
  # being explicit that the sample going in is a plain string of the file's own
  # text.
  test "a sample containing markup is escaped by the highlighter" do
    html = doc_blocks([ "  x = \"<img src=x>\"" ])

    assert_includes html, "&lt;img"
    assert_not_includes html, "<img"
  end

  test "an empty comment renders nothing" do
    assert_equal "", doc_blocks([]).strip
    assert_equal "", doc_blocks([ "", "   " ]).strip
  end

  # The index shows a module's name in one column and its summary in the next.
  # The library's summaries open with the module's own name, so the same word
  # lands in both columns and the part worth reading is squeezed out.
  test "a summary does not repeat the module's own name" do
    mod = ConsoleDocumentation::Module.new(
      slug: "draw", path: "app/console/draw.rb",
      module_names: [ "Console::Draw" ], summary: "Console::Draw -- the rendering helper layer.",
      summary_doc: [], sections: [], line_count: 1, error: nil
    )

    assert_equal "the rendering helper layer.", doc_summary(mod)
  end

  # When the library's comment names something other than the module defines,
  # the difference is worth seeing rather than tidying away: it is the library
  # that is inconsistent, not the index.
  test "a summary that names a different module keeps its prefix" do
    mod = ConsoleDocumentation::Module.new(
      slug: "animation", path: "app/console/animation.rb",
      module_names: [ "Console::Frame" ], summary: "Console::Animation -- sprite animation.",
      summary_doc: [], sections: [], line_count: 1, error: nil
    )

    assert_equal "Console::Animation -- sprite animation.", doc_summary(mod)
  end
end
