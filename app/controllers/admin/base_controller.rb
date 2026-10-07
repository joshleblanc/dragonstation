module Admin
  # The gate for every admin screen.
  #
  # Not a redirect and not a 403: a 404, the same answer the rest of the app
  # gives for something the visitor is not allowed to know exists. An admin URL
  # that answers differently for a stranger is an admin URL that gets written
  # down somewhere, and the fact that it exists is the only part of it that
  # matters to whoever found it.
  #
  # require_authentication has already run by the time this does, so Current.user
  # is resolved here rather than resumed again.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_admin!

    private
      def require_admin!
        return if Current.user&.admin?

        head :not_found
      end
  end
end
