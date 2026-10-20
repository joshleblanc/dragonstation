require "test_helper"
require "ripper"
class ConsoleGuideTest < ActiveSupport::TestCase
  setup do
    console_version!
    @guide = ConsoleGuide.new
  end

  # The failure mode of a code sample is that it stops compiling and nobody
  # notices until someone copies it. Parsing every one catches a typo here
  # rather than in a cart.
  test "every sample is valid Ruby" do
    @guide.samples.each do |sample|
      assert_not_nil Ripper.sexp(sample.code), "#{sample.title} does not parse as Ruby"
    end
  end

  # The primer and the cart structure section teach the API as much as the
  # samples do, so their code has to hold to the same rule. A primer that
  # shows Ruby that does not parse is a primer that teaches a broken language.
  test "every primer and structure example is valid Ruby" do
    (@guide.primer + @guide.structure).each do |topic|
      next if topic.code.blank?

      assert_not_nil Ripper.sexp(topic.code), "#{topic.title} does not parse as Ruby"
    end
  end

  test "every sample has something to say and something to show" do
    @guide.samples.each do |sample|
      assert_predicate sample.title, :present?
      assert_predicate sample.note, :present?
      assert_predicate sample.code, :present?
    end
  end

  # The primer is what a reader reaches for before the API, so it has to be
  # there. An empty one would leave a reader who does not know Ruby with
  # nothing between "download the console" and "here is a method list".
  test "the primer covers the language a cart is written in" do
    titles = @guide.primer.map(&:title)

    assert_operator titles.size, :>=, 8
    assert_includes titles, "Comments"
    assert_includes titles, "Values"
    assert_includes titles, "Classes"
  end

  # The cart structure section is what tells a reader what the console does
  # with their cart, which the API reference cannot: the reference documents
  # methods, not the order they run in.
  test "the cart structure section says what happens at boot and in a frame" do
    titles = @guide.structure.map(&:title)

    assert_includes titles, "What happens at boot"
    assert_includes titles, "The frame"
    assert_includes titles, "Quirks"
  end

  # A cart is one class in app/<name>.rb, so a sample that defines classes must
  # be a shape the loader would accept: every class name is a constant, and the
  # first one matches the file it would live in.
  test "the first sample defines one class named after its file" do
    code = @guide.find("first-cart").code

    assert_match(/^class Mine$/, code)
    assert_match(%r{^TITLE = 'mine'$}, code)
    refute_match(/^class [a-z]/, code)
  end

  # These are the calls a first cart is most likely to reach for, and they are
  # the ones a wrong doc page would send someone to use. A sample that invents a
  # method is worse than no sample: it reads as authoritative and fails on the
  # reader's first run.
  #
  # Read out of the parse tree rather than with a regex, because the difference
  # between `draw.sprite`, `{ ship: 'sprites/ship.png' }` and `music :theme` is
  # exactly what a regex gets wrong.
  test "every example only calls API that the library defines" do
    docs = ConsoleDocumentation.new(ConsoleVersion.default)
    known = docs.modules.flat_map(&:sections).flat_map(&:methods).map(&:name).to_set
    own = cart_own_names

    examples.each do |title, code|
      calls_in(code).each do |name|
        next if own.include?(name)

        assert known.include?(name),
          "#{title} calls #{name}, which the library does not define"
      end
    end
  end

  # Every titled piece of code the guide shows.
  def examples
    samples = @guide.samples.map { |sample| [ sample.title, sample.code ] }
    topics = (@guide.primer + @guide.structure).filter_map do |topic|
      [ topic.title, topic.code ] if topic.code.present?
    end

    samples + topics
  end

  # Methods from Ruby's own library, which the examples use and the console
  # does not define. They are here because the test above is about the
  # console's API, not about Ruby's.
  RUBY_CORE = %w[each times key? merge <<].freeze

  # Every method an example calls, whether or not it has a receiver.
  #
  # `draw.sprite` is one call, and `sprite` is not also a bare one; `self.assets`
  # is a definition with `self` as its receiver, so the cart's own hooks are not
  # library calls.
  def calls_in(code)
    names = []
    walk(Ripper.sexp(code)) do |node|
      case node[0]
      # `music(:theme)`
      when :fcall
        names << identifier(node[1])
      # `music :theme` -- no parentheses, so Ripper calls it a command. The
      # library's API is written this way more often than not.
      when :command
        names << identifier(node[1])
        names << identifier(node[3]) if period?(node[2])
      # `input.held?(:right)`
      when :call
        names << identifier(node[1]) if node[1].nil?
        names << identifier(node[1]) unless node[1].nil?
        names << identifier(node[3]) if period?(node[2])
      end
    end
    names.compact.uniq
  end

  def period?(node) = node.is_a?(Array) && node[0] == :@period

  def walk(node, &block)
    return unless node.is_a?(Array)

    yield node
    node.each { |child| walk(child, &block) }
  end

  def identifier(node)
    return unless node.is_a?(Array)

    case node[0]
    when :@ident, :@const then node[1]
    # `draw.sprite` names its receiver through a var_ref, and `self.assets`
    # arrives as :@kw -- which is why self is not collected here: it is not a
    # call on anything.
    when :var_ref, :const_ref, :top_const_ref then identifier(node[1])
    end
  end

  # Names an example defines for itself: the cart's hooks, the scene hooks the
  # loader calls, and any local method an example introduces to keep itself
  # readable. Those are the cart's business, not the library's.
  def cart_own_names
    hooks = ConsoleGuide::HOOKS.map { |h| h[:name].split(".").last } + %w[enter leave]
    defined = examples.flat_map { |_, code| code.scan(/^\s*def (?:self\.)?([a-z_0-9?!]+)/).flatten }

    hooks + defined + RUBY_CORE
  end

  test "samples can be found by id, for linking to one directly" do
    assert_equal "scenes", @guide.find("scenes").id
    assert_nil @guide.find("no-such-sample")
  end

  # The API index is grouped so a reader can find the module they want. A
  # module in no group would simply not be on the page, which is worse than a
  # flat list: a reader would not know it was missing.
  test "every module lands in exactly one group" do
    modules = ConsoleDocumentation.new(ConsoleVersion.default).modules
    grouped = @guide.groups(modules).flat_map { |group| group[:modules] }

    assert_equal modules.map(&:slug).sort, grouped.map(&:slug).sort
    assert_equal grouped.map(&:slug).uniq, grouped.map(&:slug)
  end

  # A module the grouping does not name must still be on the page: it lands in
  # the catch-all rather than vanishing, because a reader would have no way to
  # know it was missing.
  test "a module the grouping does not name is kept, not dropped" do
    stray = ConsoleDocumentation::Module.new(
      slug: "brand_new", path: "app/console/brand_new.rb",
      module_names: [ "Console::BrandNew" ], summary: "Something new.",
      summary_doc: [], sections: [], line_count: 1, error: nil
    )

    groups = @guide.groups([ stray ])

    assert_equal 1, groups.size
    assert_equal "Other", groups.first[:title]
    assert_equal [ "brand_new" ], groups.first[:modules].map(&:slug)
  end

  # A sample that says what to write but not where to write it leaves the one
  # thing a reader cannot guess.
  test "every sample says which file it goes in" do
    @guide.samples.each do |sample|
      assert_predicate sample.file, :present?
      assert_predicate sample.verb, :present?
    end
  end

  # A scene author needs to know the scene hooks exist. The table stopped at
  # `render`, so `enter` -- the hook a scene is written around -- was only
  # discoverable by reading a sample.
  test "the hooks table includes the scene hooks" do
    names = @guide.hooks.map { |hook| hook[:name] }

    assert_includes names, "enter"
    assert_includes names, "leave"
  end
end
