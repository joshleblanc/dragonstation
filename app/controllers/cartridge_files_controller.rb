# Reads one file out of a cart, so the cart's page can show what it contains.
#
# The bytes already have a public route: the runtime serves every file of a
# published cart to the game, to anyone, as gamedata/<path>. This is the same
# bytes with a human attached -- printed as text, rendered as an image, or
# offered as a download when they are neither.
#
# Which cartridge a path belongs to is decided by the database, never by
# joining the path onto a directory. A request can only name a file that
# cartridge uploaded and stored, so traversal is not something this action has
# to defend against separately -- it has nothing to resolve the path against.
class CartridgeFilesController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  # Public, like the runtime it reads from: a published cart's files are
  # already served to anyone. Drafts are decided per cartridge by
  # visible_cartridge?, so this action is as closed as the game itself.
  allow_unauthenticated_access

  # Enough of a big file to read, not so much that a data file turns into a web
  # page. Truncation is stated in the page rather than hidden, because a file
  # that stops mid-way without saying so reads as the whole file.
  TEXT_LIMIT = 128 * 1024

  # Above this the file is not read at all. The ingest already caps an archive
  # at 32MB, so a single file can be large enough that fetching it to show its
  # first 128KB is a bad trade; the download link is the honest answer.
  READ_LIMIT = 4 * 1024 * 1024

  before_action :load_cartridge

  def show
    # The exact stored path, and nothing else. Stored paths are validated as
    # cart-relative when a file is created, so a name that matches a row is a
    # file this cart owns.
    @file = @cartridge.cartridge_files.find_by(path: params[:path])

    return head :not_found unless @file

    @contents, @truncated = readable_text(@file)
  end

  private
    def load_cartridge
      @cartridge = Cartridge.find_by!(slug: params[:cartridge_id])

      head :not_found unless visible_cartridge?
    end

    # [text, truncated], or [nil, false] when these bytes are not something to
    # print.
    #
    # The extension already ruled out most binary files; this is the check that
    # the extension cannot make. A NUL byte is the same test CartridgeIngest
    # uses to decide what is source, so a file it accepted as source reads
    # here, and a file it stored as an asset does not print as mojibake.
    def readable_text(file)
      return [ nil, false ] unless file.text?
      return [ nil, false ] if file.byte_size > READ_LIMIT

      bytes = file.blob.download
      truncated = bytes.bytesize > TEXT_LIMIT
      bytes = bytes.byteslice(0, TEXT_LIMIT) if truncated

      return [ nil, false ] if bytes.include?("\x00")

      # Cutting at a byte limit can land inside a multibyte character, so the
      # tail is scrubbed rather than refused: the truncation is already visible
      # in the page, and dropping the last few characters is less bad than
      # dropping the file.
      text = bytes.force_encoding(Encoding::UTF_8).scrub("")

      [ text, truncated ]
    end
end
