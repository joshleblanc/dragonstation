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

  # The state a redeploy leaves behind when the blobs still name a service this
  # process cannot fetch them from: every console_library_files row in place, and
  # none of the bytes behind them. Changing ACTIVE_STORAGE_SERVICE and coming up
  # on a fresh container produces exactly this, which is what
  # lib/tasks/active_storage.rake exists to move across.
  #
  # Deleting the objects rather than the rows is the whole point. A row with no
  # files at all is a different state, one the app has always reported as "no
  # library files", and testing against that instead is how the two got confused:
  # they look the same in the database and nothing alike in production.
  #
  # Reloaded, because ConsoleVersion#library memoizes and a test holding the
  # version across this call would otherwise keep reading the library as it was.
  def lose_the_blobs!(console_version)
    console_version.console_library_files.each do |file|
      file.blob.service.delete(file.blob.key)
    end

    console_version.reload
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
