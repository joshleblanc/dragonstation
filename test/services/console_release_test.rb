require "test_helper"

class ConsoleReleaseTest < ActiveSupport::TestCase
  test "takes the whole of a release directory" do
    paths = %w[
      app/main.rb app/console/core.rb app/console/version.rb
      bin/run bin/publish-console
      sprites/hero.png
      metadata/README.md
    ]

    assert_equal paths.sort, ConsoleRelease.paths(paths + %w[builds/tmp/out.txt notes.txt])
  end

  test "takes the named files and nothing that is only similar" do
    paths = ConsoleRelease::FILES +
      %w[font.woff README.txt shots/1.png errors/last.txt carts/arcade/app/arcade.rb]

    assert_equal ConsoleRelease::FILES.sort, ConsoleRelease.paths(paths)
  end

  test "keeps the release scripts -- withholding them is the download's decision" do
    # A version stores what a console is, including the tool that releases the
    # next one. LibraryBundle is the thing that decides not to hand it to
    # everybody, and it cannot do that if the install left it out.
    paths = ConsoleRelease::RELEASE_SCRIPTS

    assert_equal paths.sort, ConsoleRelease.paths(paths)
  end

  test "does not descend into a directory that shares a name's prefix" do
    paths = %w[app/main.rb application/x.rb bin/run bins/run]

    assert_equal %w[app/main.rb bin/run], ConsoleRelease.paths(paths)
  end

  test "answers the same from a directory as from a set of paths" do
    Dir.mktmpdir do |dir|
      written = %w[
        app/main.rb app/console/core.rb bin/run sprites/hero.png
        README.md .gitignore errors/readme.txt carts/README.md
      ]
      # The machine's console, not the release: none of this is a version.
      ignored = %w[
        builds/tmp/out.png shots/1.png errors/last.txt dragonstation.json
        assignments.md carts/arcade/app/arcade.rb .git/config
      ]

      (written + ignored).each do |path|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.binwrite(full, "x")
      end

      assert_equal written.sort, ConsoleRelease.paths_on_disk(dir)
    end
  end

  test "names the dotfiles a walk would miss" do
    # Dir.glob's ** never matches a leading dot, so .gitignore and
    # .gitattributes have to be listed to arrive at all.
    assert_includes ConsoleRelease::FILES, ".gitignore"
    assert_includes ConsoleRelease::FILES, ".gitattributes"
  end
end
