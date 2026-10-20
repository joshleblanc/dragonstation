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
    { id: "publishing", title: "Publishing a cart" },
    { id: "primer", title: "Ruby primer" },
    { id: "structure", title: "Cart structure" },
    { id: "reference", title: "API reference" }
  ].freeze

  # What a cart is: a directory, and the contract inside it.
  LAYOUT = {
    tree: <<~TREE,
      carts/mine/
      |-- app/mine.rb      the cart itself: defines class Mine
      |-- sprites/         images; sprites/ship.png is drawn as :ship
      |-- sounds/          sound effects and music
      `-- data/            anything else the cart reads
    TREE
    rule: "Name the class after the folder: `carts/mine` needs a class called " \
          "`Mine` (or `CartMine`). The entry file is `app/mine.rb` or " \
          "`app/main.rb`, and any other `.rb` files in `app/` are loaded too."
  }.freeze

  # The hooks a cart may implement. All of them are optional, which is the
  # point: the loader starts a cart that does nothing but boot.
  #
  # Ordered by when they run, which is the order a reader meets them.
  HOOKS = [
    { name: "self.assets", when: "before boot",
      note: "Declaring the cart's files, under `sprites:`, `sounds:` and `music:`. " \
            "Sounds and music only play if they are declared here. Sprites in " \
            "`sprites/` are found by file name, so list one only to give it a " \
            "shorter name." },
    { name: "self.sprite_library", when: "before boot",
      note: "Declaring sprites on their own: the same as `sprites:` in `assets`." },
    { name: "self.sound_library", when: "before boot",
      note: "Declaring sounds on their own: the same as `sounds:` in `assets`." },
    { name: "setup", when: "once, at boot",
      note: "Setting up the starting state: variables, entities and scenes." },
    { name: "update", when: "every frame",
      note: "Reading input and moving things. Not called once the cart has scenes." },
    { name: "render", when: "every frame, last",
      note: "Drawing. It runs after everything else, including the current " \
            "scene, so it is also the place for a HUD." },
    { name: "enter", when: "when a scene starts",
      note: "Setting up a scene each time it starts. `scene_data` keeps its " \
            "values between visits, so clear it here if the scene should start fresh." },
    { name: "leave", when: "when a scene ends",
      note: "Tidying up after a scene: stopping anything it started, such as music." }
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
    { title: "Input", note: "Keyboard, gamepad and pointer, through one set of actions.",
      slugs: %w[input] },
    { title: "Scenes and entities", note: "The objects in a game, and the states it moves between.",
      slugs: %w[scene entity] },
    { title: "The world", note: "The camera, levels, and the bodies that move through them.",
      slugs: %w[camera map body] },
    { title: "Motion", note: "Tweening, and timers that repeat.",
      slugs: %w[tween] },
    { title: "Sound", note: "Music and sound effects.",
      slugs: %w[audio] },
    { title: "Interface", note: "Widgets, built on the drawing helpers.",
      slugs: %w[ui] },
    { title: "Text", note: "String helpers, since the runtime has no Regexp.",
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
      "Download the console while signed in. The download includes your " \
        "publishing key, in `dragonstation.json`.",
      "Run your cart locally with `./bin/run mine` until you are happy with it.",
      "Check it with `./bin/publish-site mine --dry-run`. This runs the same " \
        "checks as the site without sending anything.",
      "Send it with `./bin/publish-site mine`. It shows up here as a private draft.",
      "Play it here, then publish it from the cart's page."
    ],
    endpoint: [
      "POST /api/carts",
      "Authorization: Bearer <the api_key from dragonstation.json>",
      "archive=<the cart ZIP, as multipart/form-data>",
      "",
      "201 {\"slug\",\"title\",\"status\":\"draft\",\"url\",...}",
      "401 {\"error\":\"unauthorised\"}          an unknown key, or one replaced by a newer download",
      "422 {\"error\":...,\"problems\":[...]}    the archive was rejected; one problem per entry",
      "400 {\"error\":\"no archive\"}             no archive was sent",
      "503 {\"error\":\"no console library ...\"} no console version to pin the cart to"
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
        prose: "Everything after a `#` is a comment, up to the end of the line. " \
               "Comments are ignored when the cart runs, so use them freely to " \
               "explain your code.",
        code: <<~'RUBY'
          # The name this site shows for the cart.
          TITLE = 'mine'

          # A comment can also sit at the end of a line.
          @x = 400.0   # where the ship starts
        RUBY
      ),
      Topic.new(
        title: "Values",
        prose: "You will mostly work with four kinds of value: numbers, strings, " \
               "symbols and booleans. `nil` means no value at all. Only `nil` and " \
               "`false` count as false; everything else, including `0` and the " \
               "empty string, counts as true.",
        code: <<~'RUBY'
          400.0            # a number
          'text'           # a string
          "text #{400}"    # a string with a value inserted
          :right           # a symbol
          true             # a boolean
          nil              # no value at all
        RUBY
      ),
      Topic.new(
        title: "Variables and constants",
        prose: "A name starting with a lowercase letter is a local variable; it " \
               "exists only inside the method where it is written. A name starting " \
               "with an uppercase letter is a constant, and Ruby warns you if you " \
               "assign to it twice. A name starting with `@` is an instance " \
               "variable: it belongs to the cart and keeps its value between frames.",
        code: <<~'RUBY'
          def setup
            @x = 400.0        # an instance variable: it belongs to the cart
            speed = 4         # a local variable: it only exists in this method
          end
        RUBY
      ),
      Topic.new(
        title: "Conditionals",
        prose: "`if` runs code when a condition is true, and `unless` runs it when " \
               "a condition is false. `elsif` adds more cases, and `else` handles " \
               "anything left over.",
        code: <<~'RUBY'
          if input.held?(:right)
            @x += 4
          elsif input.held?(:left)
            @x -= 4
          else
            @speed = 0
          end

          # Either form also works at the end of a single line.
          @lives -= 1 unless @shielded
          @score += 10 if @hit
        RUBY
      ),
      Topic.new(
        title: "Loops",
        prose: "`while` repeats for as long as its condition is true. `each` runs " \
               "once for every item in a collection, and `times` runs a set number " \
               "of times. `break` exits a loop early.",
        code: <<~'RUBY'
          # while: repeat as long as the condition holds
          fuel = 3
          while fuel > 0
            fuel -= 1
          end

          # each: once for every item, which arrives as points
          total = 0
          [10, 20, 30].each do |points|
            total += points
          end

          # times: a fixed number of times, counting from 0
          3.times do |n|
            spawn :enemy, x: 100 + (n * 100), y: 200
          end
        RUBY
      ),
      Topic.new(
        title: "Methods",
        prose: "`def` starts a method and `end` closes it. A method returns the " \
               "value of its last expression, or whatever you pass to `return`. A " \
               "block is a chunk of code passed to a method, written between braces " \
               "or between `do` and `end`. The method decides when the block runs.",
        code: <<~'RUBY'
          def limit_to(value, low, high)
            return low if value < low
            return high if value > high
            value
          end

          def update
            @x = limit_to(@x + 4, 0, 800)
          end

          # A block: every runs the code between do and end once a second.
          def setup
            @seconds = 0
            every 60 do
              @seconds += 1
            end
          end
        RUBY
      ),
      Topic.new(
        title: "Hashes and arrays",
        prose: "An array is an ordered list. A hash is a collection of key-value " \
               "pairs. The console's API uses hashes with symbol keys throughout, " \
               "which is why you will see options like `x:` and `y:` so often.",
        code: <<~'RUBY'
          # An array
          @shots = []
          @shots << { x: 100, y: 200 }   # add to the end
          @shots[0]                      # the first item

          # A hash
          entity = { x: 100, y: 200, sprite: :ship }
          entity[:x]             # 100
          entity[:x] = 150       # change a value
          entity.key?(:y)        # true
          entity.merge(y: 300)   # a copy with y changed; entity is untouched
        RUBY
      ),
      Topic.new(
        title: "Symbols",
        prose: "A symbol is a name written with a leading colon. The API uses " \
               "symbols to name everything: sprites, buttons, colours, actions. " \
               "Symbols are cheaper than strings, and a given symbol is always the " \
               "same object.",
        code: <<~'RUBY'
          input.held?(:right)      # a button
          draw.sprite path: :ship  # a sprite name
          @color = :accent         # a colour
        RUBY
      ),
      Topic.new(
        title: "Classes",
        prose: "Your cart is a class, named after the folder it lives in, and the " \
               "console creates an instance of it at boot. Methods defined inside " \
               "the class are instance methods; these are the hooks the console " \
               "calls. Putting `self.` in front of a method name makes it a class " \
               "method, which is how a cart declares its assets.",
        code: <<~'RUBY'
          class Mine
            # A class method: the console calls it before boot.
            def self.assets
              { sounds: { jump: 'sounds/jump.wav' } }
            end

            # An instance method: a hook the console calls on your cart.
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
        prose: "Before your code runs, the console finds your class, indexes your " \
               "sprites and registers what you declared in `self.assets`. Then it " \
               "calls `setup`, once.",
        list: [
          "Your entry file is loaded, then every other `.rb` file in `app/`.",
          "Your class is found by name, and one instance of it is created.",
          "Every image in `sprites/` is indexed by file name, and the files " \
            "named in `self.assets` are registered.",
          "Input is read once, so `setup` can already check the keyboard and pointer.",
          "`setup` runs.",
          "If `setup` declared any scenes, the first one is entered."
        ]
      ),
      Topic.new(
        title: "The frame",
        prose: "After boot, the console runs 60 frames a second, and every frame " \
               "follows the same steps in the same order. When you are not sure " \
               "where some code belongs, find its step here.",
        list: [
          "Input is read. Every check in this frame sees the same keys.",
          "`after` and `every` timers fire, tweens and animations advance, and " \
            "a camera that is following something moves.",
          "With no scenes: your `update` runs, then your `render`.",
          "With scenes: the current scene's `update` runs, then its `render`, " \
            "then your cart's `render` on top.",
          "A scene change asked for during the frame happens at the end of it."
        ]
      ),
      Topic.new(
        title: "Screen, coordinates and colours",
        prose: "The screen is `screen[:w]` by `screen[:h]` pixels (1280 by 720). " \
               "`x` counts from the left and `y` counts up from the bottom, so " \
               "adding to `y` moves something up. `top(n)` converts a distance " \
               "from the top into a `y`. Colours are named: `:white`, `:black`, " \
               "`:gray`, `:dark`, `:panel`, `:accent`, `:accent2`, `:good`, " \
               "`:warn`, `:bad`, `:text` and `:muted`.",
        code: <<~'RUBY'
          # A 32-pixel square in the bottom-left corner...
          draw.rect x: 0, y: 0, w: 32, h: 32, color: :accent

          # ...and one in the top-right corner.
          draw.rect x: screen[:w] - 32, y: top(32), w: 32, h: 32, color: :bad
        RUBY
      ),
      Topic.new(
        title: "Scenes",
        prose: "A scene is a class with any of `enter`, `update`, `render` and " \
               "`leave`. Declare one by calling `scene` with a name and a class, " \
               "and switch to it with `goto`. Scenes can call everything a cart " \
               "can: `draw`, `input`, `spawn` and the rest.",
        code: <<~'RUBY'
          def setup
            scene :title, TitleScene   # declares a scene
            scene :play, PlayScene
          end

          # Inside TitleScene:
          def update
            goto :play if input.pressed?(:accept)   # switches to it
          end
        RUBY
      ),
      Topic.new(
        title: "Quirks",
        prose: "Things that catch people out, and are hard to spot in the API reference.",
        list: [
          "The first scene you declare starts automatically; you do not need to `goto` it.",
          "Once a cart declares a scene, its own `update` is never called. Put " \
            "game logic in the scenes, and use the cart's `render` for a HUD that " \
            "shows in every scene.",
          "`goto` restarts a scene from scratch: a new instance, so its instance " \
            "variables are gone, and `enter` runs again. Keep anything that should " \
            "survive in `scene_data`, which keeps its values between visits.",
          "`pop_scene` goes back to the scene underneath without calling its " \
            "`enter`, so that scene carries on where it left off.",
          "While a `push_scene` overlay is up, the scene underneath stops updating, " \
            "and `after`, `every`, tweens and animations pause with it.",
          "`scene :title` with one argument switches to that scene, like `goto`. " \
            "Declaring a scene takes two arguments.",
          "Sounds and music are only found if they are declared in `self.assets`. " \
            "Sprites in `sprites/` are found by file name without being declared.",
          "A sprite name that does not resolve does not crash the cart: it draws " \
            "as a plain white box, or not at all if you gave it no size. If a " \
            "sprite is missing, check its file name first."
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
  #
  # Each one is a whole cart rather than a fragment to add: every sample
  # defines `setup`, `update` and `render`, and pasting a second `def setup`
  # into a file silently replaces the first. A complete file is the one thing a
  # reader can copy, run, and trust.
  def samples
    @samples ||= [ first_cart, no_art_yet, scenes, moving_and_animating, sound_and_timing ].freeze
  end

  def find(id) = samples.find { |s| s.id == id }

  private
    def first_cart
      Sample.new(
        id: "first-cart",
        title: "A square you can move",
        note: "`setup` runs once, when the cart starts. `update` runs every frame " \
              "to change things, and `render` runs after it to draw them. " \
              "`input.held?` is true for as long as a direction is held, on the " \
              "arrow keys, WASD or a gamepad. Remember that `y` counts up from " \
              "the bottom of the screen.",
        file: "carts/mine/app/mine.rb",
        verb: "Create",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            SPEED = 4

            def setup
              @x = 600.0
              @y = 340.0
            end

            def update
              @x += SPEED if input.held?(:right)
              @x -= SPEED if input.held?(:left)
              @y += SPEED if input.held?(:up)
              @y -= SPEED if input.held?(:down)
            end

            def render
              draw.rect x: @x, y: @y, w: 32, h: 32, color: :accent
              draw.text 'Arrow keys or WASD to move', x: 20, y: 20, color: :muted
            end
          end
        RUBY
      )
    end

    def no_art_yet
      Sample.new(
        id: "no-art-yet",
        title: "Adding art, or a placeholder for it",
        note: "Any image in the cart's `sprites/` folder can be drawn by its " \
              "file name: `sprites/ship.png` is `:ship`. Until you have art, " \
              "`auto_sprite` generates a placeholder under that name. It never " \
              "replaces a real file, so you can leave the line in: once " \
              "`sprites/ship.png` exists, it is drawn instead. The last argument " \
              "picks a pattern: `:solid`, `:checker`, `:stripes`, `:frame`, " \
              "`:circle` or `:ring`.",
        file: "carts/mine/app/mine.rb",
        verb: "Replace the contents of",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            SPEED = 4

            def setup
              @x = 600.0
              @y = 340.0
              # Stands in for sprites/ship.png until that file exists.
              auto_sprite :ship, 32, 32, :accent, :frame
            end

            def update
              @x += SPEED if input.held?(:right)
              @x -= SPEED if input.held?(:left)
              @y += SPEED if input.held?(:up)
              @y -= SPEED if input.held?(:down)
            end

            def render
              draw.sprite path: :ship, x: @x, y: @y, w: 32, h: 32
              draw.text 'Arrow keys or WASD to move', x: 20, y: 20, color: :muted
            end
          end
        RUBY
      )
    end

    def scenes
      Sample.new(
        id: "scenes",
        title: "A title screen, with scenes",
        note: "Each scene is its own class with `enter`, `update` and `render`. " \
              "The first scene declared starts by itself, and from then on the " \
              "console runs the current scene instead of the cart's own `update`. " \
              "`goto` starts a scene from scratch, which is why `@x` is back in " \
              "the middle on every play. `scene_data` is the one thing a scene " \
              "keeps between visits, so the play count survives.",
        file: "carts/mine/app/mine.rb",
        verb: "Replace the contents of",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            def setup
              scene :title, TitleScene   # declared first, so it starts first
              scene :play, PlayScene
            end
          end

          class TitleScene
            def update
              goto :play if input.pressed?(:accept)   # Space, Enter or gamepad A
            end

            def render
              draw.text 'PRESS SPACE TO START',
                        x: screen[:w] / 2.0, y: screen[:h] / 2.0,
                        anchor_x: 0.5, anchor_y: 0.5,
                        size_px: 32, color: :accent
            end
          end

          class PlayScene
            def enter
              @x = 600.0
              scene_data[:plays] = (scene_data[:plays] || 0) + 1
            end

            def update
              @x += 4 if input.held?(:right)
              @x -= 4 if input.held?(:left)
              goto :title if input.pressed?(:cancel)   # Esc or gamepad B
            end

            def render
              draw.rect x: @x, y: 340, w: 32, h: 32, color: :accent
              draw.text "Play #{scene_data[:plays]}. Esc for the title screen.",
                        x: 20, y: 20, color: :muted
            end
          end
        RUBY
      )
    end

    def moving_and_animating
      Sample.new(
        id: "moving",
        title: "A world bigger than the screen",
        note: "`spawn` creates an entity: a plain hash with `x`, `y`, `w`, `h` " \
              "and a `kind`, here `:hero`. `animate` plays the numbered frames " \
              "in `sprites/hero/run/` (`0.png`, `1.png` and so on), and " \
              "`draw_entity` draws whichever frame is current. With no frames " \
              "yet, it draws the `:hero` placeholder instead. The camera follows " \
              "the hero by itself, but it only moves what is drawn inside " \
              "`camera.apply`. Anything drawn outside it, like the text here, " \
              "stays put on the screen.",
        file: "carts/mine/app/mine.rb",
        verb: "Replace the contents of",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            # Two screens wide. The camera never shows past these edges.
            WORLD = { x: 0, y: 0, w: 2560, h: 720 }

            def setup
              auto_sprite :hero, 32, 32, :accent, :frame
              @hero = spawn :hero, x: 100, y: 200, w: 32, h: 32
              animate @hero, :run, fps: 12
              camera.follow @hero
              camera.bounds = WORLD
            end

            def update
              @hero[:x] += 4 if input.held?(:right)
              @hero[:x] -= 4 if input.held?(:left)
            end

            def render
              camera.apply do
                draw.rect x: 0, y: 0, w: WORLD[:w], h: 200, color: :panel   # the ground
                draw.rect x: 1200, y: 200, w: 64, h: 64, color: :warn       # a crate
                draw_entity @hero
              end

              draw.text 'Walk right to scroll', x: 20, y: 20, color: :muted
            end
          end
        RUBY
      )
    end

    def sound_and_timing
      Sample.new(
        id: "sound",
        title: "Sound, and things that happen on a timer",
        note: "Unlike sprites, sounds have to be declared in `self.assets`: " \
              "`sounds:` for effects and `music:` for tracks. `sfx` plays an " \
              "effect once. `music` loops a track, and calling it with another " \
              "name swaps tracks. `every 90` runs its block every 90 frames (one " \
              "and a half seconds), and `immediate: true` runs it straight away " \
              "too. The site refuses an upload whose code names a file the cart " \
              "does not include, so add `sounds/laser.wav` and `sounds/theme.ogg` " \
              "before you publish.",
        file: "carts/mine/app/mine.rb",
        verb: "Replace the contents of",
        code: <<~'RUBY'
          TITLE = 'mine'

          class Mine
            def self.assets
              { sounds: { laser: 'sounds/laser.wav' },
                music: { theme: 'sounds/theme.ogg' } }
            end

            def setup
              auto_sprite :enemy, 24, 24, :bad, :circle
              music :theme

              # A new enemy at the right edge, every 90 frames.
              every 90, immediate: true do
                spawn :enemy, x: screen[:w], y: rand_int(40, screen[:h] - 64),
                              w: 24, h: 24
              end
            end

            def update
              sfx :laser if input.pressed?(:accept)

              each_entity :enemy do |enemy|
                move enemy, vx: -3
                despawn enemy if enemy[:x] < -24   # gone off the left edge
              end
            end

            def render
              each_entity(:enemy) { |enemy| draw_entity enemy }
              draw.text 'Space to fire', x: 20, y: 20, color: :muted
            end
          end
        RUBY
      )
    end
end
