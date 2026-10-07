# URL helpers for the file reader.
module CartridgeFilesHelper
  # The route the game itself loads this file through.
  #
  # Reusing it rather than adding a second way to serve the bytes keeps one
  # answer to "what does this file contain": the image previewed here is the
  # same request the loader makes, and the download a person clicks is what the
  # cart actually plays with.
  #
  # The served tree prefixes the cart directory, because Console::CartLoader
  # looks under carts/<name>/ and a cart never hardcodes its own name.
  def download_path(file)
    cartridge_data_path(file.cartridge.slug, "#{file.cartridge.cart_prefix}/#{file.path}")
  end

  # A file's text as markup rather than as the string it is stored as, and
  # whether that markup carries colour.
  #
  # The one place on the site that hands a view something html_safe, and it is
  # only reached for a file that is already known to be text -- see
  # FileHighlighter for why that is safe.
  def highlighted(file, text)
    highlighter = FileHighlighter.new(file.path, text)

    [ highlighter.call, highlighter.highlighted? ]
  end
end
