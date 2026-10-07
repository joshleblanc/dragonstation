# The written half of the documentation: what a cart is, and how to start one.
#
# ConsoleDocumentation reads the library's own comments, which describe the
# modules. This is the part that cannot be extracted, because it is about
# *using* the library rather than what is inside it -- the shape of a cart, the
# hooks it implements, and a worked example of each thing a first cart needs.
#
# Every call in these samples was checked against the library before it was
# written, and there is a test that keeps them valid Ruby. What that cannot
# check is intent, so the samples are deliberately small: each one is the
# smallest thing that does the job, and the API reference is one click away for
# everything else.
class ConsoleGuide
  # A worked example: what it is for, and the code.
  Sample = Struct.new(:title, :note, :code, :id, keyword_init: true)

  # The hooks a cart may implement. All of them are optional, which is the
  # point: the loader starts a cart that does nothing but boot.
  HOOKS = [
    { name: "self.assets", when: "before boot",
      note: "Names the art the cart owns. Declaring it is what lets the site " \
            "check the cart at upload time and tell you a sprite is missing " \
            "before anyone plays it." },
    { name: "setup", when: "once, at boot",
      note: "Build your state here: spawn things, load a level, start music." },
    { name: "update", when: "every frame",
      note: "Move, read input, advance timers. Only used when the cart defines " \
            "no scenes." },
    { name: "render", when: "every frame, last",
      note: "Draws after whichever scene drew, so it is where a HUD that " \
            "persists across scenes belongs." }
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
      "Build a cart. ./run --cart arcade boots it locally.",
      "Send it: ./publish-site arcade. It arrives here as a draft under your account.",
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
        note: "A cart is one class in one file, named after the directory it " \
              "lives in: `carts/mine/app/mine.rb` defines `Mine`. Paths are " \
              "relative to that directory, so `sprites/ship.png` means this " \
              "cart's own file.",
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
        note: "A cart with scenes gets `enter`, `update` and `render` per " \
              "scene instead of the cart's own `update`. `scene_data` is " \
              "per-scene state that survives scene changes.",
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
        note: "`auto_sprite` synthesises a texture for any name that has no " \
              "file, and never overwrites one that does. Generated textures " \
              "are deterministic, so the same cart looks the same everywhere " \
              "and can stand in for art later.",
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
              "clamps itself to the world rectangle it is given.",
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
              "block every N frames, which covers spawners, timers and " \
              "cooldowns without coroutines.",
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
