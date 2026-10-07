require "test_helper"

class ConsoleLibraryInstallTest < ActiveSupport::TestCase
  # ConsoleLibrary is redirected for every test in this class rather than inside
  # a block in the two that need it. An install writes real files, and a single
  # test that forgets the redirect leaves a version directory in the repository
  # where the next test can adopt it -- so the redirect is the default here and
  # has to be undone deliberately.
  setup do
    @root = Dir.mktmpdir
    @original_library_root = redirect_library_root(@root)
  end

  teardown do
    restore_library_root(@original_library_root)
    FileUtils.rm_rf(@root)
  end

  test "installs a library and registers the version" do
    version = install("0.2.0")

    assert_equal "0.2.0", version.version
    assert_equal "Console 0.2.0", version.title
    assert version.available?
    assert_includes ConsoleVersion.pluck(:version), "0.2.0"
  end

  test "writes the library files where the runtime will look for them" do
    install("0.2.0")

    assert_equal [ "0.2.0" ], installed_versions(@root)
    assert File.file?(File.join(@root, "0.2.0", "app", "main.rb"))
    assert File.file?(File.join(@root, "0.2.0", "app", "console", "core.rb"))
    assert File.file?(File.join(@root, "0.2.0", "app", "console", "version.rb"))
  end

  test "leaves no staging directory behind" do
    install("0.2.0")

    # A refused install cleans up after itself, or the next `console:install`
    # would walk into a half-written library.
    entries = console_library_entries("0.3.0")
    entries.delete("app/console/core.rb")
    assert_rejected build_archive(entries)

    assert_equal [ "0.2.0" ], installed_versions(@root)
    assert_empty Dir.children(@root).grep(/\A\.incoming/)
  end

  test "takes the title and notes it was given" do
    version = ConsoleLibraryInstall.new(
      archive: console_library_archive("0.2.0"),
      title: "Console nightly", notes: "faster tweens"
    ).call

    assert_equal "Console nightly", version.title
    assert_equal "faster tweens", version.notes
  end

  test "accepts a library wrapped in its own directory" do
    version = install("0.2.0", prefix: "console-0.2.0")

    assert_equal "0.2.0", version.version
    assert version.available?
  end

  test "installs under the version in version.rb, not the archive's folder name" do
    # The directory name is packaging; version.rb is the identity. An archive
    # that says it is 0.2.0 while sitting in a folder called release-candidate
    # is installed as 0.2.0, and its cartridges are pinned to "0.2.0".
    version = install("0.2.0", prefix: "release-candidate")

    assert_equal "0.2.0", version.version
    assert_equal [ "0.2.0" ], installed_versions(@root)
  end

  # --- the rule that makes this an install, not an update ---------------

  test "refuses to overwrite an installed version" do
    install("0.2.0")

    changed = console_library_entries("0.2.0", "app/console/core.rb" => "module Console; CHANGED = true; end\n")
    error = assert_rejected build_archive(changed)

    assert_match(/already installed/, error.message)
    assert_match(/never replaced/, error.message)

    # The installed copy is untouched. This is the whole point: a cartridge
    # pinned to 0.2.0 must keep running the bytes it was pinned to.
    assert_equal "module Console; end\n", File.read(File.join(@root, "0.2.0", "app", "console", "core.rb"))
  end

  test "refuses when the version has a row but no directory" do
    # A row can outlive its files. Treating the row as occupied is what stops a
    # re-upload from silently becoming an update.
    ConsoleVersion.create!(version: "0.2.0")

    error = assert_rejected console_library_archive("0.2.0")

    assert_match(/already installed/, error.message)
  end

  test "refuses when the directory exists but has no row" do
    FileUtils.mkdir_p(File.join(@root, "0.2.0"))

    error = assert_rejected console_library_archive("0.2.0")

    assert_match(%r{already exists}, error.message)
    assert_empty ConsoleVersion.all
  end

  test "installs a new version alongside one that is already in use" do
    old = install("0.2.0")
    cartridge = ingest(space_cart, user: users(:one), console_version: old)

    fresh = install("0.3.0")

    # 0.2.0 stays exactly as it was, and nothing pinned to it moves.
    assert_equal old, cartridge.reload.console_version
    assert_not_equal old, fresh
    assert_equal %w[0.2.0 0.3.0], installed_versions(@root)
  end

  # --- what may go into the served tree ---------------------------------

  test "refuses a require of a module the archive does not contain" do
    # The failure this prevents is not an upload error but a cartridge that
    # boots and then dies on a missing module.
    entries = console_library_entries("0.2.0")
    entries["app/main.rb"] =
      "require 'app/console/version.rb'\nrequire 'app/console/absent.rb'\n"

    error = assert_rejected build_archive(entries)

    assert_match(%r{requires app/console/absent\.rb}, error.message)
    assert_match(/missing from the library/, error.message)
  end

  test "refuses a require of a non-ruby file, because the require list is served" do
    # CartridgeRuntimeController serves whatever app/main.rb requires, with a
    # content type guessed from the extension. A .html under app/console/ would
    # therefore be served as text/html from this origin, to every cartridge
    # pinned to the version. This is the guard against that.
    error = assert_rejected(
      console_library_archive("0.2.0",
        "app/main.rb" => "require 'app/console/payload.html'\n",
        "app/console/payload.html" => "<script>alert(1)</script>")
    )

    assert_match(%r{Only \.rb modules directly under app/console/}, error.message)
  end

  test "refuses a require that climbs out of app/console" do
    # ConsoleLibrary::REQUIRE_PATTERN only matches app/console/, so this require
    # would be silently ignored -- installed as though it were fine, and then
    # missing from every cartridge's served tree.
    error = assert_rejected(
      console_library_archive("0.2.0",
        "app/main.rb" => "require 'app/secrets.rb'\n",
        "app/secrets.rb" => "module Secrets; end\n")
    )

    assert_match(%r{requires app/secrets\.rb, which is not under app/console/}, error.message)
    assert_match(/would fail to boot/, error.message)
  end

  test "refuses an archive with no main.rb" do
    error = assert_rejected build_archive("app/console/version.rb" => "VERSION = 1\n")

    assert_match(%r{no app/main\.rb}, error.message)
  end

  test "refuses an archive with no modules" do
    error = assert_rejected(
      console_library_archive("0.2.0", "app/main.rb" => "# nothing required\n")
    )

    assert_match(%r{requires nothing under app/console/}, error.message)
  end

  # --- the version itself ----------------------------------------------

  test "refuses an archive with no readable version.rb" do
    error = assert_rejected console_library_archive("0.2.0", "app/console/version.rb" => "# no constants here\n")

    assert_match(/version\.rb is missing or has no MAJOR\/MINOR\/PATCH/, error.message)
  end

  test "refuses a version.rb that does not yield three numbers" do
    # MAJOR/MINOR/PATCH are joined into the directory name, so two of three
    # gives "0.2" -- which ConsoleVersion would reject on the row, after the
    # files were already written. Refused before anything moves instead.
    error = assert_rejected console_library_archive("0.2.0", "app/console/version.rb" => <<~RUBY)
      module Console
        module Version
          MAJOR = 0
          MINOR = 2
        end
      end
    RUBY

    assert_match(/not a version I can use/, error.message)
  end

  test "refuses a version.rb with no MAJOR at all" do
    error = assert_rejected console_library_archive("0.2.0", "app/console/version.rb" => "STRING = '0.2.0'\n")

    assert_match(/version\.rb is missing or has no MAJOR\/MINOR\/PATCH/, error.message)
  end

  # --- archive safety, inherited rather than re-implemented ------------

  test "refuses an archive whose path escapes the library" do
    entries = console_library_entries("0.2.0")
    entries["app/console/../../../etc/passwd"] = "root"

    assert_rejected build_archive(entries), /escapes the console library/
  end

  test "refuses an archive holding more than one library" do
    error = assert_rejected build_archive(
      console_library_entries("0.2.0").to_h { |path, bytes| [ "one/#{path}", bytes ] }
        .merge(console_library_entries("0.3.0").to_h { |path, bytes| [ "two/#{path}", bytes ] })
    )

    assert_match(/more than one console library/, error.message)
  end

  test "refuses an archive with nothing that looks like a library" do
    assert_rejected build_archive("notes.txt" => "hello"), /no console library found/
  end

  test "refuses an empty archive" do
    assert_rejected build_archive({}), /empty/
  end

  private
    def install(version, prefix: nil)
      entries = console_library_entries(version)
      entries = entries.to_h { |path, bytes| [ prefix ? "#{prefix}/#{path}" : path, bytes ] } if prefix

      ConsoleLibraryInstall.new(archive: build_archive(entries)).call
    end

    def assert_rejected(archive, matching = nil)
      error = assert_raises(ConsoleLibraryInstall::Invalid) do
        ConsoleLibraryInstall.new(archive: archive).call
      end
      assert_match matching, error.message if matching
      error
    end
end
