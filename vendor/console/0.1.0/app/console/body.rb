# Console::Body -- a kinematic platformer body.
#
# Deliberately not a physics engine. There is no solver, no impulse response,
# no rigid bodies and no friction model, because the games that would use this
# do not need one -- a platformer needs gravity, a floor and a wall, and that
# is a state machine rather than a simulation.
#
#   body = Console::Body.new x: 64, y: 400, w: 16, h: 24, gravity: 0.4
#
#   def update
#     body.vx = input.axis_x * 4
#     body.vy += body.gravity
#     body.jump 12 if input.pressed?(:accept) && body.grounded?
#     body.update map.solids
#   end
#
#   def render
#     draw_entity body.entity
#   end
#
# Two decisions in here are what separate a body that feels solid from one that
# does not, and both are about NOT taking the obvious path.
#
# SUBSTEPPING. A body falling for two seconds accumulates enough velocity to
# cross a platform in a single frame, and a single-frame overlap test then
# reports no collision at all -- the body passes straight through the floor and
# the game quietly breaks. Every move is therefore split into steps no larger
# than MAX_STEP, and each step is fully resolved. This is the single most
# important line of code in the file.
#
# AXIS SEPARATION WITH RETRY. Moving on X and Y independently is what makes
# you slide along a wall instead of sticking to it: a wall zeroes vx but
# leaves vy alone, so you keep falling. But resolving X first and then Y once
# is not enough for corners -- a body moving diagonally into the corner of a
# step gets blocked on X and then also blocked on Y by the same block, and
# snags. So when X is blocked, the Y move is retried at the corrected position,
# and the body walks up onto the step instead of catching on it.
module Console
  class Body
    # Largest distance a single resolution step may cover. Anything smaller
    # than the thinnest solid in the level is safe; 8px is comfortably under
    # the 16px tiles the console ships while keeping the step count low.
    MAX_STEP = 8.0

    # How far the body may penetrate a solid before it is treated as a
    # collision. A small positive value keeps a body that is already resting
    # on a floor from re-reporting a landing every frame.
    SKIN = 0.01

    attr_accessor :x, :y, :w, :h
    attr_accessor :vx, :vy, :gravity, :max_fall, :step_height
    attr_accessor :friction, :entity
    attr_reader :grounded, :wall, :ceiling, :wall_dir, :on_floor, :on_roof
    attr_reader :solids

    # One options hash, never a positional list.
    #
    # mruby binds a trailing key: value list to the FIRST optional parameter,
    # so `Body.new(x: 1, y: 2)` would drop the whole hash into the first
    # positional argument. One hash is the only spelling that works.
    #
    # Pass `entity:` to drive an existing entity hash: x/y are read from it at
    # construction and written back on every update, so `draw_entity` and the
    # animation system keep working on the same object.
    def initialize(options = {})
      @entity = options[:entity]

      @w = (options[:w] || (@entity && @entity[:w]) || 16).to_f
      @h = (options[:h] || (@entity && @entity[:h]) || 16).to_f
      @x = (options[:x] || (@entity && @entity[:x]) || 0).to_f
      @y = (options[:y] || (@entity && @entity[:y]) || 0).to_f

      @vx = (options[:vx] || 0).to_f
      @vy = (options[:vy] || 0).to_f
      @gravity = (options[:gravity] || 0.25).to_f
      @max_fall = options[:max_fall] ? options[:max_fall].to_f : nil
      @step_height = options[:step_height] ? options[:step_height].to_f : 0.0
      @friction = options.key?(:friction) ? options[:friction].to_f : 1.0

      @grounded = false
      @wall = false
      @ceiling = false
      @wall_dir = nil
      @on_floor = false
      @on_roof = false
      @was_grounded = false
      @landed_this_frame = false
      @fell = 0.0
      @solids = []
    end

    def rect
      { x: @x, y: @y, w: @w, h: @h }
    end

    def entity
      @entity ||= { x: @x, y: @y, w: @w, h: @h, kind: :body }
    end

    def grounded?
      @grounded
    end

    # True on the single frame the body transitions from airborne to standing.
    # Edge-triggered on purpose: a `while grounded?` is wrong, because the body
    # stays grounded for every frame it rests.
    def landed?
      @landed_this_frame
    end

    # Falling distance, in pixels, accumulated since the body left the ground.
    # This is what a fall-damage or squash-and-stretch effect wants; it is not
    # the instantaneous vy.
    def fall_distance
      @fell
    end

    def wall?
      @wall
    end

    def ceiling?
      @ceiling
    end

    # :left, :right, or nil. Direction the body was pushed by a wall.
    def wall_dir
      @wall_dir
    end

    # The solid the body is standing on, or nil. Useful for riding a moving
    # platform, which is the usual reason to want the reference rather than
    # just a boolean.
    def floor
      @on_floor
    end

    def roof
      @on_roof
    end

    # Set vertical velocity directly. A jump is this plus a grounded? check --
    # there is no separate jump arc to learn.
    def jump(speed)
      @vy = speed
      @fell = 0.0
      self
    end

    # Advance one frame against a list of solid rects.
    #
    # Each solid is `{ x:, y:, w:, h: }` plus an optional `one_way:` flag.
    # Solids are static; see the note in the README about why moving platforms
    # are left to the cart.
    def update(solids = nil)
      @solids = solids || []

      # Snapshot before the move so `landed?` can be edge-triggered.
      @was_grounded = @grounded
      @landed_this_frame = false
      @grounded = false
      @wall = false
      @ceiling = false
      @wall_dir = nil
      @on_floor = nil
      @on_roof = nil
      @blocked_rect = nil

      # Gravity is a positive magnitude that pulls DOWN. DragonRuby's origin is
      # bottom-left, so falling is a DECREASING y and therefore a negative vy.
      # (DragonRuby's own samples write `gravity = -0.2` for this reason; taking
      # the magnitude as positive keeps cart authors from having to remember
      # which way is down.)
      @vy -= @gravity
      @vy = -@max_fall if @max_fall && @vy < -@max_fall

      # X first, then Y. Doing Y first makes landing feel like ice.
      #
      # `want_vx` is captured because resolve zeroes @vx on contact, and the
      # step-up retry needs the velocity the body was TRYING to move with.
      want_vx = @vx
      blocked_x = move_axis :x, want_vx, @solids

      # Step-up. If a wall stopped horizontal motion, ask whether lifting the
      # body by up to step_height would clear the obstruction; if so, lift and
      # retry the same move. Without this a body walks into every ledge and
      # stops dead, because by the time the Y pass runs the body is resting on
      # the floor and is already blocked vertically.
      #
      # Disabled by default (step_height 0). Auto-stepping is a feel choice,
      # and defaulting it on lets a cart walk up a wall it meant to be blocked
      # by.
      if blocked_x
        lift = step_up_offset @solids
        if lift
          @y += lift
          blocked_x = move_axis :x, want_vx, @solids
        end
      end

      blocked_y = move_axis :y, @vy, @solids

      @vx *= @friction
      @vy = 0.0 if blocked_y

      @landed_this_frame = @grounded && !@was_grounded
      @fell = 0.0 if @grounded
      @fell += @gravity unless @grounded

      sync_entity
      self
    end

    # Move along one axis in substeps, resolving after each. Returns true if
    # any step ended up blocked.
    def move_axis(axis, delta, solids)
      return false if delta.nil? || delta == 0.0

      distance = delta.abs
      steps = (distance / MAX_STEP).ceil
      steps = 1 if steps < 1
      step = delta / steps

      blocked = false
      steps.times do
        @x += step if axis == :x
        @y += step if axis == :y

        hit = resolve axis, solids
        next unless hit

        blocked = true
        break
      end

      blocked
    end

    # Push the body back out of anything it overlaps, along `axis` only.
    #
    # Resolving one axis at a time is what produces wall sliding: a horizontal
    # block clears vx but leaves vy untouched, so gravity keeps working and the
    # body slides down the wall rather than sticking to it.
    def resolve(axis, solids)
      return nil if solids.nil? || solids.size == 0

      r = rect
      hit = nil

      solids.each do |s|
        next unless overlap?(r, s)
        next if one_way_ignores?(axis, s)

        # Remember where the overlap actually happened. resolve() is about to
        # snap the body clear of s, and step_up_offset needs the position that
        # was blocked -- not the corrected one, which no longer overlaps
        # anything and would report "no step needed" forever.
        @blocked_rect = r if axis == :x

        case axis
        when :x
          if @vx > 0
            @x = s[:x] - @w
            @wall_dir = :right
          else
            @x = s[:x] + s[:w]
            @wall_dir = :left
          end
          # Clearing vx here (rather than only in the caller) is what actually
          # stops the body at a wall. vy is deliberately left alone so the body
          # slides down the wall instead of sticking to it.
          @vx = 0.0
          @wall = true
        when :y
          if @vy <= 0
            # Falling (or resting): the body lands on top.
            @y = s[:y] + s[:h]
            @grounded = true
            @on_floor = s
          else
            # Rising: the head hits a ceiling.
            @y = s[:y] - @h
            @ceiling = true
            @on_roof = s
          end
        end

        hit = s
        r = rect
      end

      hit
    end

    # How far the body may lift itself to walk over a low ledge, or 0 (the
    # default) to treat every wall as a wall. See the step-up note in `update`.
    def step_up_offset(solids)
      return nil if @step_height.nil? || @step_height <= 0
      return nil if solids.nil? || solids.size == 0

      # Deliberately the BLOCKED rect, not the corrected one.
      r = @blocked_rect || rect
      need = 0.0
      solids.each do |s|
        next if s[:one_way]
        next unless overlap?(r, s)
        top = s[:y] + s[:h]
        rise = top - @y
        need = rise if rise > need
      end

      return nil if need <= 0
      return nil if need > @step_height
      need
    end

# True when a solid should be IGNORED for this move.
    #
    # A one-way platform is solid only from above and only while descending.
    # Both halves matter: without the first, a body rising through a platform
    # is stopped by it; without the second, a body standing on a platform can
    # never jump back up through it.
    def one_way_ignores?(axis, solid)
      return false unless solid[:one_way]
      return false unless axis == :y

      # Rising: pass straight up through it.
      return true if @vy > 0

      # Already sunk below it: there is nothing left to stand on.
      return true if (@y + @h) <= solid[:y] + SKIN

      false
    end

    def overlap?(a, b)
      a[:x] < b[:x] + b[:w] && (a[:x] + a[:w]) > b[:x] &&
        a[:y] < b[:y] + b[:h] && (a[:y] + a[:h]) > b[:y]
    end

    def sync_entity
      return unless @entity
      @entity[:x] = @x
      @entity[:y] = @y
      @entity[:vx] = @vx
      @entity[:vy] = @vy
      @entity
    end
  end
end