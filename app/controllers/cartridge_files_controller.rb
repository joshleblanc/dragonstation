# One file of a cart, for a person: printed as text, shown as an image, or
# offered as a download. Paths are looked up as rows of this cartridge, never
# joined onto a directory, so there is nothing for traversal to resolve against.
class CartridgeFilesController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  allow_unauthenticated_access

  # Shown, with the truncation stated in the page.
  TEXT_LIMIT = 128 * 1024

  # Not fetched at all above this; the download link is the honest answer.
  READ_LIMIT = 4 * 1024 * 1024

  before_action :load_visible_cartridge

  def show
    @file = @cartridge.cartridge_files.find_by(path: params[:path])
    return head :not_found unless @file

    @contents, @truncated = readable_text(@file)
  end

  private
    # [text, truncated], or [nil, false] when the bytes are not printable.
    def readable_text(file)
      return [ nil, false ] if !file.text? || file.byte_size > READ_LIMIT

      bytes = file.blob.download
      truncated = bytes.bytesize > TEXT_LIMIT
      bytes = bytes.byteslice(0, TEXT_LIMIT) if truncated

      # NUL means binary -- the same test CartridgeIngest uses.
      return [ nil, false ] if bytes.include?("\x00")

      # A byte cut can land mid-character; drop the fragment, not the file.
      [ bytes.force_encoding(Encoding::UTF_8).scrub(""), truncated ]
    end
end
