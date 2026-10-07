require "zip"

# Building console libraries in memory and installing them the way the app does.
#
# Libraries live in ActiveStorage now, so a test that needs one installs it
# through ConsoleLibraryInstall rather than writing a directory somewhere. There
# is no scratch directory to redirect and no tree to clean up: ActiveStorage is
# transactional with the database, and the test database is discarded.
module ConsoleLibraryTestHelper
  # The smallest thing ConsoleLibraryInstall will accept: an entry point that
  # requires two modules, both present, and a version.rb naming the version.
  #
  # Built rather than read out of the real console on purpose -- these tests are
  # about which version string and which require list get refused, and copying
  # the real library would make them assert against whatever the console happens
  # to ship this month.
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

  # Install a library the way the upload screen does, and return the version.
  #
  # The same path, so a test that needs a console gets the validation the app
  # applies rather than a hand-built row that could not exist in production.
  def install_console_library(version, extra = {}, title: nil, notes: nil)
    upload = console_library_upload(version, extra)

    ConsoleLibraryInstall.new(archive: upload, title: title, notes: notes).call
  end

  # A library held in memory rather than in the database, for the tests that
  # read one directly -- the documentation extractor above all, which needs a
  # module that will not parse and could not be installed.
  def candidate_library(version, extra = {})
    ConsoleLibrary.new(ConsoleVersion.new(version: version),
      entries: console_library_entries(version, extra))
  end
end

ActiveSupport::TestCase.include ConsoleLibraryTestHelper