class SettingsController < ApplicationController
  def show
    @api_key = Current.user.api_key
  end

  # A new key, replacing the old one.
  #
  # Rendered rather than redirected, because the secret exists for exactly one
  # response: putting it in the flash would write it to a cookie, and the whole
  # point of not storing it is that it is nowhere but here.
  def rotate_api_key
    @secret = Current.user.issue_api_key!
    @api_key = Current.user.api_key

    flash.now[:notice] = "Here is your new key. It is not stored anywhere, so this is the " \
                         "only time it will be shown."

    # Explicitly, because there is no rotate_api_key template: without this a
    # POST that renders nothing answers 204 and shows nothing at all.
    render :show
  end
end
