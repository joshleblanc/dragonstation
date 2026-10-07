# Console -- the cartridge runtime.
#
# This is the object a cart talks to. `Console.boot` is called once by
# app/main.rb, `Console.tick` runs 60x a second, and in between it owns:
#
#   draw      Console::Draw      rendering helpers
#   input     Console::Input     one action vocabulary
#   ui        Console::UI        widgets
#   entities  Console::EntityStore
#   anim      Console::Anim      animation state machines
#   audio     Console::Audio     sfx + music
#   camera    Console::Camera    world/screen transform
#   tweens    Console::TweenHost tweens, `after`, `every`
#   scenes    Console::SceneController
#
# Frame order is fixed and worth knowing:
#
#   1. input snapshot          so a whole frame sees one consistent input state
#   2. timers / tickers / tweens
#   3. animations advance
#   4. scene update + scene draw   (or, with no scenes, cart update)
#   5. cart render (always last, so it is the place for a HUD)
#   6. HUD / warnings
#
module Console
  VERSION = '0.1.0'

  class << self
    attr_reader :args, :draw, :input, :ui, :entities, :anim, :audio
    attr_reader :camera, :tweens, :scenes, :cart, :cart_name
    attr_accessor :show_hud, :ui_store, :screen, :warnings, :test_mode
    attr_accessor :quit_after, :shot_path, :shot_at
    attr_reader :booted_at
  end

  @show_hud = false
  @ui_store = {}
  @screen = { w: 1280, h: 720 }
  @warnings = []
  @test_mode = false
  @shot_path = nil
  @shot_at = nil

  # --- lifecycle --------------------------------------------------------

  # Called by app/main.rb exactly once, after every library file is required.
  #
  # `cart` is the module implementing the cart contract (see Console::API).
  def self.boot(args, cart, cart_name = nil)
    @args = args
    @booted_at = Kernel.tick_count
    @cart_name = cart_name || 'cart'

    # Give the cart the console's API as bare method calls. Extending the
    # instance (rather than including into its class) keeps the API scoped to
    # the cart that asked for it.
    @cart = cart
    @cart.extend Console::API unless @cart.respond_to?(:spawn)
    @booted = false

    @screen = { w: args.grid.w, h: args.grid.h }
    @ui_store = {}
    @warnings = []

    @entities = EntityStore.new
    @tweens = TweenHost.new
    @scenes = SceneController.new args
    @anim = Anim.new args
    @audio = Audio.new args
    @camera = Camera.new args
    @draw = Draw.new args
    @draw.camera = @camera
    @ui = UI.new self
    @input = Input.new args

    args.outputs.background_color = Palette.to_a(:dark)

    Sprites.index!

    register_cart_assets

    # Take one input snapshot now, so a cart's `setup` can read the pointer
    # and action state without waiting for the first frame.
    @input.refresh

    @booted = true

    cart.setup if cart.respond_to?(:setup)
    scenes.goto scenes.defs.keys.first if cart_uses_scenes?

    debug "console #{VERSION} booted with cart #{@cart_name}"
    self
  end

  def self.booted?
    @booted ? true : false
  end

  # Let a cart declare its assets in one place.
  #
  #   def self.assets
  #     { sprites: { hero: 'sprites/hero.png' },
  #       sounds:  { jump: 'sounds/jump.wav' },
  #       music:   { title: 'sounds/title.ogg' } }
  #   end
  #
  # Every path is relative to the cart's own directory, so the example above is
  # 'carts/space/sprites/hero.png' for a cart at carts/space -- see
  # Console::Assets. Nothing here needs the cart's name to be hardcoded.
  #
  # A single `assets` method rather than three, because names like `sfx` and
  # `music` are already taken by the playback API and a cart that declared
  # `def self.sfx` would silently shadow `sfx(:jump)`.
  def self.register_cart_assets
    # Declarations are normally class-level (`def self.assets`), while the hooks
    # are instance-level, so look in both places.
    owner = @cart.respond_to?(:assets) ? @cart : @cart.class
    if owner.respond_to?(:assets)
      assets = owner.assets || {}
      assets[:sprites]&.each { |name, path| Sprites.register name, path }
      assets[:sounds]&.each { |name, path| audio.register name, path }
      assets[:music]&.each { |name, path| audio.register "music_#{name}", path }
    end
    if owner.respond_to?(:sprite_library)
      owner.sprite_library.each { |name, path| Sprites.register name, path }
    end
    if owner.respond_to?(:sound_library)
      owner.sound_library.each { |name, path| audio.register name, path }
    end
  end

  def self.tick(args)
    return unless @booted
    @args = args
    @screen = { w: args.grid.w, h: args.grid.h }

    tick_count = Kernel.tick_count

    # 1. input snapshot
    input.refresh

    # debug overlay toggle
    if input.pressed?(:debug_toggle)
      @show_hud = !@show_hud
    end

    # 2. scheduled work
    tweens.update

    # 3. animations
    anim.update

        # 4. gameplay + scene draw
    if cart_uses_scenes?
      scenes.run true
    else
      cart.update if cart.respond_to?(:update)
      draw_background
      cart.render if cart.respond_to?(:render)
    end

    # 5. cart overlay (HUD) always runs last
    if cart_uses_scenes? && cart.respond_to?(:render)
      cart.render
    end

    # 6. diagnostics
    ui.hud if @show_hud
    draw_warnings

    handle_shot(tick_count)
    handle_quit(tick_count)
  end

  def self.draw_background(color = :dark)
    args.outputs.background_color = Palette.to_a(color)
  end

  # --- helpers used by the API mixin ------------------------------------

  # Top-of-screen layout helpers, also reachable as bare calls in a cart.
  def self.strip(top_y, h, width = nil)
    Geom.strip top_y, h, width
  end

  def self.top(y)
    Geom.top y
  end

  def self.screen_rect
    Geom.screen_rect args.grid
  end

  def self.cart_uses_scenes?
    scenes.names.size > 0
  end

  # Jump to a scene from outside a cart (the --scene switch).
  def self.goto_scene(name)
    if scenes.defined?(name)
      scenes.goto name
      debug "jumped to scene #{name}"
      true
    else
      warn "no scene named #{name} (have: #{scenes.names.join(', ')})"
      false
    end
  end

  def self.kind_counts
    out = {}
    entities.entities.each do |e|
      k = e[:kind] || :entity
      out[k] = (out[k] || 0) + 1
    end
    out
  end

  # Log a message. Nothing on screen -- use this for normal chatter.
  def self.debug(message)
    puts "[console] #{message}"
    message
  end

  # Log a message AND surface it on screen for a few seconds.
  #
  # On-screen is reserved for things a cart author needs to notice without
  # watching a terminal, like a sprite name that does not resolve.
  # How long an on-screen warning stays up. Long enough to notice while
  # playing, short enough that a fixed warning does not cover the game forever.
  WARNING_TICKS = 420

  def self.warn(message)
    debug message
    @warnings << { text: message, until_tick: Kernel.tick_count + WARNING_TICKS }
    @warnings = @warnings.last(6)
    message
  end

  def self.warn_sprite(name)
    warn "sprite not found: #{name} (using a placeholder)"
  end

  def self.draw_warnings
    return if @warnings.size == 0
    now = Kernel.tick_count
    @warnings = @warnings.select { |w| w[:until_tick] > now }
    return if @warnings.size == 0
    @warnings.each_with_index do |w, i|
      draw.text w[:text],
                x: 10,
                y: @screen[:h] - 10 - (i * 18),
                size_enum: -3,
                color: Palette::COLORS[:warn]
    end
  end

  # --- assets ------------------------------------------------------------

  # The booted cart's own directory ('carts/space'), or nil when no cart is
  # booted.
  def self.assets_root
    Assets.root
  end

  # Turn a cart-relative path into a real one:
  #
  #   asset 'sprites/hero.png'   # => 'carts/space/sprites/hero.png'
  #   asset 'data/level.json'    # => 'carts/space/data/level.json'
  #
  # The console resolves sprites, sounds, music, animation frames and maps on
  # its own; use this for anything else it does not know about, such as
  # DR.read_file on a JSON or CSV in your own data/ directory.
  def self.asset(path)
    Assets.resolve path
  end

  # Assets this cart is borrowing from the console root rather than owning.
  #
  # A published cart stages its own directory alone, so an empty list is what a
  # cart wants: every entry is a file that will be missing from the build until
  # it moves into the cart.
  def self.shared_assets
    Assets.shared_assets
  end

  # Resolve a sprite name to a renderable path.
  def self.sprite(name)
    resolved = Sprites.path name
    warn_sprite name if resolved == :solid && !Sprites.exists?(name)
    resolved
  end

  # Resolve or synthesise a sprite, so a cart can run before art exists.
  def self.auto_sprite(name, w = 16, h = 16, color = :accent, pattern = :solid)
    Sprites.auto args, name, w, h, color, pattern
  end

  # --- headless helpers --------------------------------------------------

  # Request a screenshot at `at_tick`, written into the game directory.
  def self.screenshot(path, at_tick = nil)
    @shot_path = path
    @shot_at = at_tick || Kernel.tick_count
  end

  def self.handle_shot(tick_count)
    return unless @shot_path
    return unless tick_count == @shot_at
    # The capture region is explicit: DragonRuby expects x/y/w/h (and an
    # alpha) alongside the path, and silently does nothing without them.
    grid = args.grid
    args.outputs.screenshots << { x: 0, y: 0, w: grid.w, h: grid.h,
                                  path: @shot_path, a: 255 }
    @shot_path = nil
  end

  def self.quit_after=(ticks)
    @quit_after = ticks
  end

  def self.handle_quit(tick_count)
    return unless @quit_after
    if tick_count >= @quit_after
      DR.request_quit
    end
  end
