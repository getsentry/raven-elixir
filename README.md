# sentry

[![Build Status](https://img.shields.io/travis/getsentry/sentry-elixir.svg?style=flat)](https://travis-ci.org/getsentry/sentry-elixir)
[![hex.pm version](https://img.shields.io/hexpm/v/sentry.svg?style=flat)](https://hex.pm/packages/sentry)

The Official Sentry Client for Elixir which provides a simple API to capture exceptions, automatically handle Plug Exceptions and provides a backend for the Elixir Logger.

[Documentation](https://hexdocs.pm/sentry/readme.html)

## Installation

To use Sentry with your projects, edit your mix.exs file to add it as a dependency and add the `:sentry` package to your applications:

```elixir
defp application do
  [applications: [:sentry, :logger]]
end

defp deps do
  [{:sentry, "~> 5.0.1"}]
end
```

### Capture Exceptions

Sometimes you want to capture specific exceptions.  To do so, use `Sentry.capture_exception/3`.

```elixir
try do
  ThisWillError.reall()
rescue
  my_exception ->
    Sentry.capture_exception(my_exception, [stacktrace: System.stacktrace(), extra: %{extra: information}])
end
```

For optional settings check the [docs](https://hexdocs.pm/sentry/readme.html).

### Setup with Plug or Phoenix

In your router add the following lines:

```elixir
use Plug.ErrorHandler
use Sentry.Plug
```

### Capture All Exceptions

This library comes with an extension to capture all Error messages that the Plug handler might not. Simply set `use_error_logger` to true.

This is based on the Erlang [error_logger](http://erlang.org/doc/man/error_logger.html).

```elixir
config :sentry,
  use_error_logger: true
```

## Configuration

| Key           | Required         | Default      | Notes |
| ------------- | -----------------|--------------|-------|
| `dsn` | True  | n/a | |
| `environment_name` | False  | `:dev` | |
| `included_environments` | False  | `~w(prod test dev)a` | If you need non-standard mix env names you *need* to include it here |
| `tags` | False  | `%{}` | |
| `release` | False  | None | |
| `server_name` | False  | None | |
| `use_error_logger` | False  | False | |
| `client` | False  | `Sentry.Client` | If you need different functionality for the HTTP client, you can define your own module that implements the `Sentry.HTTPClient` behaviour and set `client` to that module |
| `hackney_opts` | False  | `[pool: :sentry_pool]` | |
| `hackney_pool_max_connections` | False  | 50 | |
| `hackney_pool_timeout` | False  | 5000 | |
| `before_send_event` | False | | |
| `after_send_event` | False | | |
| `sample_rate` | False | 1.0 | |
| `in_app_module_whitelist` | False | `[]` | |
| `report_deps` | False | True | Will attempt to load Mix dependencies at compile time to report alongside events |
| `enable_source_code_context` | True | | |
| `root_source_code_path` | Required if `enable_source_code_context` is enabled | | Should generally be set to `File.cwd!`|
| `context_lines` | False  | 3 | |
| `source_code_exclude_patterns` | False  | `[~r"/_build/", ~r"/deps/", ~r"/priv/"]` | |
| `source_code_path_pattern` | False  | `"**/*.ex"` | |

An example production config might look like this:

```elixir
config :sentry,
  dsn: "https://public:secret@app.getsentry.com/1",
  environment_name: :prod,
  included_environments: [:prod],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!,
  tags: %{
    env: "production"
  },
  hackney_opts: [pool: :my_pool],
  in_app_module_whitelist: [MyApp]
```

The `environment_name` and `included_environments` work together to determine
if and when Sentry should record exceptions. The `environment_name` is the
name of the current environment. In the example above, we have explicitly set
the environment to `:prod` which works well if you are inside an environment
specific configuration like `config/prod.exs`.

Alternatively, you could use Mix.env in your general configuration file:

```elixir
config :sentry, dsn: "https://public:secret@app.getsentry.com/1",
  included_environments: [:prod],
  environment_name: Mix.env
```

You can even rely on more custom determinations of the environment name. It's
not uncommmon for most applications to have a "staging" environment. In order
to handle this without adding an additional Mix environment, you can set an
environment variable that determines the release level.

```elixir
config :sentry, dsn: "https://public:secret@app.getsentry.com/1",
  included_environments: ~w(production staging),
  environment_name: System.get_env("RELEASE_LEVEL") || "development"
```

In this example, we are getting the environment name from the `RELEASE_LEVEL`
environment variable. If that variable does not exist, we default to `"development"`.
Now, on our servers, we can set the environment variable appropriately. On
our local development machines, exceptions will never be sent, because the
default value is not in the list of `included_environments`.

Sentry uses the [hackney HTTP client](https://github.com/benoitc/hackney) for HTTP requests.  Sentry starts its own hackney pool named `:sentry_pool` with a default connection pool of 50, and a connection timeout of 5000 milliseconds.  The pool can be configured with the `hackney_pool_max_connections` and `hackney_pool_timeout` configuration keys.  If you need to set other [hackney configurations](https://github.com/benoitc/hackney/blob/master/doc/hackney.md#request5) for things like a proxy, using your own pool or response timeouts, the `hackney_opts` configuration is passed directly to hackney for each request.

### Reporting Exceptions with Source Code

Sentry's server supports showing the source code that caused an error, but depending on deployment, the source code for an application is not guaranteed to be available while it is running.  To work around this, the Sentry library reads and stores the source code at compile time.  This has some unfortunate implications.  If a file is changed, and Sentry is not recompiled, it will still report old source code.

The best way to ensure source code is up to date is to recompile Sentry itself via `mix do clean, compile`.  It's possible to create a Mix Task alias in `mix.exs` to do this.  The example below would allow one to run `mix sentry_recompile` which will force recompilation of Sentry so it has the newest source and then compile the project:

```elixir
# mix.exs
defp aliases do
  [sentry_recompile: ["clean", "compile"]]
end
```

For more documentation, see [Sentry.Sources](https://hexdocs.pm/sentry/Sentry.Sources.html).

## Testing Your Configuration

To ensure you've set up your configuration correctly we recommend running the
included mix task.  It can be tested on different Mix environments and will tell you if it is not currently configured to send events in that environment:

```bash
$ MIX_ENV=dev mix sentry.send_test_event
Client configuration:
server: https://sentry.io/
public_key: public
secret_key: secret
included_environments: [:prod]
current environment_name: :dev

:dev is not in [:prod] so no test event will be sent

$ MIX_ENV=prod mix sentry.send_test_event
Client configuration:
server: https://sentry.io/
public_key: public
secret_key: secret
included_environments: [:prod]
current environment_name: :prod

Sending test event!
```

## Docker

There are a couple of important things to keep in mind when building a `Docker` image.

### config files

If you follow [_Best practices for writing Dockerfiles_](https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/), you probably copy just `mix.exs` and `mix.lock` files firstly to leverage caching. Then, you install and compile all dependencies.

```dockerfile
COPY mix.* ./
RUN mix do deps.get, deps.compile
```

In such case, your build will result in the following error:

```bash
== Compilation error on file lib/sentry/event.ex ==
** (ArgumentError) application :sentry is not loaded, or the configuration parameter :enable_source_code_context is not set
    (elixir) lib/application.ex:261: Application.fetch_env!/2
    lib/sentry/event.ex:38: (module)
    (stdlib) erl_eval.erl:670: :erl_eval.do_apply/6

could not compile dependency :sentry, "mix compile" failed. You can recompile this dependency with "mix deps.compile sentry", update it with "mix deps.update sentry" or clean it with "mix deps.clean sentry"
```

This happens because no `config` files are available for `sentry` compilation. To fix the problem, you need an additional step before fetching and compiling `sentry-elixir`:

```dockerfile
# ...
COPY config/*.exs ./config/

RUN mix do deps.get, deps.compile
```

With the entry above you will be able to start compiling `sentry` dependency.

### HOME directory

However, `sentry` itself recursively reads files at compile time in the root project directory and use `File.cwd!/1` for that, so if you put your project in `root` directory (`/`), it will take a lot of time to complete.

To "fix" that, here's an entry to add in your `Dockerfile`:

```dockerfile
WORKDIR /opt/your-application-name
```

Once you have this added, you should be able to successfuly build a `Docker` image:

```bash
docker build -t your_application_name .
```

## Docs

To build the docs locally, you'll need the [Sphinx](http://www.sphinx-doc.org/en/stable/):

```
$ pip install sphinx
```

Once Sphinx is available building the docs is simply:

```
$ make docs
```

You can then view the docs in your browser:

```
$ open docs/_build/html/index.html
```

## License

This project is Licensed under the [MIT License](https://github.com/getsentry/sentry-elixir/blob/master/LICENSE).
