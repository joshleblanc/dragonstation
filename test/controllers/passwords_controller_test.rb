require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_alert "reset link is invalid"
  end

  test "update" do
    # Long enough to satisfy the minimum length. The policy is deliberately the
    # same as at sign-up, so a reset cannot be used to end up with a weaker
    # password than a new account would have.
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token),
        params: { password: "a-longer-secret", password_confirmation: "a-longer-secret" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    # Both long enough, so this exercises the confirmation check and not the
    # length check.
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token),
        params: { password: "a-longer-secret", password_confirmation: "a-different-one" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_alert "Passwords did not match"
  end

  test "update refuses a password shorter than the minimum" do
    token = @user.password_reset_token

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "short" }
      assert_redirected_to edit_password_path(token)
    end
  end

  private
    # The layout renders flash, so notices and alerts have one home and one
    # pair of classes rather than per-view inline styling. They are separate
    # assertions on purpose: the controller chose alert over notice in a few
    # places, and a matcher loose enough to accept either would hide that.
    def assert_notice(text)
      assert_select ".flash-notice", /#{text}/
    end

    def assert_alert(text)
      assert_select ".flash-alert", /#{text}/
    end
end
