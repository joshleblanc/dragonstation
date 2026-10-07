require "test_helper"

# Where a reader gets their key.
#
# The page has one job it cannot get wrong: a key is shown once. Everything else
# on it is navigation.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { console_version! }

  test "settings need an account" do
    get settings_path

    assert_redirected_to new_session_path
  end

  test "an account with no key is told how to get one" do
    sign_in_as users(:one)

    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
    assert_match(/no key yet/i, response.body)
  end

  # The prefix identifies a key in a list; the secret must never be on the page
  # again, because the page is the one place it was shown.
  test "an existing key is shown by its prefix, never in full" do
    sign_in_as users(:one)
    _, secret = ApiKey.issue!(users(:one))

    get settings_path

    assert_response :success
    assert_match(/#{Regexp.escape(secret.first(ApiKey::DISPLAY_LENGTH))}/, response.body)
    assert_not_includes response.body, secret
  end

  test "issuing a key shows it, once" do
    sign_in_as users(:one)

    post settings_api_key_path

    assert_response :success
    assert_select ".key-value", /ds_/
    assert_match(/only time it will be shown/i, response.body)
  end

  test "the revealed key is the one the site accepts" do
    sign_in_as users(:one)

    post settings_api_key_path
    revealed = revealed_key

    assert ApiKey.authenticate(revealed).present?
    assert_equal users(:one), ApiKey.authenticate(revealed).user
  end

  # The secret is in the response and nowhere after it -- not in the flash,
  # which would write it to a cookie.
  test "the revealed key is not kept in the session" do
    sign_in_as users(:one)

    post settings_api_key_path
    revealed = revealed_key

    # A later visit shows the prefix, never the key.
    get settings_path
    assert_no_match(/#{Regexp.escape(revealed)}/, response.body)
  end

  test "issuing a key retires the previous one" do
    sign_in_as users(:one)
    _, old_secret = ApiKey.issue!(users(:one))

    post settings_api_key_path
    new_secret = revealed_key

    assert_not_equal old_secret, new_secret
    assert_nil ApiKey.authenticate(old_secret)
  end

  # Integration tests have no view context to ask, so the revealed key is read
  # out of the response the way a browser would.
  def revealed_key
    response.body[/class="key-value">([^<]+)</, 1].to_s.strip
  end

  # A download is a GET, so it has to be a link. button_to renders a form that
  # POSTs, which matches no route -- a 404 the reader sees as a routing error,
  # and one that asserting "the button is there" would never catch.
  test "the console download is a link that fetches, not a form that posts" do
    sign_in_as users(:one)

    get settings_path

    assert_select "a[href=?]", console_bundle_path
    assert_select "form[action=?]", console_bundle_path, count: 0

    get console_bundle_path
    assert_response :success
  end

  test "the plain library is on the page too" do
    sign_in_as users(:one)

    get settings_path

    assert_select "a[href=?]", library_download_path
  end
end
