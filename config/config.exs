use Mix.Config

config :sentry,
  included_environments: [:prod]

import_config "#{Mix.env}.exs"
