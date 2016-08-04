defmodule Sentry do
  use GenEvent
  alias Sentry.Client

  @moduledoc """
  Setup the application environment in your config.

      config :sentry,
        dsn: "https://public:secret@app.getsentry.com/1"
        tags: %{
          env: "production"
        }

  Install the Logger backend.

      config :logger, backends: [:console, Sentry]
  """

  ## Server

  def handle_call({:configure, _options}, state) do
    {:ok, :ok, state}
  end

  def handle_event({:error, gl, {Logger, msg, _ts, _md}}, state) when node(gl) == node() do
    capture_exception(msg)
    {:ok, state}
  end

  def handle_event(_data, state) do
    {:ok, state}
  end

  ## Sentry

  defmodule Event do
    defstruct event_id: nil,
              culprit: nil,
              timestamp: nil,
              message: nil,
              tags: %{},
              level: "error",
              platform: "elixir",
              server_name: nil,
              exception: nil,
              stacktrace: %{
                frames: []
              },
              extra: %{}
  end

  @doc """
  Parses and submits an exception to Sentry if DSN is setup in application env.
  """
  @spec capture_exception(String.t) :: {:ok, String.t} | :error
  def capture_exception(exception) do
    # TODO: better environment handling
    case Application.get_env(:sentry, :dsn) do
      dsn when is_bitstring(dsn) ->
        parsed_dsn = Client.parse_dsn!(dsn)
        transform(exception)
        |> capture_exception(parsed_dsn)
      _ ->
        :error
    end
  end

  @spec capture_exception(%Event{}, Client.parsed_dsn) :: {:ok, String.t} | :error
  def capture_exception(%Event{message: nil, exception: nil}, _) do
    {:ok, "Unable to parse as exception, ignoring..."}
  end

  def capture_exception(event, {endpoint, public_key, private_key}) do
    auth_headers = Client.authorization_headers(public_key, private_key)

    Client.request(:post, endpoint, auth_headers, event)
  end

  ## Transformers

  @doc """
  Transforms a exception string to a Sentry event.
  """
  @spec transform(String.t) :: %Event{}
  def transform(stacktrace) do
    :erlang.iolist_to_binary(stacktrace)
    |> String.split("\n")
    |> transform(%Event{})
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["Error in process " <> _ = message|t], state) do
    transform(t, %{state | message: message})
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["Last message: " <> last_message|t], state) do
    transform(t, put_in(state.extra, Map.put_new(state.extra, :last_message, last_message)))
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["State: " <> last_state|t], state) do
    transform(t, put_in(state.extra, Map.put_new(state.extra, :state, last_state)))
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["Function: " <> function|t], state) do
    transform(t, put_in(state.extra, Map.put_new(state.extra, :function, function)))
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["    Args: " <> args|t], state) do
    transform(t, put_in(state.extra, Map.put_new(state.extra, :args, args)))
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["    ** " <> message|t], state) do
    transform_first_stacktrace_line([message|t], state)
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["** " <> message|t], state) do
    transform_first_stacktrace_line([message|t], state)
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["        " <> frame|t], state) do
    transform_stacktrace_line([frame|t], state)
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform(["    " <> frame|t], state) do
    transform_stacktrace_line([frame|t], state)
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform([_|t], state) do
    transform(t, state)
  end

  @spec transform([String.t], %Event{}) :: %Event{}
  def transform([], state) do
    %{state |
      event_id: UUID.uuid4(:hex),
      timestamp: iso8601_timestamp,
      tags: Application.get_env(:sentry, :tags, %{}),
      server_name: to_string(:net_adm.localhost)}
  end

  @spec transform(any, %Event{}) :: %Event{}
  def transform(_, state) do
    # TODO: maybe do something with this?
    state
  end

  ## Private

  defp transform_first_stacktrace_line([message|t], state) do
    [_, type, value] = Regex.run(~r/^\((.+?)\) (.+)$/, message)
    transform(t, %{state | message: message, exception: [%{type: type, value: value}]})
  end

  defp transform_stacktrace_line([frame|t], state) do
    match =
      case Regex.run(~r/^(\((.+?)\) )?(.+?):(\d+): (.+)$/, frame) do
        [_, _, filename, lineno, function] -> [:unknown, filename, lineno, function]
        [_, _, app, filename, lineno, function] -> [app, filename, lineno, function]
        _ -> :no_match
      end

    case match do
      [app, filename, lineno, function] ->
        state = if state.culprit, do: state, else: %{state | culprit: function}

        state = put_in(state.stacktrace.frames, [%{
          filename: filename,
          function: function,
          module: nil,
          lineno: String.to_integer(lineno),
          colno: nil,
          abs_path: nil,
          context_line: nil,
          pre_context: nil,
          post_context: nil,
          in_app: not app in ["stdlib", "elixir"],
          vars: %{},
        } | state.stacktrace.frames])

        transform(t, state)
      :no_match -> transform(t, state)
    end
  end

  @spec iso8601_timestamp :: String.t
  defp iso8601_timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
  end
end