# Who is allowed to see a cartridge, in one place.
#
# Three actions answer that question -- the cartridge page, the runtime that
# feeds the game, and the file reader -- and all three are public routes, so
# the rule is the only thing between an unpublished cart and the internet. It
# used to be written out in each controller, which is how one of them ends up
# quietly disagreeing with the others.
#
# Published is public. A draft is visible to the person writing it and to an
# admin, and to nobody else.
module CartridgeVisibility
  extend ActiveSupport::Concern

  private
    # True when @cartridge may be shown to whoever is asking.
    #
    # Resumes the session first, deliberately: allow_unauthenticated_access
    # skips require_authentication, and that callback is also what populates
    # Current.session from the cookie. Without it Current.user is nil for
    # everyone and a signed-in owner is denied their own draft.
    def visible_cartridge?
      current_user_if_signed_in
      return true if @cartridge.published?

      owner?
    end

    def owner?
      Current.user.present? && (Current.user.admin? || Current.user == @cartridge&.user)
    end
end
