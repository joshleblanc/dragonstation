# Ripper is stdlib but not preloaded, and nothing else in a request loads it.
require "ripper"

# The console library's documentation, read out of the library's own comments.
#
# Every module has a header and nearly every method a comment, maintained with
# the code; a hand-written copy would be wrong within a release, silently.
# Ripper gives the structure and the lexer gives the comments. Nothing is
# evaluated -- the library needs DragonRuby to run -- and a file that will not
# parse gets a page saying so rather than an exception on a public page.
class ConsoleDocumentation
  Method = Struct.new(:name, :signature, :doc, :line, keyword_init: true) do
    def documented? = doc.present?
  end

  # A group of methods under one of the library's `# --- heading ---` dividers.
  Section = Struct.new(:title, :methods, keyword_init: true)

  Module = Struct.new(:slug, :path, :module_names, :summary, :summary_doc, :sections,
                      :line_count, :error, keyword_init: true) do
    def named_modules = module_names.reject { |n| n == "Console" }

    # File names do not match module names (animation.rb defines Console::Anim).
    def name = named_modules.first || slug
  end

  # Prose, or a usage sample: the library marks samples by indenting them.
  Block = Struct.new(:type, :text, keyword_init: true) do
    def code? = type == :code
  end

  # Dividers are written `# --- title ---`, `# --- title` and `# title ----`.
  DIVIDERS = [
    /\A#\s*-{3,}\s*(.*?)\s*-{3,}\s*\z/,
    /\A#\s*-{3,}\s*(.*?)\s*\z/,
    /\A#\s*(.*?)\s*-{4,}\s*\z/
  ].freeze

  CODE_INDENT = 2

  # A trailing `\` continues a paragraph across a blank comment line.
  CONTINUED = /\\\s*\z/

  # Bump when the extraction changes: the cache outlives deploys.
  CACHE_SALT = "v1"
  CACHE_TTL = 7.days

  # A comment split into prose and code blocks. A block is code only if every
  # line is indented; one unindented line means the comment is talking again.
  def self.blocks(lines)
    groups = []

    lines.join("\n").split(/\n{2,}/).each do |chunk|
      rows = chunk.split("\n")

      if groups.last&.last&.match?(CONTINUED)
        groups.last.concat(rows)
      else
        groups << rows
      end
    end

    groups.filter_map { |rows| block(rows) }
  end

  def self.block(rows)
    rows = rows.reject { |l| l.strip.empty? }
    return nil if rows.empty?

    if rows.all? { |l| l[/\A\s*/].size >= CODE_INDENT }
      Block.new(type: :code, text: rows.map { |l| l.sub(/\A {1,#{CODE_INDENT}}/, "") }.join("\n"))
    else
      Block.new(type: :text, text: paragraph(rows))
    end
  end
  private_class_method :block

  # Hard-wrapped comment lines reflowed into one; a trailing `\` is a break.
  def self.paragraph(rows)
    rows.each_with_object([]) do |line, sentences|
      piece = line.strip
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

  attr_reader :library

  # A ConsoleVersion, or a ConsoleLibrary that is not stored (tests use this
  # for modules that could never be installed).
  def initialize(console_version_or_library)
    @library =
      if console_version_or_library.is_a?(ConsoleLibrary)
        console_version_or_library
      else
        ConsoleLibrary.new(console_version_or_library)
      end
  end

  def console_version = library.console_version

  # In require order, which is the order each module builds on the last.
  def modules
    @modules ||= library.candidate? ? build_all : cached_modules
  end

  def slugs = modules.map(&:slug)

  def find(slug) = modules.find { |m| m.slug == slug }

  private
    def build_all = library.require_paths.filter_map { |path| read(path) }

    # Parsing ~20 files plus a blob download each is what these pages cost.
    # Keyed on content_token, so a version repaired in place re-keys itself.
    def cached_modules
      Rails.cache.fetch("console-docs/#{CACHE_SALT}/#{library.content_token}", expires_in: CACHE_TTL) { build_all }
    end

    def read(path)
      source = library.read(path).dup.force_encoding(Encoding::UTF_8)
      return unparsed(path, "is not text") unless source.valid_encoding?

      sexp = Ripper.sexp(source)
      return unparsed(path, "is not valid Ruby") unless sexp

      build(path, source, sexp)
    rescue ConsoleLibrary::Missing => e
      unparsed(path, e.message)
    end

    def unparsed(path, reason)
      Module.new(slug: File.basename(path, ".rb"), path: path, module_names: [],
                 summary: nil, summary_doc: nil, sections: [], line_count: 0,
                 error: "#{path} #{reason}")
    end

    # Lines are split once and handed down: splitting per method once cost
    # 343,000 strings and most of a request's GC.
    def build(path, source, sexp)
      lines = source.lines
      comments = comments_by_line(source, lines.size)
      header = header_comment(lines, comments)

      Module.new(
        slug: File.basename(path, ".rb"),
        path: path,
        module_names: module_names(sexp),
        summary: header.map { |l| l.sub(/\A#\s?/, "").strip }.find(&:present?),
        summary_doc: header,
        sections: sections_of(lines, comments, sexp),
        line_count: lines.size
      )
    end

    # From the parse tree, classes included: about half the library is classes.
    def module_names(sexp)
      names = []
      collect_names(sexp, [], names)
      names.uniq
    end

    def collect_names(node, prefix, names)
      return unless node.is_a?(Array)

      # `class << self` is :sclass, so singleton classes never land here.
      if %i[module class].include?(node[0]) && (own = const_path(node[1])).present?
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
        right = node[2].is_a?(Array) ? const_path(node[2]) : node[2].to_s
        [ const_path(node[1]), right ].compact.join("::")
      else node[1].to_s
      end
    end

    # The comment above the first `module`: the file's description of itself.
    def header_comment(lines, comments)
      line = lines.index { |l| l =~ /^\s*module\s/ }
      line ? doc_and_dividers(lines, comments, line + 1).first : []
    end

    def sections_of(lines, comments, sexp)
      sections = []
      current = Section.new(title: nil, methods: [])

      definitions(lines, sexp).each do |definition|
        doc, dividers = doc_and_dividers(lines, comments, definition[:line])

        dividers.each do |title|
          sections << current
          current = Section.new(title: title, methods: [])
        end

        current.methods << Method.new(doc: doc, **definition)
      end

      sections << current
      sections.reject { |s| s.methods.empty? }
    end

    # [doc lines, divider titles] for the comment block above `line`. A bare
    # divider has a nil title and still starts a section.
    def doc_and_dividers(lines, comments, line)
      titles = []

      doc = raw_comment_lines(lines, comments, line).reject do |comment|
        match = DIVIDERS.lazy.filter_map { |pattern| comment.match(pattern) }.first
        titles << match[1].presence if match
        match
      end

      [ doc.map { |c| c.sub(/\A#\s?/, "").rstrip }, titles ]
    end

    # Comment lines above `line`, up to the nearest code. Blank lines are
    # walked through: the library puts one between a divider and its method.
    def raw_comment_lines(lines, comments, line)
      out = []
      index = line - 2

      while index >= 0
        text = lines[index].strip
        break unless text.empty? || text.start_with?("#")

        out.unshift(*comments[index + 1]) unless text.empty?
        index -= 1
      end

      out
    end

    # Ruby drops comments from the parse tree, so they come from the lexer.
    def comments_by_line(source, line_count)
      lines = Array.new(line_count + 1) { [] }

      Ripper.lex(source).each do |(position, type, token, _state)|
        lines[position[0]] << token.chomp if type == :on_comment
      end

      lines
    end

    def definitions(lines, sexp)
      found = []

      walk(sexp) do |node|
        next unless %i[def defs].include?(node[0])

        target = node[0] == :def ? node[1] : node[2]
        line = target[2][0] if target.is_a?(Array) && target[2].is_a?(Array) && target[2][0].is_a?(Integer)
        name =
          case target[0]
          when :@ident, :@const, :@op, :@kw then target[1].to_s
          when :call then target[3].to_s
          end
        next unless line && name

        found << { name: name, line: line, signature: signature_at(lines, line) }
      end

      found.sort_by { |d| d[:line] }
    end

    # The line as written, defaults and all, continued while parens are open.
    def signature_at(lines, line)
      out = lines[line - 1].to_s.strip
      depth = out.count("(") - out.count(")")

      while depth.positive? && line < lines.size
        line += 1
        out = "#{out} #{lines[line - 1].strip}"
        depth += lines[line - 1].count("(") - lines[line - 1].count(")")
      end

      out.sub(/[;\s]+\z/, "")
    end

    def walk(node, &block)
      return unless node.is_a?(Array)

      yield node
      node.each { |child| walk(child, &block) }
    end
end
