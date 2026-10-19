module Admin
  # Every admin screen. A non-admin gets a 404, like anything else they may not
  # know exists -- an admin URL that answers differently gets written down.
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
