require "zip"

# Building console libraries in memory, and reading them from somewhere other
# than the repository.
module ConsoleLibraryTestHelper
  # The smallest thing ConsoleLibraryInstall will accept: an entry point that
  # requires two modules, both present, and a version.rb naming the version.
  #
  # Built rather than zipped from vendor/console/0.1.0 on purpose -- these tests
  # are about which version string and which require list get refused, and
  # copying the real library would make them assert against whatever the
  # console happens to ship this month.
  def console_library_entries(version, extra = {})
    major, minor, patch = version.split(".")

    entry = "require 'app/console/version.rb'\nrequire 'app/console/core.rb'\n"

    version_file =
      "module Console\n" \
      "  module Version\n" \
      "    MAJOR = #{major}\n" \
      "    MINOR = #{minor}\n" \
      "    PATCH = #{patch}\n" \
      "  end\n" \
      "end\n"

    {
      "app/main.rb" => entry,
      "app/console/version.rb" => version_file,
      "app/console/core.rb" => "module Console; end\n"
    }.merge(extra)
  end

  def console_library_archive(version, extra = {})
    build_archive(console_library_entries(version, extra))
  end

  # A real uploaded file, because the controller reads
  # params[:console_library_install][:archive] and a StringIO does not survive a
  # multipart round trip. Cleaned up by cleanup_uploads.
  def console_library_upload(version, extra = {})
    path = Rails.root.join("tmp", "console-library-#{SecureRandom.hex(6)}.zip")
    File.binwrite(path, console_library_archive(version, extra).string)
    uploads << path
    Rack::Test::UploadedFile.new(path, "application/zip")
  end

  def uploads = @uploads ||= []

  def cleanup_uploads
    @uploads&.each { |path| FileUtils.rm_f(path) }
    @uploads = []
  end

  # Point ConsoleLibrary at a directory other than vendor/console.
  #
  # Without this an install test would write a real version directory into the
  # repository and leave it there, which is both a dirty tree and a test that
  # passes for the wrong reason the second time.
  def with_library_root(root)
    original = redirect_library_root(root)
    yield
  ensure
    restore_library_root(original)
  end

  # The pair to use from setup/teardown, where the redirect has to hold for
  # every test rather than for the body of a block. Getting this wrong writes
  # into the repository, so it is the default for any test that installs.
  def redirect_library_root(root)
    original = ConsoleLibrary.method(:root)
    ConsoleLibrary.define_singleton_method(:root) { Pathname.new(root) }
    forget_memoized_libraries
    original
  end

  def restore_library_root(original)
    ConsoleLibrary.define_singleton_method(:root, original)
    forget_memoized_libraries
  end

  # ConsoleVersion memoizes its library, so a row loaded before the root was
  # swapped would keep reading the real vendor directory.
  def forget_memoized_libraries
    ConsoleVersion.all.each { |version| version.instance_variable_set(:@library, nil) }
  end

  # The version directories under a root, ignoring anything an install left
  # behind mid-flight.
  def installed_versions(root)
    Dir.children(root).reject { |name| name.start_with?(".") }.sort
  end
end

ActiveSupport::TestCase.include ConsoleLibraryTestHelper
