Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # Cartridges are addressed by slug, so a published game keeps a URL that
  # survives its title being edited.
  resources :cartridges, param: :slug do
    patch :publish, on: :member
  end

  # The runtime. Declared before the catch-all below it, because the build's
  # own files are also served from this path: the shell asks for game.css and
  # dragonruby-html5-loader.js as siblings of index.html, and they have to
  # resolve without shadowing the two dynamic endpoints.
  #
  # The loader asks for manifest.json first, then gamedata/<path> for every
  # file the manifest names.
  get "cartridges/:cartridge_id/play/manifest.json",
    to: "cartridge_runtime#manifest", as: :cartridge_manifest
  get "cartridges/:cartridge_id/play/gamedata/*path",
    to: "cartridge_runtime#data", as: :cartridge_data
  get "cartridges/:cartridge_id/play/*file",
    to: "cartridge_runtime#shell", as: :cartridge_shell

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "cartridges#index"
end
