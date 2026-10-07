# Console::Map -- load a level out of an LDTK export.
#
# LDTK (https://ldtk.io) is the one editor whose data model is close enough to
# the console's to be worth native support: it places entities in a level, and
# an entity here is already a rect with a kind and a bag of properties.
#
#   map = Console::Map.load 'levels/Level_0.ldtk'
#   map.solids          # collision rects, harvested from IntGrid layers
#   map.entities        # [{ kind: :enemy, x:, y:, w:, h:, hp: 3, label: 'boss' }]
#   map.spawn_all       # hand every entity to the entity store
#
# Two details decide whether this works or quietly does not, so they are worth
# stating up front.
#
# COORDINATES. LDTK is a top-left origin with y growing DOWN. The console (and
# DragonRuby underneath it) is bottom-left with y growing UP. Everything is
# flipped on load, so a platform near the top of the LDTK level lands at a
# high y -- which is what bottom-left thinking expects. Pass `flip_y: false`
# to keep raw LDTK coordinates.
#
# FIELD TYPES. An Int/Float/String/Bool field stores its payload under 'value'.
# A Point field does NOT: it stores 'cx'/'cy' as siblings and the 'value' key
# is absent entirely. In mruby an absent key is not a nil value -- chaining
# into one raises `:[] method missing on ~NilClass~` rather than returning nil.
# So every field is read through a __type branch and never assumed to have a
# 'value'. See `self.field_value`.
module Console
  class Map
    # LDTK layer __type values this loader understands. Anything else is
    # ignored rather than guessed at, so an unfamiliar LDTK version degrades
    # to "no solids" instead of to nonsense geometry.
    ENTITY_LAYER = 'Entities'
    INTGRID_LAYER = 'IntGrid'
    TILE_LAYER = 'Tiles'
    AUTO_LAYER = 'AutoLayer'

    # Field __type values that carry their payload under 'value'. Point is
    # deliberately absent: it is the one that does not.
    VALUE_FIELD_TYPES = %w[Int Float String Bool Color Tile Enum Array EntityRef
                           LocalGrid].freeze

    attr_reader :identifier, :path, :width, :height
    attr_reader :entities, :solids, :tiles, :warnings

    # Load and parse an .ldtk file. Returns nil (with a console warning) when
    # the file is missing or unreadable, so a missing level degrades to a
    # visible warning rather than a boot crash.
    #
    # The path is resolved against the booted cart first, so a cart saying
    # `load_map 'maps/Level_0.ldtk'` loads its own level, and the warning below
    # names the file that was actually looked for.
    def self.load(path, options = {})
      path = Assets.resolve path
      unless DR.stat_file(path)
        Console.warn "map not found: #{path}"
        return nil
      end

      contents = DR.read_file path
      if contents.nil? || contents.to_s.length == 0
        Console.warn "map is empty or unreadable: #{path}"
        return nil
      end

      data = DR.parse_json contents
      unless data.is_a?(Hash)
        Console.warn "map is not a JSON object: #{path}"
        return nil
      end

      new data, options.merge(path: path)
    rescue => e
      # Only the IO/parse boundary is rescued. A malformed level is a real
      # error and the cart author needs to see it.
      Console.warn "map failed to load: #{path} (#{e.class}: #{e.message})"
      nil
    end

    # Build a map from an already-parsed Hash. Useful for tests and for levels
    # that arrive over the network rather than off disk.
    def self.from_hash(data, options = {})
      new data, options
    end

    # Read one LDTK field instance into a plain Ruby value.
    #
    # Point is the case that matters: it has no 'value' key at all, so asking
    # for one returns nil and chaining into THAT nil raises. Branching on
    # __type is the only safe way in.
    def self.field_value(field)
      return nil unless field.is_a?(Hash)
      type = field['__type'].to_s

      if type == 'Point'
        return nil unless field.key?('cx') && field.key?('cy')
        return { x: field['cx'].to_f, y: field['cy'].to_f }
      end

      # LDTK renamed the payload key from `value` to `__value`. A loader that
      # knows only the old spelling loses EVERY field on a modern export, and
      # loses them silently: a missing key reads as "no value supplied" rather
      # than as an error, so the level still loads and just comes out bare.
      # Read the current key first and keep the old one as a fallback so both
      # generations parse. Point is branched above -- it has neither key.
      return field['__value'] if field.key?('__value')
      return field['value'] if field.key?('value')
      nil
    end

    def initialize(data, options = {})
      @path = options[:path]
      @flip_y = options.key?(:flip_y) ? options[:flip_y] : true
      @solid_entities = options[:solid_entities] || []
      @one_way_value = options[:one_way_value]
      @warnings = []
      @entities = []
      @solids = []
      @tiles = []

      level = self.class.send :pick_level, data, options[:level]
      if level.nil?
        @identifier = nil
        @width = 0
        @height = 0
        @warnings << 'no level found in map'
        return
      end

      @identifier = level['identifier'].to_s
      @width = (level['pxWid'] || 0).to_f
      @height = (level['pxHei'] || 0).to_f

      read_layers level
    end

    # Entities of one kind, by LDTK identifier ('Enemy') or console kind
    # (:enemy). Both spellings work because LDTK's own naming is PascalCase.
    def entities_of(kind)
      wanted = Console::Str.snake kind.to_s
      @entities.select { |e| e[:kind].to_s == wanted }
    end

    # Push every entity into the store and return what was created.
    #
    # `kind:` is taken from the LDTK __identifier, so an 'Enemy' entity
    # becomes a :enemy entity without the cart naming anything. Extra keys are
    # merged per entity, for carts that want to stamp a cart-specific id.
    def spawn_all(extra = {})
      @entities.map do |attrs|
        Console.entities.spawn nil, attrs.merge(extra)
      end
    end

    def to_s
      "#<Console::Map #{@identifier} #{@entities.size} entities, " \
        "#{@solids.size} solids, #{@tiles.size} tiles>"
    end

    private

    # An .ldtk project nests levels two deep: data['worlds'][n]['levels'][m].
    # Tolerate the other shapes too -- a top-level levels array, or a bare
    # level exported on its own -- because people hand-edit these files.
    def self.pick_level(data, wanted)
      candidates = []

      if data['worlds'].is_a?(Array)
        data['worlds'].each do |world|
          next unless world.is_a?(Hash)
          next unless world['levels'].is_a?(Array)
          world['levels'].each { |l| candidates << l if l.is_a?(Hash) }
        end
      end

      if data['levels'].is_a?(Array)
        data['levels'].each { |l| candidates << l if l.is_a?(Hash) }
      end

      # A single level exported on its own has layers but no wrapper.
      candidates << data if data['layerInstances'].is_a?(Array)

      candidates = candidates.select { |l| l['layerInstances'].is_a?(Array) }
      return nil if candidates.empty?

      if wanted
        match = candidates.find { |l| l['identifier'].to_s == wanted.to_s }
        return match if match
      end

      candidates.first
    end

    def read_layers(level)
      instances = level['layerInstances']
      return unless instances.is_a?(Array)

      instances.each do |layer|
        next unless layer.is_a?(Hash)
        type = layer['__type'].to_s
        case type
        when ENTITY_LAYER then read_entity_layer layer
        when INTGRID_LAYER then read_intgrid_layer layer
        when TILE_LAYER, AUTO_LAYER then read_tile_layer layer
        end
      end
    end

    # --- entities --------------------------------------------------------

    def read_entity_layer(layer)
      instances = layer['entityInstances']
      return unless instances.is_a?(Array)

      instances.each do |inst|
        next unless inst.is_a?(Hash)
        attrs = entity_attributes inst
        if solid_entity? inst, attrs
          @solids << solid_from_entity(attrs)
        else
          @entities << attrs
        end
      end
    end

    # Whether an entity is collision rather than a thing to spawn.
    #
    # The map gets to decide this, so a cart never has to keep a list of every
    # entity type in the level that happens to be solid -- a list that silently
    # rots the moment someone adds a platform in LDTK. Three ways to say it, in
    # order of explicitness:
    #
    #   1. `solid_entities:` names the LDTK identifier outright.
    #   2. The entity carries a truthy `Solid` bool field.
    #   3. The entity carries a truthy `OneWay` bool field. A pass-through
    #      platform is still a platform, so one-way implies solid instead of
    #      being treated as an unrelated flag.
    #
    # (2) and (3) are read off the entity instance, and LDTK bakes an entity
    # type's field defaults into every placed copy -- so ticking `Solid` once
    # on the Platform TYPE in the editor marks every Platform in the level,
    # and there is nothing left to remember on the console side.
    def solid_entity?(inst, attrs)
      return true if @solid_entities.include?(inst['__identifier'].to_s)
      return true if attrs[:solid]
      return true if attrs[:one_way]
      false
    end

    # LDTK entity -> console entity hash.
    #
    # Fields are applied BEFORE the geometry so that a stray field can never
    # overwrite x/y/w/h and produce an entity with no usable rect.
    def entity_attributes(inst)
      attrs = {}
      fields = inst['fieldInstances']

      if fields.is_a?(Array)
        fields.each do |field|
          next unless field.is_a?(Hash)
          name = field['__identifier']
          next if name.nil? || name.to_s.empty?
          value = self.class.field_value field
          # A nil value means the field was left at an LDTK default that has
          # no payload (Point with no cx/cy). Keeping the key would shadow the
          # cart's own spawn default with nil, so it is dropped.
          attrs[Console::Str.snake(name).to_sym] = value unless value.nil?
        end
      end

      w = (inst['width'] || 16).to_f
      h = (inst['height'] || 16).to_f

      attrs[:kind] = Console::Str.snake(inst['__identifier']).to_sym
      attrs[:ldtk_identifier] = inst['__identifier'].to_s
      attrs[:w] = w
      attrs[:h] = h
      attrs[:x] = (inst['px'] || [0, 0])[0].to_f
      attrs[:y] = console_y((inst['px'] || [0, 0])[1].to_f, h)
      attrs
    end

    def solid_from_entity(attrs)
      {
        x: attrs[:x],
        y: attrs[:y],
        w: attrs[:w],
        h: attrs[:h],
        # `one_way` on the entity is the LDTK-native spelling of a pass-through
        # platform; honour both that and the generic flag.
        one_way: attrs[:one_way] ? true : false,
        # Deliberately the same shape as an IntGrid-derived solid, so a cart
        # reads every entry in `solids` the same way without caring which layer
        # it came from.
        kind: :solid
      }
    end

    # --- intgrid (collision) ---------------------------------------------

    # LDTK's own convention for collision: an IntGrid layer where any non-zero
    # cell is solid. The layer's grid size is the tile size, and rows run
    # top-down, so each row is mirrored into console space.
    def read_intgrid_layer(layer)
      csv = layer['intGridCsv']
      return unless csv.is_a?(Array)

      grid = (layer['__gridSize'] || 16).to_f
      return if grid <= 0

      cols = (layer['__cWid'] || (@width / grid).ceil).to_i
      rows = (layer['__cHei'] || (@height / grid).ceil).to_i

      csv.each_with_index do |value, i|
        next if value.to_i == 0

        col = i % cols
        # NOTE: mruby's `/` is ALWAYS float division -- 181 / 20 is 9.05, not
        # 9. Without this .to_i every solid in the row lands at a slightly
        # different y and a level's floor comes out subtly stepped. This is the
        # single most mruby-specific bug in this file.
        row = (i / cols).to_i
        # Guard against a short or ragged csv rather than trusting the
        # dimensions; a malformed grid should not invent geometry.
        next if row >= rows

        @solids << {
          x: col * grid,
          y: @height - ((row + 1) * grid),
          w: grid,
          h: grid,
          one_way: one_way_cell?(value),
          kind: :solid
        }
      end
    end

    # `one_way_value:` lets a level mark pass-through platforms with a
    # distinct IntGrid value (2, say) instead of requiring a second layer.
    def one_way_cell?(value)
      return false if @one_way_value.nil?
      value.to_i == @one_way_value.to_i
    end

    # --- tiles ------------------------------------------------------------

    # Tiles are collected but not drawn: this is data, not a renderer.
    # Each entry keeps both LDTK's source position and a console-space px so a
    # future draw pass never has to re-derive the flip.
    def read_tile_layer(layer)
      grid = (layer['__gridSize'] || 16).to_f
      return if grid <= 0

      ['gridTiles', 'autoLayerTiles'].each do |key|
        list = layer[key]
        next unless list.is_a?(Array)

        list.each do |t|
          next unless t.is_a?(Hash)
          px = t['px'] || [0, 0]
          @tiles << {
            px: [px[0].to_f, console_y(px[1].to_f, grid)],
            src: t['src'] || [0, 0],
            flip_x: (t['f'] || 0).to_i == 1,
            flip_y: (t['f'] || 0).to_i == 2,
            tile_id: t['t'],
            size: grid,
            layer: layer['__identifier'].to_s
          }
        end
      end
    end

    # LDTK y (down, from the top of the level) -> console y (up, from the
    # bottom), converting a top-down height to a bottom-up one.
    def console_y(ldtk_y, height = 0)
      return ldtk_y unless @flip_y
      @height - ldtk_y - height
    end
  end
end