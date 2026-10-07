# Console::Animation -- sprite animation and an animation state machine.
#
# Two levels:
#
#   Console::Anim   a per-console registry of active animations, keyed by
#                   entity id. Use this for gameplay code.
#
#   Console::Frame  a single running animation (a frame counter, a finished
#                   flag, an interrupt lock). Use this if you need to drive
#                   one yourself.
#
# Frame timing is built on DragonRuby's Numeric.frame, which is tick-based:
# DragonRuby ticks at 60/sec, so `fps: 12` means `hold_for: 5`.
#
#   animate(entity, :run)                       # sprites/<kind>/<run>/*.png
#   animate(entity, :walk, sheet: 'hero.png',   # a sprite sheet, cropped
#                 frame_w: 16, frame_h: 20, frames: 6)
#   animate(entity, :hit, on_finish: :idle)     # one-shot, then idle
#   animate(entity, :die, repeat: false, lock: 12)
module Console
  FPS = 60.0

  # A single running animation.
  class Frame
    attr_reader :name, :kind, :frame_count, :hold_for, :repeat, :started_at
    attr_accessor :on_finish, :locked_until, :next_state

    def initialize(spec, tick_count)
      @name = spec[:name]
      @kind = spec[:kind] || :sequence
      @frame_count = spec[:frame_count] || 1
      @fps = spec[:fps] || 12
      @hold_for = spec[:hold_for] || (FPS / @fps).round
      @hold_for = 1 if @hold_for < 1
      @repeat = spec.key?(:repeat) ? spec[:repeat] : true
      @repeat_index = spec[:repeat_index] || 0
      @started_at = tick_count
      @finished = false
      @on_finish = spec[:on_finish]
      @next_state = nil
      lock = spec[:lock] || 0
      @locked_until = tick_count + lock
      @sheet = spec[:sheet]
      @frame_w = spec[:frame_w]
      @frame_h = spec[:frame_h]
      @frames = spec[:frames]
      @speed = spec[:speed] || 1.0
    end

    # Advance and report whether this animation has run to completion.
    def update(tick_count)
      elapsed = (tick_count - @started_at) * @speed
      total = @frame_count * @hold_for
      if elapsed >= total
        if @repeat
          # Loop by rebasing the start so long-running anims do not drift.
          @started_at = tick_count - ((elapsed - total) % total)
          false
        else
          @finished = true unless @finished
          true
        end
      else
        false
      end
    end

    def finished?
      @finished
    end

    def index(tick_count)
      return @repeat_index if @finished
      elapsed = (tick_count - @started_at) * @speed
      frame = (elapsed / @hold_for).to_i
      if frame >= @frame_count
        @repeat_index
      else
        frame
      end
    end

    # Locked animations refuse to be replaced; this is how a death animation
    # keeps a flinch from cutting it short.
    def locked?(tick_count)
      tick_count < @locked_until
    end

    # The sprite primitive properties for the current frame.
    def primitive_props(tick_count)
      i = index tick_count
      if @kind == :sheet
        { path: @sheet,
          source_x: i * @frame_w,
          source_y: 0,
          source_w: @frame_w,
          source_h: @frame_h }
      else
        { path: @frames[i] || @frames[0] }
      end
    end
  end

  # The per-console registry of animations.
  class Anim
    def initialize(args)
      @args = args
      @by_id = {}
      @definitions = {}
    end

    def tick_count
      Kernel.tick_count
    end

    # Advance every active animation and apply finish handling.
    def update
      tc = tick_count
      @by_id.each_value { |frame| frame.update tc }
    end

    def active?(id)
      @by_id.key?(id)
    end

    def [](id)
      @by_id[id]
    end

    def name_of(id)
      f = @by_id[id]
      f ? f.name : nil
    end

    def playing?(id, name)
      name_of(id) == name
    end

    def finished?(id)
      f = @by_id[id]
      f ? f.finished? : true
    end

    def locked?(id)
      f = @by_id[id]
      f ? f.locked?(tick_count) : false
    end

    # Start an animation on an entity. Returns the Frame, or nil if the
    # requested animation is locked out by an uninterruptible one.
    def play(entity, name, options = {})
      id = entity[:id]
      return nil if entity[:id].nil?
      existing = @by_id[id]
      return nil if existing && existing.name != name && existing.locked?(tick_count)
      return existing if existing && existing.name == name && !options[:restart]

      spec = build_spec(entity, name, options)
      return nil unless spec
      frame = Frame.new spec, tick_count
      @by_id[id] = frame
      frame
    end

    def stop(id)
      @by_id.delete id
    end

    def stop_all
      @by_id = {}
    end

    # The frame properties to merge into the entity's sprite primitive.
    def primitive_props(entity)
      frame = @by_id[entity[:id]]
      return nil unless frame
      frame.primitive_props tick_count
    end

    # Draw an animated sprite for an entity, using the entity's own x/y/w/h
    # plus any transform keys it carries.
    def draw(entity, spec = {})
      frame = @by_id[entity[:id]]
      return nil unless frame
      prim = { x: entity[:x], y: entity[:y], w: entity[:w], h: entity[:h] }
      prim = prim.merge(frame.primitive_props(tick_count))
      prim = prim.merge(spec) if spec
      @args.outputs.sprites << prim
      prim
    end

    private

    def build_spec(entity, name, options)
      opts = {}
      options.each { |k, v| opts[k] = v }
      opts[:name] = name

      # An explicit frame list (or sheet) short-circuits asset discovery.
      if opts[:frames] && opts[:frames].size > 0
        opts[:kind] ||= :sequence
        opts[:frames] = opts[:frames]
        opts[:frame_count] ||= opts[:frames].size
        return opts
      elsif opts[:sheet]
        opts[:sheet] = Assets.resolve opts[:sheet]
        opts[:kind] = :sheet
        opts[:frame_count] ||= opts[:frames]
        opts[:frame_w] ||= entity[:w]
        opts[:frame_h] ||= entity[:h]
        return nil if opts[:frame_count].nil?
        opts
      else
        group = opts[:group] || animation_group(entity, name)
        paths = Sprites.frames group
        if paths.size == 0
          # No frames on disk: fall back to whatever the state name resolves to
          # as a single static sprite, so states still work without art.
          static = Sprites.path(name)
          return nil if static == :solid && !Sprites.exists?(name)
          return { name: name, kind: :sequence, frames: [static],
                   frame_count: 1, repeat: false }.merge(opts)
        end
        opts[:kind] = :sequence
        opts[:frames] = paths
        opts[:frame_count] = paths.size
        opts
      end
    end

    # sprites/<kind>/<state>/... by convention, e.g. an entity with
    # kind: :hero playing :run looks in sprites/hero/run/.
    def animation_group(entity, name)
      kind = entity[:kind]
      kind = 'sprites' if kind.nil?
      "#{kind}/#{name}"
    end
  end
end