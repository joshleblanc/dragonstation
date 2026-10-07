# The console library's documentation, read out of the library itself.
#
# A cart author needs to know what the library offers, and the honest answer is
# already written down: every module carries a header explaining what it is for,
# and nearly every method carries a comment saying what it does and why. Those
# comments are maintained alongside the code, by whoever changed it last. A
# hand-written copy of the same thing would be a second source of truth that is
# wrong within a release -- and the failure would be silent, because stale docs
# still read as docs.
#
# So this reads the comments instead of writing them. Ripper gives the structure
# (which module, which method, where) and the lexer gives the comments, which
# Ruby does not keep in the parse tree. Nothing is evaluated: the library cannot
# run here -- it needs DragonRuby's DR and $args -- and docs must not depend on
# being able to run the thing being documented.
#
# A file that will not parse yields a page with an explanation rather than an
# exception. These pages are public and vendored source is data, not something
# this class gets to be precious about.
#
# Ripper is stdlib but not preloaded, and nothing else in a request would load
# it -- so it is required here rather than discovered missing in production.
require "ripper"

class ConsoleDocumentation
  # One method, with the comment written above it.
  Method = Struct.new(:name, :signature, :doc, :line, keyword_init: true) do
    # True when the method says anything. A fair number are one-liners whose
    # name is the documentation, and rendering an empty paragraph for each of
    # them buries the ones that are not.
    def documented? = doc.present?
  end

  # The `# --- heading ---` dividers the library uses to group its own methods.
  Section = Struct.new(:title, :methods, keyword_init: true) do
    def documented_methods = methods.select(&:documented?)
  end

  # One library file: the module(s) it defines, and everything in them.
  Module = Struct.new(:slug, :path, :module_names, :summary, :summary_doc, :sections,
                      :line_count, :error, keyword_init: true) do
    # Everything the file defines under the Console namespace.
    def named_modules = module_names.reject { |n| n == "Console" }

    # What to call this page. The library's own naming does not match its file
    # names (animation.rb defines Console::Anim), so the module wins where
    # there is one and the file name is the fallback.
    def name = named_modules.first || slug

    def documented_methods = sections.flat_map(&:documented_methods)
  end

  # The library groups its own methods with dashed rules, and it writes them two
  # ways: `# --- indexing ---` and `# 8-bit helpers ---`. Both are dividers; a
  # rule that opens and closes is only decorative, so the title is whatever sits
  # between the dashes.
  CLOSED_DIVIDER = /\A#\s*-{3,}\s*(.*?)\s*-{3,}\s*\z/
  OPEN_DIVIDER = /\A#\s*-{3,}\s*(.*?)\s*\z/
  TRAILING_DIVIDER = /\A#\s*(.*?)\s*-{4,}\s*\z/

  # A comment block stops at the first line that is neither a comment nor blank;
  # a blank line inside a block is a `#` line, so it is part of the paragraph
  # break rather than the end of the comment.
  # One run of a doc comment: prose, or a usage sample.
  #
  # The library writes samples as an indented run of comment lines inside an
  # otherwise plain-text comment -- see the header of draw.rb -- so the
  # indentation is the markup, and a renderer that treated every comment as
  # prose would run `draw.within(panel_rect) do` into the paragraph above it.
  Block = Struct.new(:type, :text, keyword_init: true) do
    def code? = type == :code
  end

  # Indented at least this far, after the `# ` has been stripped.
  CODE_INDENT = 2

  # A blank comment line separates blocks. It does not have to *be* a blank
  # line: the library writes a continued paragraph with a trailing `\` to show
  # it is one, and splitting there would cut a sentence in half.
  CONTINUED = /\\\s*\z/

  # A comment split into prose and code runs.
  #
  # A block is code only if *every* line is indented: one unindented line in the
  # middle of an example is how a comment continues talking about it, and that
  # line is prose.
  def self.blocks(lines)
    groups = []

    lines.join("\n").split(/\n{2,}/).each do |chunk|
      rows = chunk.split("\n")

      # A trailing `\` says the paragraph continues, so the next chunk belongs
      # to this one rather than starting a new block.
      if groups.last && groups.last.last.match?(CONTINUED)
        groups.last.concat(rows)
      else
        groups << rows
      end
    end

    groups.filter_map { |chunk| block(chunk) }
  end

  def self.block(rows)
    rows = Array(rows).flatten.reject { |l| l.to_s.strip.empty? }
    return nil if rows.empty?

    if rows.all? { |l| l[/\A\s*/].size >= CODE_INDENT }
      Block.new(type: :code, text: rows.map { |l| l.sub(/\A {1,#{CODE_INDENT}}/, "") }.join("\n"))
    else
      Block.new(type: :text, text: paragraph(rows))
    end
  end

  # Prose is reflowed into one line: a comment is hard-wrapped, and keeping
  # those wraps would make every paragraph carry its own indentation into the
  # page. A trailing `\` says the sentence continues, so that line joins the
  # next rather than becoming a break.
  def self.paragraph(rows)
    rows.each_with_object([]) do |line, sentences|
      piece = line.to_s.strip
      continued = piece.match?(CONTINUED)
      piece = piece.sub(CONTINUED, "").rstrip

      if sentences.last
        sentences.last << " " unless sentences.last.empty?
        sentences.last << piece
      else
        sentences << piece.dup
      end

      sentences << +"" if continued
    end.reject(&:empty?).join(" ")
  end
  private_class_method :block

  attr_reader :library

  # Takes a ConsoleVersion, or a ConsoleLibrary for a library that is not stored
  # -- which is how the tests read a module that would not parse, since such a
  # module can never be installed.
  def initialize(console_version_or_library)
    @library =
      if console_version_or_library.is_a?(ConsoleLibrary)
        console_version_or_library
      else
        ConsoleLibrary.new(console_version_or_library)
      end
  end

  def console_version = library.console_version

  # Every module, in the order app/main.rb requires them. That order is
  # load-bearing to the library, so it is the order a reader should meet them
  # in too: each module mostly builds on the ones above it.
  def modules
    @modules ||= library.require_paths.filter_map { |path| read(path) }
  end

  def slugs = modules.map(&:slug)

  def find(slug) = modules.find { |m| m.slug == slug }

  private
    def read(path)
      source = library.read(path).dup.force_encoding(Encoding::UTF_8)

      # A file that will not parse, or that is not text at all, still gets a
      # page: one that says why. These pages are public and this is vendored
      # source, so an exception here would take the whole site down over a file
      # nobody can read.
      return unparsed(path, "is not valid Ruby") unless Ripper.sexp(source)
      return unparsed(path, "is not text") unless source.valid_encoding?

      build(path, source)
    rescue ConsoleLibrary::Missing => e
      unparsed(path, e.message)
    end

    def unparsed(path, reason)
      Module.new(slug: File.basename(path, ".rb"), path: path, module_names: [],
                 summary: nil, summary_doc: nil, sections: [], line_count: 0,
                 error: "#{path} #{reason}")
    end

    def build(path, source)
      comments = comments_by_line(source)
      names = module_names(source)
      header = header_comment(source, comments)

      Module.new(
        slug: File.basename(path, ".rb"),
        path: path,
        module_names: names,
        summary: summary_of(header),
        summary_doc: header,
        sections: sections_of(source, comments),
        line_count: source.lines.size
      )
    end

    # Module paths, from the parse tree rather than the file name: the library
    # does not always agree with itself here -- animation.rb defines
    # Console::Anim, ui.rb defines Console::UI -- and a page titled with a name
    # that does not exist in the code is worse than no page.
    #
    # Classes count as well as modules. Roughly half the library is a class
    # (Console::Draw, Console::Input), and reading only `module` would leave
    # those pages claiming to define nothing at all.
    def module_names(source)
      sexp = Ripper.sexp(source)
      return [] unless sexp

      names = []
      collect_names(sexp, [], names)
      names.uniq
    end

    def collect_names(node, prefix, names)
      return unless node.is_a?(Array)

      case node[0]
      when :module, :class
        # `class << self` is an :sclass node, not a :class, so singleton
        # classes never reach here as a definition of their own.
        own = const_path(node[1])
        return if own.blank?

        path = prefix + [ own ]
        names << path.join("::")
        node.each { |child| collect_names(child, path, names) }
      else
        node.each { |child| collect_names(child, prefix, names) }
      end
    end

    def const_path(node)
      case node[0]
      when :@const, :@ident then node[1].to_s
      when :var_ref, :top_const_ref, :const_ref then const_path(node[1])
      when :colon2
        left = const_path(node[1])
        right = node[2].is_a?(Array) ? const_path(node[2]) : node[2].to_s
        [ left, right ].compact.join("::")
      else node[1].to_s
      end
    end

    # The comment block above the first `module` keyword: the file's own
    # description of itself.
    def header_comment(source, comments)
      line = source.lines.index { |l| l =~ /^\s*module\s/ }
      return [] unless line

      doc_for(source, comments, line + 1)
    end

    def summary_of(header)
      header.map { |l| l.sub(/\A#\s?/, "").strip }.find(&:present?)
    end

    # Methods, in file order, grouped by the library's own dividers.
    def sections_of(source, comments)
      sections = []
      current = Section.new(title: nil, methods: [])

      definitions(source).each do |definition|
        doc, dividers = doc_and_dividers(source, comments, definition[:line])

        dividers.each do |title|
          sections << current
          current = Section.new(title: title, methods: [])
        end

        current.methods << Method.new(
          name: definition[:name],
          signature: definition[:signature],
          doc: doc,
          line: definition[:line]
        )
      end

      sections << current
      sections.reject { |s| s.methods.empty? }
    end

    # Comments immediately above a line, split into the parts that document it
    # and the ones that announce the section it belongs to.
    def doc_and_dividers(source, comments, line)
      block = raw_comment_lines(source, comments, line)
      titles = []

      doc = block.reject do |comment|
        divider, title = divider_title(comment)
        next false unless divider

        titles << title
        true
      end

      [ doc.map { |c| c.sub(/\A#\s?/, "").rstrip }, titles ]
    end

    # A divider's title, or nil when the comment is not one. An empty title is
    # a real thing here -- the library uses a bare rule to separate two blocks
    # of the same section -- so the answer is an array rather than a string:
    # [true, nil] for a divider with no name, [false, nil] for prose.
    def divider_title(comment)
      [ CLOSED_DIVIDER, OPEN_DIVIDER, TRAILING_DIVIDER ].each do |pattern|
        next unless (match = comment.match(pattern))

        return [ true, match[1].presence ]
      end

      [ false, nil ]
    end

    def doc_for(source, comments, line) = doc_and_dividers(source, comments, line).first

    # Every comment line above `line`, up to the nearest code line. Blank lines
    # are walked through rather than stopping the scan: the library puts a blank
    # line between a section divider and the method it introduces, and treating
    # that as the end of the comment would lose every documented method.
    def raw_comment_lines(source, comments, line)
      lines = source.lines
      out = []

      index = line - 2
      while index >= 0
        text = lines[index].to_s

        if text.strip.empty?
          index -= 1
          next
        end

        break unless text.strip.start_with?("#")

        out.unshift(*(comments[index + 1] || []))
        index -= 1
      end

      out
    end

    def comments_by_line(source)
      lines = Array.new(source.lines.size + 1) { [] }

      Ripper.lex(source).each do |(position, type, token, _state)|
        lines[position[0]] << token.chomp if type == :on_comment
      end

      lines
    end

    # Definitions with their signature read straight off the source.
    def definitions(source)
      sexp = Ripper.sexp(source)
      return [] unless sexp

      found = []

      walk(sexp) do |node|
        line = definition_line(node)
        next unless line

        name = definition_name(node)
        next unless name

        found << { name: name, line: line, signature: signature_at(source, line) }
      end

      found.sort_by { |d| d[:line] }
    end

    def definition_line(node)
      case node[0]
      when :def then constant_line(node[1])
      when :defs then constant_line(node[2])
      end
    end

    def definition_name(node)
      target = node[0] == :def ? node[1] : node[2]

      case target[0]
      when :@ident, :@const, :@op, :@kw then target[1].to_s
      when :call then target[3].to_s
      end
    end

    def constant_line(node)
      node[2][0] if node.is_a?(Array) && node[2].is_a?(Array) && node[2][0].is_a?(Integer)
    end

    # `def draw.sprite(path:, x:, y:)` and friends. Read from the source rather
    # than rebuilt from the parse tree: what a reader needs is the line as
    # written, including its default arguments.
    def signature_at(source, line)
      lines = source.lines
      out = lines[line - 1].to_s.strip

      depth = out.count("(") - out.count(")")
      following = line
      while depth.positive? && following < lines.size
        following += 1
        out = "#{out} #{lines[following - 1].strip}"
        depth += lines[following - 1].count("(") - lines[following - 1].count(")")
      end

      out.sub(/[;\s]+\z/, "")
    end

    # Every node in the tree, so a definition nested three modules deep is found
    # the same way as one at the top.
    def walk(node, &block)
      return unless node.is_a?(Array)

      yield node
      node.each { |child| walk(child, &block) }
    end
end
