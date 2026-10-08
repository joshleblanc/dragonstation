require "test_helper"
require "fileutils"

# The download the console installs itself from.
#
# Two shapes differing by one secret, and the tests are arranged around that:
# the library is public because the site already serves every byte of it to run
# a cart, and the bundle is private because it carries a key that publishes
# carts as its owner.
class DownloadsControllerTest < ActionDispatch::IntegrationTest
  setup { console_version! }

  # One unpacked console is a couple of megabytes; leaving them under tmp/ for
  # every run would be a slow leak rather than a temporary directory.
  teardown { FileUtils.rm_rf(@unpacked.to_s) if @unpacked }

  test "the library downloads without an account, because it is already public" do
    get library_download_path

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/\Aattachment; /, response.headers["Content-Disposition"])
    assert_includes response.headers["Content-Disposition"], "console-#{ConsoleVersion.default.version}.zip"
  end

  test "the library ZIP holds every file the console serves" do
    get library_download_path

    names = zip_entries
    library = ConsoleVersion.default.library

    library.file_paths.each { |path| assert_includes names, path }
    assert_includes names, "app/console/core.rb"
    assert_operator names.size, :>, 15
  end

  # The first version of this shipped only what a browser needs to run a cart,
  # which left whoever unpacked it with a directory of Ruby and nothing to run
  # it with. These are the pieces that make it a console rather than a library.
  test "the download is a whole console, not just a library" do
    get library_download_path

    names = zip_entries

    assert_includes names, "app/main.rb", "no entry point"
    assert_includes names, "bin/run", "no way to boot a cart"
    assert_includes names, "bin/publish-site", "no way to publish one"
    assert_includes names, "bin/update-library", "no way to update the library"
    assert_includes names, "bin/publish-cart"
    assert_includes names, "bin/run-test"
    assert_includes names, "bin/smoke"
    assert_includes names, "carts/README.md", "nowhere to put a cart"
    assert_includes names, "sprites/tiny-star.png", "no starter art"
    assert_includes names, "metadata/game_metadata.txt"
    assert_includes names, "README.md"
  end

  # The Windows half: the shell scripts are no use there, and a console that
  # only ships them is a console half the audience cannot start.
  test "the download carries the Windows scripts too" do
    get library_download_path

    %w[run.bat run-test.bat smoke.bat publish-cart.bat publish-site.bat
       update-library.bat].each do |script|
      assert_includes zip_entries, "bin/#{script}"
    end
  end

  # A console whose scripts arrive non-executable is a console that cannot be
  # run. unzip restores the mode; this is what it reads.
  test "the scripts arrive executable" do
    get library_download_path

    zip.each do |entry|
      next unless entry.name.start_with?("bin/")

      mode = entry.instance_variable_get(:@unix_perms).to_i
      assert_equal 0o755, mode & 0o777, "#{entry.name} is not executable in the download"
    end
  end

  # Machine state, not console: a download should not carry one reader's
  # crash, or another reader's build output.
  test "the download carries no machine state" do
    get library_download_path

    names = zip_entries

    assert_not_includes names, "errors/last.txt"
    assert_not_includes names, "dragonstation.json"
    assert(names.none? { |n| n.start_with?("builds/") || n.start_with?("carts/") && n != "carts/README.md" })
  end

  # What the reader actually unpacks, not what the ZIP promises.
  test "an unpacked download is a console that can run a cart" do
    get library_download_path
    root = unpack_zip

    assert File.executable?(root.join("bin/run").to_s), "bin/run is not executable"
    assert File.exist?(root.join("app/main.rb").to_s)
    assert File.directory?(root.join("carts").to_s)
    assert File.file?(root.join("carts/README.md").to_s)
    assert File.directory?(root.join("sprites").to_s)
    # Every path the site serves has to exist on disk, or a script that reads
    # one gets an error instead of a file.
    LibraryBundle.new(ConsoleVersion.default).release_paths.each do |path|
      assert File.file?(root.join(path).to_s), "#{path} is in the ZIP but not on disk"
    end
  end

  # The library alone must not carry anyone's key. This is the assertion that
  # fails loudly if a credentials file is ever written unconditionally.
  test "the library ZIP carries no credentials" do
    get library_download_path

    assert_not_includes zip_entries, LibraryBundle::CREDENTIALS_PATH
    assert_not_includes response.body, ApiKey::PREFIX
  end

  test "the ZIP's library files are the real bytes" do
    get library_download_path

    assert_includes read_entry("app/console/version.rb"), "MAJOR"
  end

  test "the personal bundle needs an account" do
    get console_bundle_path

    assert_redirected_to new_session_path
  end

  test "the personal bundle carries a working key for its reader" do
    sign_in_as users(:one)

    get console_bundle_path

    assert_response :success
    assert_not_includes response.headers["Cache-Control"], "max-age"

    credentials = JSON.parse(read_entry(LibraryBundle::CREDENTIALS_PATH))
    assert_equal users(:one), ApiKey.authenticate(credentials["api_key"]).user
    assert_equal "#{console_url}/api/carts", credentials["publish_url"]
    assert_equal console_url, credentials["site_url"]
    assert_equal ConsoleVersion.default.version, credentials["console_version"]
  end

  # The whole point of the bundle: the key inside it has to be the key the site
  # accepts, or the console is holding a file that proves nothing.
  test "the key in the bundle is one the publish endpoint accepts" do
    sign_in_as users(:one)
    get console_bundle_path
    key = JSON.parse(read_entry(LibraryBundle::CREDENTIALS_PATH))["api_key"]

    archive = Rack::Test::UploadedFile.new(StringIO.new(build_archive(space_cart).read),
      "application/zip", original_filename: "space.zip")

    post api_carts_path, params: { archive: archive }, headers: bearer(key)

    assert_response :created
    assert_equal users(:one).id, Cartridge.order(:id).last.user_id
  end

  # The secret is never stored, so the download is the only place it exists and
  # each one issues a new key. That is the cost of keeping it out of the
  # database, and it is a cost a reader can see: the old key stops working.
  test "each download issues a fresh key and retires the last one" do
    sign_in_as users(:one)

    get console_bundle_path
    first = JSON.parse(read_entry(LibraryBundle::CREDENTIALS_PATH))["api_key"]

    get console_bundle_path
    second = JSON.parse(read_entry(LibraryBundle::CREDENTIALS_PATH))["api_key"]

    assert_not_equal first, second
    assert_nil ApiKey.authenticate(first)
    assert ApiKey.authenticate(second).present?
  end

  test "one reader's bundle carries a key that is nobody else's" do
    sign_in_as users(:two)

    get console_bundle_path
    key = JSON.parse(read_entry(LibraryBundle::CREDENTIALS_PATH))["api_key"]

    assert_equal users(:two), ApiKey.authenticate(key).user
    assert_not_equal users(:one), ApiKey.authenticate(key).user
  end

  test "the bundle includes the library too, not only the credentials" do
    sign_in_as users(:one)

    get console_bundle_path

    names = zip_entries
    ConsoleVersion.default.library.file_paths.each { |path| assert_includes names, path }
    assert_includes names, LibraryBundle::CREDENTIALS_PATH
  end

  test "there is nothing to download when no library is installed" do
    # destroy_all, not delete_all: a version's files hang off the row now, so
    # deleting the rows outright leaves the files behind and trips the foreign key.
    ConsoleVersion.destroy_all

    get library_download_path
    assert_response :not_found

    sign_in_as users(:one)
    get console_bundle_path
    assert_response :not_found
  end

  private
    def admin = users(:two).tap { |user| user.update!(admin: true) }

    def console_url = "http://www.example.com"

    def bearer(secret) = { "Authorization" => "Bearer #{secret}" }

    # Not memoised: these tests make several requests, and a cached ZIP would
    # silently answer a later question with an earlier response.
    def zip
      Zip::File.open_buffer(StringIO.new(response.body))
    end

    def zip_entries = zip.entries.map(&:name)

    def read_entry(name)
      zip.read(name)
    end

    # The download, unpacked the way a reader would: modes and all.
    def unpack_zip
      root = Rails.root.join("tmp/bundle-test-#{SecureRandom.hex(4)}")
      FileUtils.mkdir_p(root)

      @unpacked ||= begin
        Zip::File.open_buffer(StringIO.new(response.body)) do |archive|
          archive.each do |entry|
            path = root.join(entry.name)
            FileUtils.mkdir_p(path.dirname)
            File.binwrite(path, archive.read(entry.name))
            mode = entry.instance_variable_get(:@unix_perms).to_i & 0o777
            FileUtils.chmod(mode, path) if mode.positive?
          end
        end
        root
      end
    end
end
