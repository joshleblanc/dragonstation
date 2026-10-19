# Server-side syntax highlighting for the cart file reader and the docs. The
# reader arrives in a Turbo frame and works with scripting off, so colouring
# happens here; Rouge emits classed spans styled in application.css. The lexer
# comes from the file name only; an unknown name is plain text.
#
# Rouge escapes every token it emits, which is what makes html_safe sound here
# for a stranger's upload -- and a test feeds it an attack-shaped file to check.
class FileHighlighter
  # Rouge output is ~5x the source; past this, print plain and say so.
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
