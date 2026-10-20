# The written half of the documentation: the language a cart is written in, how
# a cart is put together, and what a cart can do.
#
# ConsoleDocumentation reads the library's own comments, which describe the
# modules. This is the part that cannot be extracted, because it is about
# *writing* a cart rather than what is inside the library -- the shape of a
# cart, the hooks it implements, and a worked example of each thing a first
# cart needs.
#
# Every call in these samples was checked against the library before it was
# written, and there is a test that keeps them valid Ruby. What that cannot
# check is intent, so the samples are deliberately small: each one is the
# smallest thing that does the job, and the API reference is one click away for
# everything else.
class ConsoleGuide
  # A worked example: what it is for, and the code.
  #
  # `file` is where the code goes and `verb` is what to do with the file it
  # names. A sample that says what to write but not where to write it leaves
  # the one thing a reader cannot guess.
  Sample = Struct.new(:title, :note, :code, :id, :file, :verb, keyword_init: true)

  # A titled piece of prose, with an example, and sometimes a list.
  #
  # The language primer and the cart structure section are both built from
  # these: a short explanation, then something to look at. It is the only shape
  # a reference like this can be taken in.
  Topic = Struct.new(:title, :prose, :code, :list, keyword_init: true)

  # The sections of the documentation page, in the order they appear.
  #
  # One list, so the contents at the top and the headings below cannot drift
  # apart: a link to a section that is not there is a dead end for the reader.
  SECTIONS = [
    { id: "start", title: "Getting started" },
    { id: "first-cart", title: "Your first cart" },
    { id: "publishing", title: "Sending a cart here" },
    { id: "primer", title: "Ruby primer" },
    { id: "structure", title: "Cart structure" },
    { id: "reference", title: "API reference" }
  ].freeze

  # What a cart is: a directory, and the contract inside it.
  LAYOUT = {
    tree: <<~TREE,
      carts/mine/
      |-- app/mine.rb      defines Mine
      |-- sprites/         the art this cart owns
      |-- sounds/          the sound this cart owns
      `-- data/            anything else the cart loads
    TREE
    rule: "Name your class after the folder. The console looks for the folder " \
          "name camelized, so `carts/mine/app/mine.rb` can define `Mine` or " \
          "`CartMine`."
  }.freeze

  # The hooks a cart may implement. All of them are optional, which is the
  # point: the loader starts a cart that does nothing but boot.
  #
  # Ordered by when they run, which is the order a reader meets them.
  HOOKS = [
    { name: "self.assets", when: "before boot",
      note: "Names the art the cart owns. Declaring it lets the site check the " \
            "cart at upload time and tell you a sprite is missing before anyone " \
            "plays it." },
    { name: "self.sprite_library", when: "before boot",
      note: "A map of sprite names to paths, for a cart with lots of sprites and " \
            "nothing else to declare." },
    { name: "self.sound_library", when: "before boot",
      note: "The same, for sounds." },
    { name: "setup", when: "once, at boot",
      note: "Build your state here. Spawn what you need and load a level." },
    { name: "update", when: "every frame",
      note: "Move things and read the input. Only used when the cart defines no " \
            "scenes." },
    { name: "render", when: "every frame, last",
      note: "Draws after the current scene, so this is where a HUD that persists " \
            "across scenes belongs." },
    { name: "enter", when: "on entering a scene",
      note: "A scene's own setup. `scene_data` keeps its values between visits, " \
            "so a scene that wants a clean start clears it here." },
    { name: "leave", when: "on leaving a scene",
      note: "A scene's own teardown, for stopping what it started." }
  ].freeze

  # The API reference, grouped by what a reader is trying to do.
  #
  # Require order is the order the modules build on each other, which is the
  # right order to read the source in and the wrong order to look something up
  # in: a reader asking how to draw a sprite should not have to know that
  # `draw.rb` happens to be sixth in a list they have never seen.
  CATEGORIES = [
    { title: "The cart", note: "How the console finds a cart and starts it.",
      slugs: %w[cart_loader core assets] },
    { title: "Drawing", note: "Putting things on the screen.",
      slugs: %w[draw sprites animation palette geom] },
    { title: "Input", note: "Keyboard, gamepad and pointer, as one vocabulary.",
      slugs: %w[input] },
    { title: "Scenes and entities", note: "The things in a game, and the states it is in.",
      slugs: %w[scene entity] },
    { title: "The world", note: "The camera, the levels and the bodies they move through.",
      slugs: %w[camera map body] },
    { title: "Motion", note: "Interpolation, and work that reschedules itself.",
      slugs: %w[tween] },
    { title: "Sound", note: "Music and effects.",
      slugs: %w[audio] },
    { title: "Interface", note: "Widgets, drawn through the draw helpers.",
      slugs: %w[ui] },
    { title: "Text", note: "String helpers, for a runtime without Regexp.",
      slugs: %w[str] },
    { title: "Testing", note: "Tests that run inside the real runtime.",
      slugs: %w[testing] },
    { title: "Version", note: "Where the version string lives.",
      slugs: %w[version] }
  ].freeze

  # What a cart author does not have to do any more, and what publishing costs.
  #
  # Kept here rather than in the view so the page and the API documentation are
  # describing the same thing: if the endpoint changes, this is where it is
  # written down once.
  PUBLISHING = {
    steps: [
      "Download the console. Signed in, the download arrives with a key in " \
        "dragonstation.json beside the library.",
      "Build a cart. ./bin/run --cart arcade boots it locally.",
      "Send it with ./bin/publish-site arcade. It arrives here as a draft under your account.",
      "Play it, then publish it from the cart's page."
    ],
    endpoint: [
      "POST /api/carts",
      "Authorization: Bearer <the api_key from dragonstation.json>",
      "archive=<the cart ZIP, as multipart/form-data>",
      "",
      "201 {\"slug\",\"title\",\"status\":\"draft\",\"url\",...}",
      "401 {\"error\":\"unauthorised\"}          a key that is not yours, or one a newer download replaced",
      "422 {\"error\":...,\"problems\":[...]}    the refusals below, one per line",
      "400 {\"error\":\"no archive\"}             nothing was sent",
      "503 {\"error\":\"no console library ...\"} nothing to pin the cart to"
    ].freeze
  }.freeze

  def hooks = HOOKS

  def publishing = PUBLISHING

  def sections = SECTIONS

  def layout = LAYOUT

  # The language the console is written in.
  #
  # A cart is Ruby, so a reader who knows some programming but not this
  # particular language needs somewhere to start. PICO-8's manual has the same
  # section for the same reason, and it is the section a cart author reads
  # before the API.
  def primer
    @primer ||= [
      Topic.new(
        title: "Comments",
        prose: "A line that starts with `#` is a comment, and runs to the end of " \
               "the line. The console reads your file but never runs a comment, " \
               "so they are worth writing.",
        code: <<~'RUBY'
          # The cart's title, shown on the page.
          TITLE = 'mine'

          # A comment can also sit at the end of a line.
          @x = 400.0   # where the ship starts
        RUBY
      ),
      Topic.new(
        title: "Values",
        prose: "You will meet four kinds of value: numbers, strings, symbols and " \
               "booleans. `nil` is the absence of a value. It and `false` are the " \
               "only things that count as false, so `0` and the empty string are " \
               "both true.",
        code: <<~'RUBY'
          400.0            # a number
          'text'           # a string
          "text #{400}"    # a string with a value put into it
          :right           # a symbol
          true             # a boolean
          nil              # no value at all
        RUBY
      ),
      Topic.new(
        title: "Variables and constants",
        prose: "A name starting with a lowercase letter is a local variable, and " \
               "belongs to the method it is written in. A name starting with an " \
               "uppercase letter is a constant, and Ruby complains if you assign " \
               "to one twice. A name starting with `@` is an instance variable, " \
               "which belongs to the cart and survives between frames.",
        code: <<~'RUBY'
          def setup
            @x = 400.0        # an instance variable: it belongs to the cart
            speed = 4         # a local variable: it belongs to this method
          end
        RUBY
      ),
      Topic.new(
        title: "Conditionals",
        prose: "`if` runs a block when something is true, `unless` runs it when " \
               "something is false, and `elsif` chains more cases. `else` catches " \
               "whatever is left.",
        code: <<~'RUBY'
          if input.held?(:right)
            @x += 4
          elsif input.held?(:left)
            @x -= 4
          else
            @x = 400.0
          end

          @x = 0 unless @dead
        RUBY
      ),
      Topic.new(
        title: "Loops",
        prose: "`while` repeats until its condition goes false. `each` walks a " \
               "collection, and `times` counts. `break` leaves a loop early.",
        code: <<~'RUBY'
          i = 0
          while i < 3
            i += 1
          end

          [1, 2, 3].each do |n|
            draw.text 'tick', x: 10, y: 10
          end

          3.times { |n| spawn :enemy, x: n * 100, y: 200 }
        RUBY
      ),
      Topic.new(
        title: "Methods",
        prose: "`def` starts a method and `end` finishes it. A method returns the " \
               "value of its last expression, or whatever you pass to `return`. A " \
               "block is a chunk of code you hand to a method, written with braces " \
               "or with `do` and `end`.",
        code: <<~'RUBY'
          def limit_to(value, low, high)
            return low if value < low
            return high if value > high
            value
          end

          def setup
            @x = limit_to(@x, 0, 800)
          end
        RUBY
      ),
      Topic.new(
        title: "Hashes and arrays",
        prose: "An array is a list. A hash is a set of key and value pairs. The " \
               "console's API is built on hashes with symbol keys, which is why " \
               "you will see options like `x:` and `y:` so often.",
        code: <<~'RUBY'
          # An array
          @shots = []
          @shots << { x: 100, y: 200 }

          # A hash
          entity = { x: 100, y: 200, sprite: :ship }
          entity[:x]        # 100
          entity.key?(:x)   # true
          entity.merge(y: 300)
        RUBY
      ),
      Topic.new(
        title: "Symbols",
        prose: "A symbol is a name, written with a leading colon. The API asks " \
               "you to name everything with one: a sprite, a button, a colour, an " \
               "action. A symbol is cheaper than a string and always means the same " \
               "thing.",
        code: <<~'RUBY'
          input.held?(:right)      # a button
          draw.sprite path: :ship  # a sprite name
          @color = :accent         # a colour
        RUBY
      ),
      Topic.new(
        title: "Classes",
        prose: "Your cart is a class. Its name comes from the folder it lives in, " \
               "and the console makes one of them for you at boot. Methods written " \
               "inside it are instance methods, and they are the hooks the runtime " \
               "calls. `self.` in front of a method makes it a class method, and " \
               "that is how a cart declares its assets.",
        code: <<~'RUBY'
          class Mine
            def self.assets
              { sprites: { ship: 'sprites/ship.png' } }
            end

            def setup
              @x = 400.0
            end
          end
        RUBY
      )
    ].freeze
  end

  # How a cart is put together, and what happens when it runs.
  #
  # The API reference says what each method does. This says what the console
  # does with your cart, in the order it does it, which is the part a first
  # cart gets wrong.
  def structure
    @structure ||= [
      Topic.new(
        title: "What happens at boot",
        prose: "The console requires your file, finds the class, registers the art " \
               "you declared, and then calls `setup`. The input is sampled before " \
               "`setup` runs, so your cart can read the keyboard and the pointer " \
               "from the very first line of it.",
        list: [
          "Your file is required, and the class is found by name.",
          "The sprites and sounds you declared are registered.",
          "The input is sampled, so `setup` can read it.",
          "`setup` runs.",
          "If you declared any scenes, the first one you declared is entered."
        ]
      ),
      Topic.new(
        title: "The frame",
        prose: "The console ticks 60 times a second. Each tick updates the " \
               "schedulers, then either runs your scene or your cart, and then " \
               "draws. The order matters if you are not sure where something " \
               "belongs.",
        list: [
          "`after`, `every`, tweens and animations are advanced.",
          "With no scenes: your `update` runs, then your `render`.",
          "With scenes: the current scene's `update` runs, then its `render`.",
          "With scenes: your `render` runs last, over the top of the scene."
        ]
      ),
      Topic.new(
        title: "Scenes",
        prose: "A scene is a class with `enter`, `update` and `render`. You declare " \
               "one with two arguments and jump to it with one, which is worth " \
               "knowing before you go looking for a `scene` method that only " \
               "declares.",
        code: <<~'RUBY'
          def setup
            scene :title, TitleScene   # declares it
            scene :play, PlayScene
          end

          def update
            goto :play if input.pressed?(:accept)   # jumps to it
          end
        RUBY
      ),
      Topic.new(
        title: "Quirks",
        prose: "The things that are true of the console and not obvious from the " \
               "API reference.",
        list: [
          "The first scene you declare starts by itself. You do not need to `goto` it.",
          "`goto` restarts a scene and runs its `enter` again. `pop_scene` goes back " \
            "without, which is the difference between restarting and resuming.",
          "`scene_data` keeps its values between visits to the same scene.",
          "Your `update` only runs when your cart has no scenes. With scenes, the " \
            "scene's `update` runs instead.",
          "Your `render` runs last, so a HUD that has to sit over a scene belongs there.",
          "`scene :title` with one argument jumps. It takes two to declare.",
          "A `push_scene` overlay pauses `after`, `every` and the tweens as well as " \
            "the entities, so the world really does stop."
        ]
      )
    ].freeze
  end

  # The API index, grouped.
  #
  # Anything the grouping does not name is kept rather than dropped: a module
  # added to the library must not vanish from its documentation because nobody
  # updated this list.
  def groups(modules)
    grouped = CATEGORIES.map do |category|
      category.merge(modules: modules.select { |m| category[:slugs].include?(m.slug) })
    end

    named = CATEGORIES.flat_map { |category| category[:slugs] }
    rest = modules.reject { |m| named.include?(m.slug) }
    grouped << { title: "Other", note: "The rest of the library.", slugs: [],
                 modules: rest } if rest.any?

    grouped.reject { |group| group[:modules].empty? }
  end

  # The samples, in the order a first cart meets them.
  def samples
    @samples ||= [ first_cart, scenes, no_art_yet, moving_and_animating, sound_and_timing ].freeze
  end

  def find(id) = samples.find { |s| s.id == id }

  private
    def first_cart
      Sample.new(
        id: "first-cart",
        title: "The smallest cart that moves",
        note: "One class in one file. Paths are relative to the folder, so " \
              "`sprites/ship.png` means a file inside this cart.",
        file: "carts/mine/app/mine.rb",
        verb: "Create",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            def self.assets
              { sprites: { ship: 'sprites/ship.png' } }
            end

            def setup
              @x = 400.0
            end

            def update
              @x += 4 if input.held?(:right)
              @x -= 4 if input.held?(:left)
            end

            def render
              draw.sprite path: :ship, x: @x, y: 300
            end
          end
        RUBY
      )
    end

    def scenes
      Sample.new(
        id: "scenes",
        title: "Splitting it into scenes",
        note: "A cart with scenes gets `enter`, `update` and `render` for each " \
              "scene, rather than the cart's own `update`. `scene_data` holds " \
              "state for that scene, and it survives leaving it.",
        file: "carts/mine/app/mine.rb",
        verb: "Add to",
        code: <<~'RUBY'
          class Mine
            def setup
              scene :title, TitleScene
              scene :play, PlayScene
              goto :title
            end
          end

          class TitleScene
            def enter
              scene_data[:t] = 0
            end

            def update
              goto :play if input.pressed?(:accept)
            end

            def render
              draw.text 'PRESS SPACE',
                        x: screen[:w] / 2.0, y: screen[:h] / 2.0,
                        anchor_x: 0.5, anchor_y: 0.5,
                        size_px: 32, color: :accent
            end
          end
        RUBY
      )
    end

    def no_art_yet
      Sample.new(
        id: "no-art-yet",
        title: "Playable before any art exists",
        note: "`auto_sprite` makes a texture for any name that has no file, and " \
              "never overwrites one that does. The textures come out the same " \
              "every time, so the same cart looks the same everywhere and can " \
              "stand in for art until you make some.",
        file: "carts/mine/app/mine.rb",
        verb: "Add to",
        code: <<~'RUBY'
          def setup
            auto_sprite :ship, 16, 16, :accent, :frame
            auto_sprite :star, 8, 8, :warn, :circle
          end

          def render
            draw.sprite path: :star, x: 120, y: 200
            draw.sprite path: :ship, x: 260, y: 200
          end
        RUBY
      )
    end

    def moving_and_animating
      Sample.new(
        id: "moving",
        title: "Entities, animation and a camera",
        note: "An entity is a hash you own. `animate` plays a numbered " \
              "directory of frames from the cart's sprites, and the camera " \
              "clamps itself to the world rectangle you give it.",
        file: "carts/mine/app/mine.rb",
        verb: "Add to",
        code: <<~'RUBY'
          WORLD = { x: 0, y: 0, w: 1600, h: 900 }

          def setup
            @ship = spawn :ship, kind: :hero, x: 800, y: 120,
                           w: 28, h: 28, sprite: :ship
            animate @ship, :run, fps: 12
            camera.follow @ship
            camera.bounds = WORLD
          end

          def update
            @ship[:x] += 3 if input.held?(:right)
            @ship[:x] -= 3 if input.held?(:left)
            camera.update
          end

          def render
            draw.sprite path: @ship[:sprite], x: @ship[:x], y: @ship[:y]
          end
        RUBY
      )
    end

    def sound_and_timing
      Sample.new(
        id: "sound",
        title: "Sound, and work that reschedules itself",
        note: "Music is one track; effects are fire-and-forget. `every` runs a " \
              "block every N frames, which is enough for spawners, timers and " \
              "cooldowns without coroutines.",
        file: "carts/mine/app/mine.rb",
        verb: "Add to",
        code: <<~'RUBY'
          def setup
            music :theme
            every 90, immediate: true do
              next_wave
            end
          end

          def update
            sfx :laser if input.pressed?(:accept)
          end

          def next_wave
            spawn :enemy, kind: :foe, x: 800, y: 900, w: 24, h: 24,
                          sprite: :enemy, dx: -1
          end
        RUBY
      )
    end
end
