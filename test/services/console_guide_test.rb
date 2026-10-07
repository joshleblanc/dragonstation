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

  test "every sample has something to say and something to show" do
    @guide.samples.each do |sample|
      assert_predicate sample.title, :present?
      assert_predicate sample.note, :present?
      assert_predicate sample.code, :present?
    end
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
  test "the samples only call API that the library defines" do
    docs = ConsoleDocumentation.new(ConsoleVersion.default)
    known = docs.modules.flat_map(&:sections).flat_map(&:methods).map(&:name).to_set
    own = cart_own_names

    @guide.samples.each do |sample|
      calls_in(sample).each do |name|
        next if own.include?(name)

        assert known.include?(name),
          "#{sample.title} calls #{name}, which the library does not define"
      end
    end
  end

  # Every method a sample calls, whether or not it has a receiver.
  #
  # `draw.sprite` is one call, and `sprite` is not also a bare one; `self.assets`
  # is a definition with `self` as its receiver, so the cart's own hooks are not
  # library calls.
  def calls_in(sample)
    names = []
    walk(Ripper.sexp(sample.code)) do |node|
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

  # Names a sample defines for itself: the cart's hooks, the scene hooks the
  # loader calls, and any local method a sample introduces to keep an example
  # readable. Those are the cart's business, not the library's.
  def cart_own_names
    hooks = ConsoleGuide::HOOKS.map { |h| h[:name].split(".").last } + %w[enter leave]

    hooks + @guide.samples.flat_map { |s| s.code.scan(/^\s*def (?:self\.)?([a-z_0-9?!]+)/).flatten }
  end

  test "samples can be found by id, for linking to one directly" do
    assert_equal "scenes", @guide.find("scenes").id
    assert_nil @guide.find("no-such-sample")
  end
end
