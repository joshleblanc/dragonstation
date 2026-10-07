# Marks up a file's text, so the cart file reader prints code rather than a wall
# of grey.
#
# Server-side because the reader has no JavaScript of its own: a file arrives
# inside a Turbo frame as HTML, so anything that coloured it in the browser
# would have to run again on every frame load, and would not run at all with
# scripting off. Rouge emits classed spans -- k for a keyword, s for a string,
# c1 for a comment -- and the colours live in application.css with everything
# else, so the reader looks like the rest of the site rather than like a tool
# someone pasted in.
#
# The lexer comes from the file's name and nothing else. Guessing by content
# would mean reading the whole file to decide how to read it, and a cart's
# source is not a language you can infer from 40KB of string anyway. A name
# Rouge does not know is plain text, which is a correct answer here rather than
# a failure: the file still prints.
#
# Rouge escapes every token it emits and adds only its own spans, so the result
# is safe to mark html_safe. That makes this the one html_safe string this site
# renders, and the reason the markup is built here instead of in the view: a cart
# is a stranger's upload. There is a test that feeds this a file shaped like an
# attack, so the property is checked rather than assumed.
class FileHighlighter
  # Rouge emits about five times the source in markup: at the reader's own 128KB
  # cap that is half a megabyte of HTML and a fifth of a second of lexing, on
  # every click. Big files print plain instead, and say so -- losing the colours
  # without saying why reads as a bug rather than as a decision.
  HIGHLIGHT_LIMIT = 64 * 1024

  def initialize(path, text)
    @path = path
    @text = text
  end

  def call
    return ERB::Util.html_escape(@text) unless highlighted?

    Rouge::Formatters::HTML.format(lexer.lex(@text), Rouge::Formatters::HTML.new).html_safe
  end

  def highlighted? = @text.bytesize <= HIGHLIGHT_LIMIT

  private
    def lexer = Rouge::Lexer.guess(filename: @path)
end
