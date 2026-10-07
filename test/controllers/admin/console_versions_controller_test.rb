require "test_helper"

class Admin::ConsoleVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @root = Dir.mktmpdir
    @original_library_root = redirect_library_root(@root)
    @admin = users(:one)
    @admin.update!(admin: true)
  end

  teardown do
    cleanup_uploads
    restore_library_root(@original_library_root)
    FileUtils.rm_rf(@root)
  end

  # --- who gets in -----------------------------------------------------

  test "a signed-in admin reaches the index" do
    sign_in_as @admin

    get admin_console_versions_path

    assert_response :success
  end

  test "a signed-in non-admin gets nothing, not even a redirect" do
    sign_in_as users(:two)

    get admin_console_versions_path

    # A 404 rather than a redirect: an admin URL that answers differently for a
    # stranger is an admin URL that can be written down.
    assert_response :not_found
  end

  test "an anonymous visitor is sent to sign in" do
    get admin_console_versions_path

    assert_redirected_to new_session_path
  end

  test "every admin action is closed to a non-admin" do
    sign_in_as users(:two)
    version = ConsoleVersion.create!(version: "0.1.0")

    get new_admin_console_version_path
    assert_response :not_found

    get admin_console_version_path(version)
    assert_response :not_found

    patch default_admin_console_version_path(version), params: { state: "default" }
    assert_response :not_found
  end

  # --- reading ---------------------------------------------------------

  test "the index lists a version with its state" do
    ConsoleVersion.create!(version: "0.1.0", title: "Console 0.1.0")

    sign_in_as @admin
    get admin_console_versions_path

    assert_response :success
    assert_select "td", text: /0\.1\.0/
  end

  test "the index says so when nothing is installed" do
    sign_in_as @admin
    get admin_console_versions_path

    assert_response :success
    assert_select "td", text: /Nothing installed/
  end

  test "a version whose directory is missing renders rather than raising" do
    # A row can outlive its files, and an admin page that raised on one would be
    # useless exactly when it is needed.
    ConsoleVersion.create!(version: "9.9.9")

    sign_in_as @admin
    get admin_console_version_path(ConsoleVersion.find_by!(version: "9.9.9"))

    assert_response :success
    assert_select ".state-bad", text: /missing directory/
  end

  test "the version page survives a library that lost a file" do
    # main.rb still names it, so the require list is intact and the directory is
    # not gone -- but the bytes are. A page that raised here would be useless
    # exactly when it is needed.
    version = installed_version!("0.1.0")
    FileUtils.rm(File.join(@root, "0.1.0", "app", "console", "core.rb"))

    sign_in_as @admin
    get admin_console_version_path(version)

    assert_response :success
    assert_select "td", text: "missing"
  end

  test "the version page lists the cartridges pinned to it" do
    version = installed_version!("0.1.0")
    cartridge = ingest(space_cart, user: users(:two), console_version: version)

    sign_in_as @admin
    get admin_console_version_path(version)

    assert_response :success
    assert_select "td", text: /#{Regexp.escape(cartridge.title)}/
  end

  # --- installing ------------------------------------------------------

  test "an admin can upload a console library" do
    sign_in_as @admin

    post admin_console_versions_path,
      params: { console_library_install: { archive: console_library_upload("0.2.0") } }

    version = ConsoleVersion.find_by!(version: "0.2.0")
    assert_redirected_to admin_console_version_path(version)
    assert version.available?
    assert_equal "Console 0.2.0", version.title
  end

  test "an uploaded library is not made the default" do
    # Making it default is a separate, deliberate act. Doing it here would mean
    # the next upload silently changed version.
    sign_in_as @admin

    post admin_console_versions_path,
      params: { console_library_install: { archive: console_library_upload("0.2.0") } }

    refute ConsoleVersion.find_by!(version: "0.2.0").default?
  end

  test "an upload cannot replace an installed version" do
    installed_version!("0.1.0")

    sign_in_as @admin
    post admin_console_versions_path,
      params: { console_library_install: { archive: console_library_upload("0.1.0") } }

    assert_response :unprocessable_content
    assert_match(/already installed/, response.body)
  end

  test "an upload does not move a cartridge that is already pinned" do
    version = installed_version!("0.1.0")
    cartridge = ingest(space_cart, user: users(:two), console_version: version)

    sign_in_as @admin
    post admin_console_versions_path,
      params: { console_library_install: { archive: console_library_upload("0.2.0") } }

    assert_equal version, cartridge.reload.console_version
  end

  test "a refused upload re-renders the form with the reasons" do
    sign_in_as @admin

    post admin_console_versions_path,
      params: {
        console_library_install: {
          archive: console_library_upload("0.2.0",
            "app/main.rb" => "require 'app/console/payload.html'\n",
            "app/console/payload.html" => "<script>alert(1)</script>")
        }
      }

    assert_response :unprocessable_content
    assert_match(/Only \.rb modules directly under app\/console\//, response.body)
    assert_empty ConsoleVersion.all
  end

  test "an upload with no file is refused" do
    sign_in_as @admin

    post admin_console_versions_path, params: { console_library_install: { archive: "" } }

    assert_redirected_to new_admin_console_version_path
    assert_empty ConsoleVersion.all
  end

  # --- the default flag ------------------------------------------------

  test "making a version the default clears the flag everywhere else" do
    first = installed_version!("0.1.0")
    second = installed_version!("0.2.0")

    sign_in_as @admin
    patch default_admin_console_version_path(second), params: { state: "default" }

    assert_redirected_to admin_console_version_path(second)
    refute first.reload.default?
    assert second.reload.default?
  end

  test "removing the default flag leaves it to the newest version" do
    version = installed_version!("0.1.0")

    sign_in_as @admin
    patch default_admin_console_version_path(version), params: { state: "not_default" }

    refute version.reload.default?
    # No flag set, so a new upload still gets something to build against.
    assert_equal version, ConsoleVersion.default
  end

  private
    def installed_version!(version)
      entries = console_library_entries(version)
      FileUtils.mkdir_p(File.join(@root, version, "app", "console"))
      entries.each do |path, bytes|
        File.binwrite(File.join(@root, version, path), bytes)
      end
      ConsoleVersion.create!(version: version, title: "Console #{version}")
    end
end
