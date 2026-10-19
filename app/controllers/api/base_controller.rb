# Key-authenticated endpoints for the console. A missing or bad key is a 401,
# never a redirect to a sign-in form a terminal cannot answer, and there is no
# CSRF token because a cross-site form cannot set an Authorization header.
module Api
  class BaseController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection

    before_action :authenticate_key!

    private
      def authenticate_key!
        Current.api_key = ApiKey.from_authorization(request.authorization)

        render json: { error: "unauthorised" }, status: :unauthorized unless Current.api_key
      end

      def render_problems(error, problems, status)
        render json: { error: error, problems: Array(problems) }, status: status
      end
  end
end
