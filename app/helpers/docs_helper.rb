# Renders the console library's documentation comments.
#
# The comments are plain text with two conventions worth honouring: `backticks`
# for an identifier, and an indented run of lines for a usage sample. Anything
# more -- lists, headings, links -- would need a markdown pipeline for comments
# that are not markdown, and a half-rendered one is worse than prose.
module DocsHelper
  # A doc comment's blocks, as markup.
  #
  # Escaped first, then decorated: the only tags in the result are the ones
  # written here, and Rouge's own from the code samples. The library is vendored
  # source rather than user input, but escaping costs nothing and means this
  # cannot become the hole if a comment ever is.
  def doc_blocks(lines)
    safe_join(
      ConsoleDocumentation.blocks(lines).map { |block| doc_block(block) }
    )
  end

  # One block of prose, or a highlighted sample.
  def doc_block(block)
    if block.code?
      tag.pre(class: "source sample") do
        raw FileHighlighter.new("sample.rb", block.text).call
      end
    else
      tag.p(doc_inline(block.text))
    end
  end

  # Prose with `code` spans in it.
  #
  # The text is escaped once, here. The tags around it are the only other
  # markup in the result -- escaping the code spans a second time is how
  # `&#39;` ends up visible on the page instead of an apostrophe.
  def doc_inline(text)
    escaped = ERB::Util.html_escape(text)
    markup = escaped.gsub(/`([^`\n]+)`/) { "<code>#{Regexp.last_match(1)}</code>" }

    tag.span(markup.html_safe, class: "doc")
  end

  # A signature, which is Ruby rather than prose.
  def signature_markup(signature)
    FileHighlighter.new("signature.rb", signature).call
  end
end