end

# Console::API -- the entire surface a cart is expected to touch.
#
# This module is extended into the cart module, so every method below is
# callable without a receiver from anywhere in a cart. It also includes cleanly
# into scene classes, because every method delegates to the Console singleton.
#
# The methods are deliberately few. Anything that is not here is a DragonRuby
# primitive you can still reach through `args`.
module Console
  module API
    # --- scenes ----------------------------------------------------------

    # scene :title, TitleScene      register a scene
    # scene :title                  go to a scene
    def scene(name = nil, klass = nil, options = {})
      if klass.nil? && options.size == 0
        Console.scenes.goto name
      else
        Console.scenes.define name, klass, options
      end
    end

    def goto(name)
      Console.scenes.goto name
    end

    def push_scene(name)
      Console.scenes.push name
    end

    def pop_scene
      Console.scenes.pop
    end

    def unwind
      Console.scenes.unwind
    end

    def current_scene
      Console.scenes.current_name
    end

    def scene_depth
      Console.scenes.depth
    end

    # Per-scene persistent state.
    def scene_data(name = nil)
      Console.scenes.store(name || Console.scenes.current_name)
    end

    # --- subsystems -------------------------------------------------------

    def draw
      Console.draw
    end

    def input
      Console.input
    end

    def ui
      Console.ui
    end

    def entities
      Console.entities
    end

    def anim
      Console.anim
    end

    def audio
      Console.audio
    end

    def camera
      Console.camera
    end

    def tweens
      Console.tweens
    end

    def args
      Console.args
    end

    def screen
      Console.screen
    end

    # --- geometry --------------------------------------------------------
    #
    # The handful of rect maths a cart actually reaches for. Anything more
    # specific is Console::Geom, but these are the ones you would otherwise
    # write by hand every time.

    def rect(x, y, w, h)
      Console::Geom.rect x, y, w, h
    end

    # The geometric centre of a rect.
    def center(r)
      Console::Geom.center r
    end

    # Do two rects overlap?
    def overlaps?(a, b, tolerance = 0.1)
      a.intersect_rect? b, tolerance
    end

    # Is a point inside a rect?
    def inside?(r, x, y)
      Console::Geom.contains? r, x, y
    end

    # value as a 0.0..1.0 fraction of max (0 when max is zero or less).
    def percent(value, max)
      Console::Geom.perc value, max
    end

    # Keep a rect inside bounds without resizing it.
    def clamp_inside(r, bounds)
      Console::Geom.clamp_inside r, bounds
    end

    # Split a rect into `count` columns with `gap` between them.
    def columns(r, count, gap = 0)
      Console::Geom.columns r, count, gap
    end

    # Shrink a rect by `amount` on all sides.
    def inset(r, amount)
      Console::Geom.inset r, amount
    end

    # The whole screen as a rect.
    def screen_rect
      Console::Geom.screen_rect args.grid
    end

    # Persistent key/value store the UI widgets use for their own state
    # (checkbox values, slider positions, menu selection).
    def ui_store
      Console.ui_store
    end

    # --- entities ---------------------------------------------------------

    def spawn(klass = nil, attributes = {})
      Console.entities.spawn klass, attributes
    end

    def despawn(entity)
      Console.entities.despawn entity
    end

    def despawn_if(&block)
      Console.entities.despawn_if(&block)
    end

    def each_entity(kind = nil, &block)
      Console.entities.each(kind, &block)
    end

    def entities_of(kind)
      Console.entities.all kind
    end

    def entity_count(kind = nil)
      Console.entities.count kind
    end

    def colliding(rect, kind = nil)
      Console.entities.colliding rect, kind
    end

    def move(entity, options = {})
      Console.entities.move entity, options
    end

    # --- animation --------------------------------------------------------

    # animate(entity, :run)
    # animate(entity, :run, sheet: 'hero.png', frame_w: 16, frame_h: 20, frames: 6)
    def animate(entity, name, options = {})
      Console.anim.play entity, name, options
    end

    def animating?(entity, name = nil)
      name.nil? ? Console.anim.active?(entity[:id]) : Console.anim.playing?(entity[:id], name)
    end

    def anim_done?(entity)
      Console.anim.finished? entity[:id]
    end

    def stop_anim(entity)
      Console.anim.stop entity[:id]
    end

    def anim_state(entity)
      Console.anim.name_of entity[:id]
    end

    # Draw an entity, resolving its active animation, tint and flips.
    def draw_entity(entity, spec = {})
      Console::EntityDraw.draw_entity Console, entity, spec
    end

    # --- tweens and scheduling -------------------------------------------

    def tween(target, property, options = {})
      Console.tweens.tween target, property, options
    end

    def tween_all(target, properties, options = {})
      Console.tweens.tween_all target, properties, options
    end

    def after(ticks, &block)
      Console.tweens.after ticks, &block
    end

    def every(ticks, options = {}, &block)
      Console.tweens.every ticks, options, &block
    end

    def next_tick(&block)
      Console.tweens.next_tick(&block)
    end

    # --- audio -----------------------------------------------------------

    def sfx(name, options = {})
      Console.audio.sfx name, options
    end

    def music(name, options = {})
      Console.audio.music name, options
    end

    def stop_music
      Console.audio.stop_music
    end

    def music_gain(value = nil)
      Console.audio.music_gain value
    end

    def mute
      Console.audio.mute
    end

    def unmute
      Console.audio.unmute
    end

    def toggle_mute
      Console.audio.toggle_mute
    end

    # --- assets -----------------------------------------------------------

    # This cart's own directory, e.g. 'carts/space'. nil outside a cart.
    def assets_root
      Console.assets_root
    end

    # Resolve a cart-relative path to a real one:
    #
    #   asset 'data/level.json'    # => 'carts/space/data/level.json'
    def asset(path)
      Console.asset path
    end

    # Assets this cart is borrowing from the console root. Empty is the goal:
    # a published cart ships its own directory alone.
    def shared_assets
      Console.shared_assets
    end

    # --- sprites ---------------------------------------------------------

    # Resolve a sprite name to a path. Warns (visibly) if it is missing.
    def sprite(name)
      Console.sprite name
    end

    # Resolve a sprite name, generating a placeholder texture if needed.
    def auto_sprite(name, w = 16, h = 16, color = :accent, pattern = :solid)
      Console.auto_sprite name, w, h, color, pattern
    end

    # Draw a sprite in one call.
    def draw_sprite(name, options = {})
      Console.draw.sprite options.merge(path: Console.sprite(name))
    end

    # The screen background colour. Call once per frame if it changes.
    def background(color = :dark)
      Console.draw_background color
    end

    # --- layout ----------------------------------------------------------

    # DragonRuby measures y from the bottom. For UI, thinking from the top is
    # far more natural, so these wrap the same numbers:
    #
    #   draw.within ui.strip(0, 40) do ... end     # a 40px bar across the top
    #
    # `top(y)` converts "y pixels down from the top" into the bottom-left
    # origin, for when you want to place one item by hand. (DragonRuby also
    # ships `Numeric#from_top`, e.g. `y: 30.from_top`, which does the same
    # thing inline.)
    def strip(top_y, h, width = nil)
      Console::Geom.strip top_y, h, width
    end

    def row_at(top_y, index, width, line_h, gap = 0)
      Console::Geom.row_from_top top_y, index, width, line_h, gap
    end

    def top(y)
      Console::Geom.top y
    end

    # --- levels -----------------------------------------------------------

    # Load an LDTK level. Returns nil (with an on-screen warning) if the file
    # is missing, so a bad level path is visible rather than a boot crash.
    #
    #   map = load_map 'maps/Level_0.ldtk'
    #   map.spawn_all
    #   @body = body entity: @ship, gravity: 0.4
    def load_map(path, options = {})
      Console::Map.load path, options
    end

    # Spawn every entity from a loaded level into the entity store.
    def spawn_level(map, extra = {})
      map.spawn_all extra
    end

    # --- bodies -----------------------------------------------------------

    # A kinematic platformer body. Takes one options hash -- see the note on
    # Console::Body about why a positional list would not survive mruby.
    def body(options = {})
      Console::Body.new options
    end

    # --- misc ------------------------------------------------------------

    def on_enter(name, &block)
      Console.scenes.on_enter name, &block
    end

    def on_leave(name, &block)
      Console.scenes.on_leave name, &block
    end

    def debug(message)
      Console.debug message
    end

    def warn(message)
      Console.warn message
    end

    # Typed characters arrive via `input.typed` after enabling collection.
    def start_text_input
      Console.start_text_input
    end

    def stop_text_input
      Console.stop_text_input
    end

    def typed
      Console.input.typed
    end

    def tick_count
      Kernel.tick_count
    end

    def frames_elapsed
      Kernel.tick_count - Console.booted_at
    end

    def seconds
      Kernel.tick_count / 60.0
    end

    # A 0.0..1.0 ramp that repeats forever -- handy for idle motion.
    def oscillate(speed = 1.0, phase = 0.0)
      ((Kernel.tick_count * speed) + phase) % 60 / 60.0
    end

    def sine(speed = 1.0, phase = 0.0, amplitude = 1.0, center = 0.0)
      center + (Math.sin(((Kernel.tick_count * speed) + phase) * (Math::PI / 30.0)) * amplitude)
    end

    # Random helpers with sane defaults for prototyping.
    #
    # DragonRuby's `rand` takes at most one argument, so the console provides
    # range helpers rather than making every cart remember the incantation.
    def rand_int(min, max)
      return min if max <= min
      min + (rand * ((max - min) + 1)).to_i
    end

    # A random Float in min..max.
    def rand_between(min, max)
      return min.to_f if max <= min
      min + (rand * (max - min))
    end

    def pick(list)
      return nil if list.nil? || list.size == 0
      list[(rand * list.size).to_i]
    end

    def chance(probability = 0.5)
      rand < probability
    end
  end
end