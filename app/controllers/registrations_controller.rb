class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  # Tighter than sign-in, because creating accounts is the thing worth
  # hammering: enough for a person filling the form in and retrying, not enough
  # for a script.
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      # The first account on a fresh install is the operator. Seeding one
      # through the console works too, but registration is the only route that
      # exists before anybody has an account.
      User.promote_first_admin!
      start_new_session_for @user

      redirect_to after_authentication_url, notice: "Welcome, #{@user.username}."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def registration_params
      params.expect(registration: %i[username email_address password password_confirmation])
    end
end
