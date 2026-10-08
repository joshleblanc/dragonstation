require "test_helper"

# Publishing a cart from the console.
#
# The API is a door, not a second upload path: everything it accepts goes
# through CartridgeIngest, so the refusals are the ones the form already makes.
# What these tests watch is the part that is new -- that the key decides whose
# cart it is, that a missing key is a 401 rather than a redirect, and that a
# refusal arrives as something a script can read.
class Api::CartsControllerTest < ActionDispatch::IntegrationTest
  setup { console_version! }

  test "a cart sent with a valid key arrives as a draft under that account" do
    post_carts(space_cart)

    assert_response :created
    body = response.parsed_body

    assert_equal "draft", body["status"]
    assert_equal "space", body["title"]
    assert_equal ConsoleVersion.default.version, body["console_version"]
    assert_equal cartridge_url(body["slug"]), body["url"]

    cartridge = Cartridge.find_by!(slug: body["slug"])
    assert cartridge.draft?
    assert_equal users(:one), cartridge.user
  end

  # The whole reason the key exists.
  test "two people's keys attribute to their own accounts" do
    sign_in_as users(:two)
    post_carts(space_cart, as: users(:two))
    second = Cartridge.order(:id).last

    post_carts(named_cart("mine"), as: users(:one))
    first = Cartridge.order(:id).last

    assert_equal users(:one), first.user
    assert_equal users(:two), second.user
  end

  test "a cart is pinned to the same version a browser upload would get" do
    post_carts(space_cart)

    assert_equal ConsoleVersion.default, Cartridge.order(:id).last.console_version
  end

  test "no key is a 401, not a sign-in redirect" do
    post api_carts_path, params: { archive: archive(space_cart) }

    assert_response :unauthorized
    assert_equal "unauthorised", response.parsed_body["error"]
  end

  test "a key that is not a key is refused" do
    post_carts(space_cart, key: "ds_made_up")

    assert_response :unauthorized
  end

  # A key that has been replaced by a newer download is the failure a reader is
  # most likely to hit, so it has to be a clean 401 rather than a half-written
  # cartridge.
  test "a retired key is refused and creates nothing" do
    _, retired = ApiKey.issue!(users(:one))
    ApiKey.rotate!(users(:one))

    assert_no_difference -> { Cartridge.count } do
      post_carts(space_cart, key: retired)
    end
    assert_response :unauthorized
  end

  test "an archive with no cart in it is refused with the reason" do
    post_carts({ "notes.txt" => "not a cart" })

    assert_response :unprocessable_content
    body = response.parsed_body

    assert_match(/not a cart/i, body["error"])
    assert_kind_of Array, body["problems"]
    assert_predicate body["problems"], :present?
  end

  test "a request with no archive says what to send" do
    post api_carts_path, headers: bearer(ApiKey.issue!(users(:one)).last)

    assert_response :bad_request
    assert_equal "no archive", response.parsed_body["error"]
  end

  test "a title may be sent with the archive" do
    post_carts(space_cart, params: { title: "My Game" })

    assert_response :created
    assert_equal "My Game", response.parsed_body["title"]
  end

  test "nothing is published by sending it" do
    post_carts(space_cart)

    cartridge = Cartridge.find_by!(slug: response.parsed_body["slug"])

    assert cartridge.draft?
    refute cartridge.published?
  end

  test "a draft sent by key is still private to its owner" do
    post_carts(space_cart)
    slug = response.parsed_body["slug"]

    get "/cartridges/#{slug}"
    assert_response :not_found

    sign_in_as users(:one)
    get "/cartridges/#{slug}"
    assert_response :success
  end

  test "publishing is refused when no library is installed" do
    # destroy_all, not delete_all: a version's files hang off the row now, so
    # deleting the rows outright leaves the files behind and trips the foreign key.
    ConsoleVersion.destroy_all

    post_carts(space_cart)

    assert_response :service_unavailable
    assert_no_difference -> { Cartridge.count } do
      post_carts(space_cart)
    end
  end

  private
    def post_carts(entries, as: nil, key: nil, params: {})
      secret = key || ApiKey.issue!(as || users(:one)).last

      post api_carts_path, params: params.merge(archive: archive(entries)), headers: bearer(secret)
    end

    def bearer(secret) = { "Authorization" => "Bearer #{secret}" }

    def archive(entries)
      Rack::Test::UploadedFile.new(StringIO.new(build_archive(entries).read),
        "application/zip", original_filename: "cart.zip")
    end
end
