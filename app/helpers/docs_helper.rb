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
      doc_prose(block.text)
    end
  end

  # Prose with `code` spans in it.
  #
  # The text is escaped once, here. The tags around it are the only other
  # markup in the result -- escaping the code spans a second time is how
  # `&#39;` ends up visible on the page instead of an apostrophe.
  def doc_inline(text)
    escaped = ERB::Util.html_escape(text)
    escaped.gsub(/`([^`\n]+)`/) { "<code>#{Regexp.last_match(1)}</code>" }.html_safe
  end

  # A paragraph of prose, with `code` spans.
  #
  # The guide's notes are written the way the library's comments are -- an
  # identifier in backticks -- so they are rendered the same way. Rendered as
  # plain text they would put a literal backtick on the page, around every
  # method name in every sample.
  def doc_prose(text, class_name: nil)
    tag.p(doc_inline(text), class: [ "doc", class_name ].compact.join(" "))
  end

  # A module's summary, as the index shows it.
  #
  # The index puts a module's name in one column and its summary in the next,
  # and the library's summaries open with the module's own name -- "Console::Draw
  # -- the rendering helper layer." -- which says it twice, side by side, and
  # pushes the part worth reading off the end.
  #
  # The prefix is only dropped when it is the module's own name. When the
  # library's comment names something else, that difference is worth seeing
  # rather than tidying away.
  def doc_summary(console_module)
    summary = console_module.summary.to_s
    prefix = "#{console_module.name} -- "

    summary.start_with?(prefix) ? summary.delete_prefix(prefix) : summary
  end

  # A signature, which is Ruby rather than prose.
  def signature_markup(signature)
    FileHighlighter.new("signature.rb", signature).call
  end
end
