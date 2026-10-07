require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
  end

  test "an admin sees the overview" do
    sign_in_as @admin

    get admin_root_path

    assert_response :success
    assert_select ".stat", text: /Users/
    assert_select ".stat", text: /Console versions/
  end

  test "a non-admin gets a 404" do
    sign_in_as users(:two)

    get admin_root_path

    assert_response :not_found
  end

  test "an anonymous visitor is sent to sign in" do
    get admin_root_path

    assert_redirected_to new_session_path
  end

  test "it counts cartridges and how many are published" do
    version = ConsoleVersion.create!(version: "0.1.0")
    draft = ingest(space_cart, user: users(:two), console_version: version)
    live = ingest(named_cart("arcade"), user: users(:two), console_version: version)
    live.publish!

    sign_in_as @admin
    get admin_root_path

    assert_response :success
    assert_equal 2, stat("Cartridges")
    assert_equal 1, stat("Published")
    assert_not_nil draft
  end

  test "it says so when no console library is installed" do
    sign_in_as @admin
    get admin_root_path

    assert_response :success
    assert_select ".admin-caution", text: /No console library is installed/
  end

  test "it warns when a version has no library files" do
    # The upload form rejects its own submission when there is no library, so
    # this is the page that has to surface it.
    ConsoleVersion.create!(version: "0.1.0")

    sign_in_as @admin
    get admin_root_path

    assert_response :success
    assert_select ".admin-caution", text: /cannot be served/
    assert_select ".state-bad", text: /no library files/
  end

  test "it says nothing alarming when every version is present" do
    console_version!

    sign_in_as @admin
    get admin_root_path

    assert_response :success
    assert_select ".admin-caution", count: 0
    assert_select ".state-ok"
  end

  private
    # The counts are rendered into the page rather than exposed to the test, so
    # the assertion reads the HTML the same way a visitor would.
    def stat(label)
      node = css_select(".stat").find { |card| card.at_css("dt")&.text.to_s.include?(label) }
      node&.at_css("dd")&.text&.strip&.to_i
    end
end
