# Who may see a cartridge: published is public; a draft is its owner's and
# admins'. The page, the runtime and the file reader are all public routes, so
# this one rule is all that stands between a draft and the internet.
module CartridgeVisibility
  extend ActiveSupport::Concern

  private
    def load_visible_cartridge
      @cartridge = Cartridge.find_by!(slug: params[:cartridge_id])
      head :not_found unless visible_cartridge?
    end

    def visible_cartridge?
      # allow_unauthenticated_access skips the callback that resumes the
      # session, and without it an owner would be refused their own draft.
      resume_session
      @cartridge.published? || owner?
    end

    def owner?
      Current.user.present? && (Current.user.admin? || Current.user == @cartridge.user)
    end
end
