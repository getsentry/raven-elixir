defmodule Mix.Tasks.Sentry.SendTestEvent do
  use Mix.Task

  @shortdoc "Attempts to send a test event to check Sentry configuration"

  def run(_args) do
    Application.ensure_all_started(:sentry)
    {endpoint, public_key, secret_key} = Sentry.Client.get_dsn!

    included_environments = case Application.fetch_env(:sentry, :included_environments) do
      {:ok, envs} when is_list(envs) -> envs
      _ ->
        Mix.raise "Sentry included_environments is not configured in :sentry, :included_environments"
    end

    environment_name = Application.get_env(:sentry, :environment_name)
    hackney_opts = Application.get_env(:sentry, :hackney_opts, [])
    Mix.shell.info "Client configuration:"
    Mix.shell.info "server: #{endpoint}"
    Mix.shell.info "public_key: #{public_key}"
    Mix.shell.info "secret_key: #{secret_key}"
    Mix.shell.info "included_environments: #{inspect included_environments}"
    Mix.shell.info "current environment_name: #{inspect environment_name}"
    Mix.shell.info "hackney_opts: #{inspect hackney_opts}\n"

    maybe_send_event(environment_name, included_environments)
  end

  defp maybe_send_event(env_name, included_envs) do
    if env_name in included_envs do
      Mix.shell.info "Sending test event..."

      {:ok, _, task} = "Testing sending Sentry event"
                       |> RuntimeError.exception
                       |> Sentry.capture_exception

      Task.await(task)

      Mix.shell.info "Test event sent!"
    else
      Mix.shell.info "#{inspect env_name} is not in #{inspect included_envs} so no test event will be sent"
    end
  end
end
