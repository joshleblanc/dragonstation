# Console::Str -- string helpers that avoid Regexp.
#
# mruby (the VM DragonRuby embeds) does not ship with the Regexp class, so
# none of the standard regular-expression methods are available. Everything in
# the console therefore uses these plain-string helpers instead.
module Console
  module Str
    extend self

    # Remove a trailing suffix if present: chop('.rb', 'hello.rb') -> 'hello'
    def chop(str, suffix)
      s = str.to_s
      return s unless s.end_with?(suffix)
      s[0, s.length - suffix.length]
    end

    # Split on any of the characters in `chars`.
    #
    # String#split treats its argument as a literal separator, so passing
    # '-_' would split on that exact two-character sequence rather than on
    # either character. Splits per character instead.
    def split_on(str, chars)
      out = ['']
      str.to_s.each_char do |ch|
        if chars.include? ch
          out << ''
        else
          out[out.size - 1] += ch
        end
      end
      out
    end

    # Split into lines.
    def lines(str)
      str.to_s.split "\n"
    end

    # True when every character of `str` is a decimal digit and str is not
    # empty. Replaces the /\A\d+\z/ idiom.
    def digits?(str)
      s = str.to_s
      return false if s.length == 0
      s.each_char do |ch|
        d = ch.ord - 48
        return false if d < 0 || d > 9
      end
      true
    end

    # Find the value of a quoted constant assignment, e.g.
    # title_of('TITLE = "Hello"') -> 'Hello'.
    #
    # Written with explicit length-based slicing rather than ranges, because
    # mruby's String#[] with a computed Range endpoint is not dependable.
    def quoted_value_after(str, prefix)
      s = str.to_s
      at = s.index prefix
      return nil if at.nil?
      after = after_at(s, at + prefix.length)
      eq = after.index '='
      return nil if eq.nil?
      tail = after_at(after, eq + 1)

      # Pick whichever quote style appears first.
      dq = tail.index '"'
      sq = tail.index "'"
      quote_char = nil
      quote_at = nil
      if !dq.nil? && (sq.nil? || dq < sq)
        quote_char = '"'
        quote_at = dq
      elsif !sq.nil?
        quote_char = "'"
        quote_at = sq
      end
      return nil if quote_char.nil?

      body = after_at(tail, quote_at + 1)
      stop = body.index quote_char
      return nil if stop.nil?
      body[0, stop]
    end

    # s[n, s.length - n] without Range indexing.
    def after_at(s, n)
      return '' if n >= s.length
      s[n, s.length - n]
    end

    # Drop trailing slashes: chomp_slash('carts/space/') -> 'carts/space'
    def chomp_slash(str)
      s = str.to_s
      s = s[0, s.length - 1] while s.end_with?('/') && s.length > 1
      s
    end

    # The last segment of a path: basename('carts/space') -> 'space'
    #
    # A cart's directory doubles as its name, so this is what turns a path back
    # into the module a cart is expected to define.
    def basename(str)
      chomp_slash(str).split('/').last.to_s
    end

    # Uppercase the first character: capitalize('hello') -> 'Hello'
    def capitalize(str)
      s = str.to_s
      return s if s.length == 0
      s[0, 1].upcase + s[1, s.length]
    end

    # 'hello-world' -> 'HelloWorld'
    def camel(str)
      split_on(str, '-_').map { |p| capitalize p }.join
    end

    # 'HelloWorld' -> 'hello_world'
    def snake(str)
      s = str.to_s
      out = ''
      s.each_char do |ch|
        code = ch.ord
        if code >= 65 && code <= 90
          out += '_' unless out.length == 0
          out += ch.downcase
        else
          out += ch
        end
      end
      out
    end

    # Pad/truncate to exactly `width` characters.
    def fit(str, width)
      s = str.to_s
      return s[0, width] if s.length > width
      s
    end

    def blank?(str)
      str.nil? || str.to_s.length == 0
    end
  end
end