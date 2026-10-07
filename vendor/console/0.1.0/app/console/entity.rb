# Console::Entity -- a flat, fast entity store.
#
# Entities are plain Hashes with `x`, `y`, `w`, `h`, `kind` and a unique `id`.
# Keeping them Hash-shaped matters: DragonRuby renders Hash primitives faster
# than class instances, and a hash entity can be passed straight to
# `args.outputs.sprites <<` when it has a `path`.
#
#   spawn Bullet, kind: :bullet, x: 100, y: 100,
#                     sprite: 'star', vx: 4, vy: 0
#   each_entity :bullet do |b|
#     move b, vx: b.vx, vy: b.vy
#     despawn b if off_screen?(b)
#   end
#
# `kind` is the tag used for querying, animation lookup (sprites/<kind>/<state>)
# and collision groups.
module Console
  class EntityStore
    attr_reader :entities
    attr_accessor :next_id

    def initialize
      @entities = []
      @by_id = {}
      @next_id = 1
    end

    def size
      @entities.size
    end

    # Create an entity. `klass` may be a Class (which must respond to
    # `defaults` or take a Hash) or any Symbol used purely as documentation.
    #
    # Returns the entity Hash.
    def spawn(klass = nil, attributes = {})
      kind = attributes[:kind]
      kind ||= klass if klass.is_a?(Symbol)
      e = { id: @next_id }
      @next_id += 1

      if klass.is_a?(Class)
        if klass.respond_to?(:spawn_defaults)
          e.merge! klass.spawn_defaults
        end
        if klass.respond_to?(:defaults)
          e.merge! klass.defaults
        end
      end

      e[:kind] = kind.to_sym if kind
      e.merge! attributes
      e[:kind] = kind.to_sym if kind && !e[:kind]
      e[:x] ||= 0.0
      e[:y] ||= 0.0
      e[:w] ||= 16
      e[:h] ||= 16

      @entities << e
      @by_id[e[:id]] = e
      e
    end

    def despawn(entity)
      return false unless entity
      id = entity[:id]
      @by_id.delete id
      @entities.delete entity
      true
    end

    def despawn_if(&block)
      doomed = @entities.select(&block)
      doomed.each { |e| despawn e }
      doomed.size
    end

    def [](id)
      @by_id[id]
    end

    def clear(kind = nil)
      if kind.nil?
        @entities = []
        @by_id = {}
        return
      end
      @entities.select { |e| e[:kind] == kind.to_sym }.each { |e| despawn e }
    end

    def count(kind = nil)
      return @entities.size if kind.nil?
      @entities.count { |e| e[:kind] == kind.to_sym }
    end

    def any?(kind)
      @entities.any? { |e| e[:kind] == kind.to_sym }
    end

    def all(kind = nil)
      return @entities.dup if kind.nil?
      @entities.select { |e| e[:kind] == kind.to_sym }
    end

    def each(kind = nil, &block)
      if kind.nil?
        @entities.each(&block)
      else
        @entities.each { |e| block.call e if e[:kind] == kind.to_sym }
      end
      @entities.size
    end

    def each_with_kind(kind, &block)
      each kind, &block
    end

    # --- queries ---------------------------------------------------------

    # All entities of `kind` intersecting `rect`.
    def colliding(rect, kind = nil)
      out = []
      @entities.each do |e|
        next if kind && e[:kind] != kind.to_sym
        next if e[:dead]
        next unless e.intersect_rect? rect
        out << e
      end
      out
    end

    # The first entity of `kind` intersecting `rect`.
    def colliding_one(rect, kind = nil)
      @entities.each do |e|
        next if kind && e[:kind] != kind.to_sym
        next if e[:dead]
        return e if e.intersect_rect? rect
      end
      nil
    end

    def nearest(rect, kind = nil)
      best = nil
      best_d = nil
      c = Geom.center rect
      @entities.each do |e|
        next if kind && e[:kind] != kind.to_sym
        d = Geometry.distance c, Geom.center(e)
        if best_d.nil? || d < best_d
          best = e
          best_d = d
        end
      end
      best
    end

    # --- motion ----------------------------------------------------------

    def move(entity, vx: 0, vy: 0)
      entity[:x] = entity[:x] + vx
      entity[:y] = entity[:y] + vy
      entity
    end

    def move_to(entity, x, y)
      entity[:x] = x
      entity[:y] = y
      entity
    end

    def toward(entity, target, speed)
      c = Geom.center entity
      t = Geom.center target
      a = Geometry.angle c, t
      entity[:vx] = Math.sin(a.to_radians) * speed
      entity[:vy] = Math.cos(a.to_radians) * speed
      entity
    end

    # Distance from a point to the centre of `rect`.
    def center(rect)
      Geom.center rect
    end
  end

  # Sprite-resolution + animation glue for entities.
  module EntityDraw
    extend self

    # Resolve an entity's sprite. Prefers an active animation, then
    # `entity[:sprite]`, then `entity[:path]`, then the generated placeholder.
    def sprite_path(console, entity)
      if entity[:sprite_frames] && entity[:sprite_frames].size > 0
        i = entity[:sprite_frame] || 0
        return entity[:sprite_frames][i % entity[:sprite_frames].size]
      end
      return entity[:sprite] if entity[:sprite]
      return entity[:path] if entity[:path]
      return entity[:kind] if entity[:kind]
      :solid
    end

    # Draw an entity, honouring an active animation, tint, alpha, flips and
    # rotation. Routes through Draw so the camera transform applies.
    #
    #   draw_entity entity
    #   draw_entity entity, angle: spin
    def draw_entity(console, entity, spec = {})
      prim = { x: entity[:x], y: entity[:y],
               w: entity[:w], h: entity[:h] }

      # An active animation wins; otherwise fall back to the entity's own
      # sprite, then its path, then its kind. Without the fallback an entity
      # with no matching animation folder renders as an empty box.
      frame = console.anim.primitive_props entity
      if frame
        prim = prim.merge frame
      else
        prim[:path] = sprite_path(console, entity)
      end

      %i[flip_horizontally flip_vertically angle angle_anchor_x
         angle_anchor_y source_x source_y source_w source_h z].each do |k|
        prim[k] = entity[k] if entity[k]
      end

      if entity[:tint] || entity[:alpha]
        prim = prim.merge Palette.to_hash(entity[:tint] || :white, entity[:alpha])
      end

      prim = prim.merge(spec) if spec && spec.size > 0
      console.draw.sprite prim
    end
  end
end