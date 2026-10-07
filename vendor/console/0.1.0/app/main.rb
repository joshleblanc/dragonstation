# app/main.rb -- the cartridge console entry point.
#
# DragonRuby requires app/main.rb first and loads nothing else on its own, so
# this file is both the loader and the game loop. Requires are explicit and
# ordered because the library modules reference each other at call time but not
# at load time.
#
# Cart selection, in priority order:
#
#   1. --cart <name>        ./run --cart hello
#   2. CART=<name> env var
#   3. the FIRST cart found in carts/ (so a fresh checkout always runs)
#
# Each cart is a directory: carts/<name>/app/<name>.rb, owning its own sprites,
# sounds, maps and data. Console::Assets is what makes 'sprites/foo.png' mean
# the cart's own file rather than a shared one.
#
# Other switches understood here:
#
#   --list           print the available carts and exit
#   --selftest       run the built-in self test, print a report, exit
#   --hud            start with the debug overlay on
#   --scene <name>   jump straight into a named scene
#   --shot <path>    write a screenshot after a second and exit
#   --ticks <n>      quit after n frames (headless smoke runs)
#
require 'app/console/version.rb'
require 'app/console/str.rb'
require 'app/console/geom.rb'
require 'app/console/palette.rb'
require 'app/console/assets.rb'
require 'app/console/draw.rb'
require 'app/console/input.rb'
require 'app/console/sprites.rb'
require 'app/console/animation.rb'
require 'app/console/audio.rb'
require 'app/console/camera.rb'
require 'app/console/tween.rb'
require 'app/console/scene.rb'
require 'app/console/entity.rb'
require 'app/console/ui.rb'
require 'app/console/map.rb'
require 'app/console/body.rb'
require 'app/console/testing.rb'
require 'app/console/cart_loader.rb'
require 'app/console/core.rb'

module Main
  # DragonRuby calls `boot` once. Resolve the cart and start the console.
  #
  # `$args` is DragonRuby's always-present global for the current frame's args,
  # which is what we need here: `boot` runs before any gameplay state exists.
  def boot
    Console::CartLoader.new($args).run
  end

  # One line per frame: hand everything to the console.
  def tick
    Console.tick args
  end

  def shutdown
    Console.debug 'shutdown'
  end
end