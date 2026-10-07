require "test_helper"
require "fileutils"

# Releasing a new console version.
#
# The point of these tests is the *permission*, not the install: the install is
# the same ConsoleLibraryInstall the upload screen runs, and it is already
# tested. What is new here is that a key belonging to an ordinary member is
# refused, and that a version is never overwritten.
#
# Which downloads carry the release script is a question about the bundle, so it
# is asked in downloads_controller_test.rb -- which needs the real library,
# where this needs an empty one.
class Api::ConsoleVersionsControllerTest < ActionDispatch::IntegrationTest
  setup { console_version! }

  test "an admin's key installs a new version" do
    assert_difference -> { ConsoleVersion.count }, 1 do
      post_releases console_archive(version: "0.2.0"), as: admin
    end

    assert_response :created
    body = response.parsed_body

    assert_equal "0.2.0", body["version"]
    assert_equal false, body["default"], "installing must not make it the default"
    assert body["modules"].to_i > 0
    assert ConsoleVersion.find_by!(version: "0.2.0").available?
  end

  # The whole reason the release script is held back from the public download.
  test "an ordinary member's key is refused" do
    assert_no_difference -> { ConsoleVersion.count } do
      post_releases console_archive(version: "0.2.0"), as: users(:one)
    end

    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body["error"]
  end

  test "a missing or wrong key is a 401, not a redirect" do
    post api_console_versions_path, params: { archive: console_archive(version: "0.2.0") }
    assert_response :unauthorized

    post_releases console_archive(version: "0.2.0"), key: "ds_made_up"
    assert_response :unauthorized
  end

  # Installing a version a site already has would be an update, and updates are
  # refused everywhere else in this app too.
  test "a version that is already installed is refused" do
    post_releases console_archive(version: "0.2.0"), as: admin
    assert_response :created

    assert_no_difference -> { ConsoleVersion.count } do
      post_releases console_archive(version: "0.2.0"), as: admin
    end

    assert_response :unprocessable_content
    assert_match(/already installed/i, response.parsed_body["problems"].join)
  end

  test "an archive that is not a console is refused with the reason" do
    post_releases console_archive(version: "0.2.0", main: "require nothing"), as: admin

    assert_response :unprocessable_content
    assert_predicate response.parsed_body["problems"], :present?
  end

  test "a request with no archive says what to send" do
    post api_console_versions_path, headers: bearer(admin_key)

    assert_response :bad_request
    assert_equal "no archive", response.parsed_body["error"]
  end

  test "releasing does not move the default, or pin any cartridge" do
    before_default = ConsoleVersion.default
    cartridge = ingest(space_cart, user: users(:one))

    post_releases console_archive(version: "0.2.0"), as: admin

    assert_equal before_default, ConsoleVersion.default
    assert_equal before_default, cartridge.reload.console_version
  end

  private
    def admin = users(:two).tap { |user| user.update!(admin: true) }

    def console_url = "http://www.example.com"

    def bearer(secret) = { "Authorization" => "Bearer #{secret}" }

    def admin_key = ApiKey.issue!(admin).last

    def post_releases(archive, as: nil, key: nil)
      secret = key || ApiKey.issue!(as).last

      post api_console_versions_path, params: { archive: archive }, headers: bearer(secret)
    end

    # A real console: the library's require list and every module it names, so
    # the install's own checks pass and a failure here means something else.
    def console_archive(version:, main: nil)
      entries = console_library_entries(version)
      entries = entries.merge("app/main.rb" => main) if main

      Rack::Test::UploadedFile.new(StringIO.new(build_archive(entries).read),
        "application/zip", original_filename: "console-#{version}.zip")
    end

    def zip
      Zip::File.open_buffer(StringIO.new(response.body))
    end

    def zip_entries = zip.entries.map(&:name)

    def read_entry(name) = zip.read(name)
end
