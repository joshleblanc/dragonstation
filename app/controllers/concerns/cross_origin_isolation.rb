# COOP + COEP make the page cross-origin isolated, which is what gives the wasm
# build SharedArrayBuffer (and so threads). Without them the loader falls back
# to registering dragonruby-serviceworker.js to fake these headers and reload
# the page -- slower, and a dead page whenever a fetch fails. Both the page
# holding the iframe and the iframe itself need them.
module CrossOriginIsolation
  extend ActiveSupport::Concern

  included do
    # Before, not after: send_file/send_data build the response directly.
    before_action do
      response.set_header "Cross-Origin-Opener-Policy", "same-origin"
      response.set_header "Cross-Origin-Embedder-Policy", "require-corp"
    end
  end
end
