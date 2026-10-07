class Current < ActiveSupport::CurrentAttributes
  attribute :session

  # Set only by the API, where the credential is a key rather than a cookie.
  # Both are per-request state and CurrentAttributes resets them, so a key can
  # never outlive the request that presented it.
  attribute :api_key

  # Whoever is asking: a browser with a session, or a console with a key.
  #
  # The fallback is what lets the API share every check in the app -- visibility
  # of a draft, ownership of a cartridge -- without a second version of each
  # one written for key-authenticated callers.
  def user
    session&.user || api_key&.user
  end
end
