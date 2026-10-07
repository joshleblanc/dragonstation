require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "issuing a key returns a secret that is never stored" do
    key, secret = ApiKey.issue!(@user)

    assert secret.start_with?(ApiKey::PREFIX)
    assert key.user == @user
    assert key.digest.present?
    assert_not_equal secret, key.digest
    # Nothing anywhere in the row is the secret itself.
    assert_not_includes key.attributes.values.map(&:to_s), secret
  end

  test "the secret authenticates, and what matches is its digest" do
    _, secret = ApiKey.issue!(@user)
    key = ApiKey.authenticate(secret)

    assert_equal @user, key.user
    assert_equal ApiKey.digest(secret), key.digest
  end

  test "a wrong or missing secret is not a key" do
    ApiKey.issue!(@user)

    assert_nil ApiKey.authenticate("ds_nope")
    assert_nil ApiKey.authenticate("")
    assert_nil ApiKey.authenticate(nil)
  end

  test "a blank Authorization header does not find a key" do
    _, secret = ApiKey.issue!(@user)

    assert_nil ApiKey.from_authorization(nil)
    assert_nil ApiKey.from_authorization("")
    assert_nil ApiKey.from_authorization(secret)         # no scheme
    assert_nil ApiKey.from_authorization("Basic #{secret}")
    assert_nil ApiKey.from_authorization("Bearer")
    assert_nil ApiKey.from_authorization("Bearer ")
  end

  test "a Bearer header authenticates, whatever the case of the scheme" do
    _, secret = ApiKey.issue!(@user)

    assert_equal @user, ApiKey.from_authorization("Bearer #{secret}").user
    assert_equal @user, ApiKey.from_authorization("bearer #{secret}").user
  end

  test "using a key stamps when it was last used" do
    # Read the record from issue!, not from authenticate -- authenticating is
    # what stamps it, so asking the same call twice would prove nothing.
    key, secret = ApiKey.issue!(@user)

    assert_nil key.last_used_at

    assert ApiKey.authenticate(secret).last_used_at.present?
  end

  # One key per account: a new one retires the old, which is also how a leaked
  # key is killed.
  test "issuing a new key retires the previous one" do
    _, first = ApiKey.issue!(@user)

    assert ApiKey.authenticate(first).present?

    _, second = ApiKey.issue!(@user)

    assert_nil ApiKey.authenticate(first)
    assert_equal @user, ApiKey.authenticate(second).user
    assert_equal 1, ApiKey.where(user: @user).count
  end

  test "rotating keeps the same account and returns the new secret" do
    _, old_secret = ApiKey.issue!(@user)

    key, new_secret = ApiKey.rotate!(@user)

    assert_equal @user, key.user
    assert_not_equal old_secret, new_secret
    assert_nil ApiKey.authenticate(old_secret)
    assert ApiKey.authenticate(new_secret).present?
  end

  test "the prefix identifies a key without being one" do
    key, secret = ApiKey.issue!(@user)

    assert_equal secret.first(ApiKey::DISPLAY_LENGTH), key.prefix
    assert key.display.end_with?("...")
    assert_operator key.display.length, :<, secret.length
  end

  test "a key does not outlive its account" do
    ApiKey.issue!(users(:two))
    user = users(:two)

    assert_difference -> { ApiKey.count }, -1 do
      user.destroy
    end
  end
end
