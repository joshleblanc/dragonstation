require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  VALID = {
    username: "newcomer",
    email_address: "newcomer@example.com",
    password: "correct horse battery",
    password_confirmation: "correct horse battery"
  }.freeze

  test "new renders the form" do
    get new_registration_path

    assert_response :success
    assert_select "input[name='registration[username]']"
    assert_select "input[name='registration[email_address]']"
    assert_select "input[name='registration[password]']"
    assert_select "input[name='registration[password_confirmation]']"
  end

  test "creating an account signs the new user in" do
    assert_difference "User.count", 1 do
      post registration_path, params: { registration: VALID }
    end

    user = User.find_by!(email_address: VALID[:email_address])

    assert_redirected_to root_path
    assert cookies[:session_id]
    # Current is reset between integration requests, so the durable evidence
    # that they are signed in is the session the cookie points at.
    assert_equal user, Session.order(:id).last.user
  end

  test "the first account on a fresh install becomes an admin" do
    # No admin exists yet, so whoever registers first is the operator --
    # otherwise every admin screen is behind a login nobody can make.
    User.delete_all

    post registration_path, params: { registration: VALID }

    assert User.find_by!(email_address: VALID[:email_address]).admin?
  end

  test "later accounts are not admins" do
    User.delete_all

    post registration_path, params: { registration: VALID }
    assert User.find_by!(email_address: VALID[:email_address]).reload.admin?

    post registration_path, params: {
      registration: VALID.merge(username: "second", email_address: "second@example.com")
    }

    assert_not User.find_by!(email_address: "second@example.com").reload.admin?
  end

  test "an existing admin is left alone when someone else registers" do
    operator = User.create!(
      username: "operator", email_address: "operator@example.com",
      password: "correct horse battery", admin: true
    )

    post registration_path, params: { registration: VALID }

    assert_not User.find_by!(email_address: VALID[:email_address]).admin?
    assert operator.reload.admin?, "an existing admin lost admin to a later signup"
  end

  test "rejects a mismatched password confirmation" do
    # Without this the typed confirmation is ignored and the first field wins,
    # which is its own kind of lockout: the password is not the one they think.
    assert_no_difference "User.count" do
      post registration_path, params: {
        registration: VALID.merge(password_confirmation: "something else entirely")
      }
    end

    assert_response :unprocessable_content
    assert_select ".form-errors"
    assert_nil cookies[:session_id]
  end

  test "rejects a short password" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        registration: VALID.merge(password: "short", password_confirmation: "short")
      }
    end

    assert_response :unprocessable_content
  end

  test "rejects a username that is already taken" do
    assert_no_difference "User.count" do
      post registration_path, params: { registration: VALID.merge(username: users(:one).username) }
    end

    assert_response :unprocessable_content
  end

  test "rejects an email that is already taken" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        registration: VALID.merge(email_address: users(:one).email_address)
      }
    end

    assert_response :unprocessable_content
  end

  test "rejects a username that is not a valid constant-safe handle" do
    assert_no_difference "User.count" do
      post registration_path, params: { registration: VALID.merge(username: "not a name!") }
    end

    assert_response :unprocessable_content
  end

  test "normalises the username before storing it" do
    post registration_path, params: { registration: VALID.merge(username: "@MixedCase") }

    assert_equal "mixedcase", User.find_by!(email_address: VALID[:email_address]).username
  end

  test "normalises the email address before storing it" do
    post registration_path, params: {
      registration: VALID.merge(email_address: "  Newcomer@Example.COM ")
    }

    assert_equal "newcomer@example.com", User.find_by!(email_address: "newcomer@example.com").email_address
  end

  test "re-renders with the username and email kept, and the password not" do
    post registration_path, params: {
      registration: VALID.merge(password_confirmation: "mismatch")
    }

    assert_response :unprocessable_content
    assert_select "input[value='newcomer']"
    assert_select "input[value='newcomer@example.com']"
    # A password never comes back into the form.
    assert_select "input[type=password][value=?]", /\S/, count: 0
  end

  test "the sign-in page links to registration" do
    get new_session_path

    assert_select "a[href=?]", new_registration_path
  end
end
