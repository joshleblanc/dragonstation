# Console::Assets -- where a cart's files actually live.
#
# A cart is a directory, and it owns everything it needs:
#
#   carts/space/
#     app/space.rb        the cart itself, plus any code files beside it
#     sprites/            its own art
#     sounds/
#     maps/
#     data/
#
# A cart writes plain paths -- 'sprites/hero.png', 'maps/Level_0.ldtk' -- and
# they mean "somewhere inside my cart". The console rewrites them into real,
# game-relative paths ('carts/space/sprites/hero.png') on the way out to
# DragonRuby. Only this module has to know where the cart directory sits; the
# sprite index, audio, maps and the draw helpers just hand paths over.
#
# Resolution is cart-first, with exactly one fallback: the console's own root.
# A file inside the cart wins; a file that exists only at the console root still
# resolves, so the console can ship starter art for a brand-new cart. Each
# fallback is logged, because a published cart stages its cart directory alone
# (see ./publish-cart) and anything it borrows from the console root is missing
# from the build. A cart that owns its assets has no fallbacks.
module Console
  module Assets
    extend self

    # The logical asset directory carts keep their art in. Kept as a name
    # rather than a path: where it actually sits depends on the booted cart.
    SPRITES_DIR = 'sprites'

    class << self
      attr_reader :root, :fallbacks
    end

    @root = nil
    @fallbacks = []

    # Point the console at a cart directory. nil means "no cart is booted", and
    # every path resolves against the console root -- which is what the console
    # needs when it is not running a cart at all.
    def boot(cart_root)
      @root = cart_root.nil? || cart_root.to_s.empty? ? nil : cart_root.to_s
      @fallbacks = []
      self
    end

    def scoped?
      !@root.nil?
    end

    # The cart directory in scope, or nil.
    def cart_root
      @root
    end

    # Rewrite a cart-relative path into a real one.
    #
    # Cart copy first, then the console root, and when neither exists it returns
    # the cart-relative path anyway: that is where the file belongs, and it is
    # what a "not found" warning should name.
    def resolve(path)
      return path unless path.is_a?(String)
      return path if path.empty?
      return path if path.include? '://'
      return path if scoped_inside? path
      return path unless scoped?

      inside = "#{@root}/#{path}"
      if DR.stat_file inside
        inside
      elsif DR.stat_file path
        note_fallback path
        path
      else
        inside
      end
    end

    # True when `path` came from the console root rather than the cart. Used by
    # the tests, and by anything that wants to warn about an unowned asset.
    def shared?(path)
      @fallbacks.include? path.to_s
    end

    # Every asset this cart is borrowing from the console root.
    def shared_assets
      @fallbacks.dup
    end

    private

    # A path already pointing inside the cart is left alone, so resolving is
    # idempotent -- a path can pass through resolve twice without being nested.
    def scoped_inside?(path)
      return false unless scoped?
      path == @root || path.start_with?("#{@root}/")
    end

    def note_fallback(path)
      return if @fallbacks.include? path
      @fallbacks << path
      return unless Console.respond_to? :debug
      Console.debug "#{path} is not in the cart; resolved from the console root. " \
                    "Move it into #{@root}/ if the cart owns it."
    end
  end
end