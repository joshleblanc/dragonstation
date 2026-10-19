# POST /api/carts -- publishing a cart from the console's ./publish-site.
#
# The same CartridgeIngest as the upload form, refusals and all, and it lands
# as a draft: going live stays a decision a person makes after seeing it run.
module Api
  class CartsController < BaseController
    def create
      # Refused rather than defaulted to the newest: two carts silently on
      # different libraries is worse than a clear error.
      version = ConsoleVersion.default
      unless version&.available?
        return render_problems("no console library is available to build against", [], :service_unavailable)
      end

      if params[:archive].blank?
        return render_problems("no archive", "send the cart as multipart/form-data under `archive`", :bad_request)
      end

      cartridge = CartridgeIngest.new(
        archive: params[:archive],
        user: Current.user,
        console_version: version,
        title: params[:title]
      ).call

      render json: {
        id: cartridge.id,
        slug: cartridge.slug,
        title: cartridge.title,
        status: cartridge.draft? ? "draft" : "published",
        url: cartridge_url(cartridge),
        console_version: cartridge.console_version.version
      }, status: :created
    rescue CartridgeIngest::Invalid => e
      render_problems("that archive is not a cart I can run", e.problems, :unprocessable_content)
    end
  end
end
