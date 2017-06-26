defmodule Sentry.LoggerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  import Sentry.TestEnvironmentHelper

  test "exception makes call to Sentry API" do
    bypass = Bypass.open
    pid = self()
    Bypass.expect bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "RuntimeError"
      assert body =~ "Unique Error"
      assert conn.request_path == "/api/1/store/"
      assert conn.method == "POST"
      send(pid, "API called")
      Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
    end

    modify_env(:sentry, dsn: "http://public:secret@localhost:#{bypass.port}/1")
    :error_logger.add_report_handler(Sentry.Logger)

    capture_log fn ->
      Task.start( fn ->
        raise "Unique Error"
      end)

      assert_receive "API called"
    end

    :error_logger.delete_report_handler(Sentry.Logger)
  end

  test "GenServer throw makes call to Sentry API" do
    Process.flag :trap_exit, true
    bypass = Bypass.open
    Bypass.expect bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Poison.decode!(body)
      assert List.first(json["exception"])["type"] == "exit"
      assert List.first(json["exception"])["value"] == "** (exit) bad return value: \"I am throwing\""
      assert conn.request_path == "/api/1/store/"
      assert conn.method == "POST"
      Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
    end

    modify_env(:sentry, dsn: "http://public:secret@localhost:#{bypass.port}/1")
    :error_logger.add_report_handler(Sentry.Logger)

    capture_log fn ->
      {:ok, pid} = Sentry.TestGenServer.start_link(self())
      Sentry.TestGenServer.do_throw(pid)
      assert_receive "terminating"
    end
    :error_logger.delete_report_handler(Sentry.Logger)
  end

  test "abnormal GenServer exit makes call to Sentry API" do
    Process.flag :trap_exit, true
    bypass = Bypass.open
    Bypass.expect bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Poison.decode!(body)
      assert List.first(json["exception"])["type"] == "exit"
      assert List.first(json["exception"])["value"] == "** (exit) :bad_exit"
      assert conn.request_path == "/api/1/store/"
      assert conn.method == "POST"
      Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
    end

    modify_env(:sentry, dsn: "http://public:secret@localhost:#{bypass.port}/1")
    :error_logger.add_report_handler(Sentry.Logger)

    capture_log fn ->
      {:ok, pid} = Sentry.TestGenServer.start_link(self())
      Sentry.TestGenServer.bad_exit(pid)
      assert_receive "terminating"
    end
    :error_logger.delete_report_handler(Sentry.Logger)
  end

  test "Bad function call causing GenServer crash makes call to Sentry API" do
    Process.flag :trap_exit, true
    bypass = Bypass.open
    Bypass.expect bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Poison.decode!(body)
      assert List.first(json["exception"])["type"] == "exit"
      assert List.first(json["exception"])["value"] == "** (exit) :function_clause"
      assert List.last(json["stacktrace"]["frames"]) == %{"filename" => "lib/calendar.ex",
                                                          "function" => "NaiveDateTime.from_erl/2",
                                                          "lineno" => 1214,
                                                          "module" => "Elixir.NaiveDateTime",
                                                          "context_line" => nil,
                                                          "pre_context" => [],
                                                          "post_context" => [],
                                                        }
      assert conn.request_path == "/api/1/store/"
      assert conn.method == "POST"
      Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
    end

    modify_env(:sentry, dsn: "http://public:secret@localhost:#{bypass.port}/1")
    :error_logger.add_report_handler(Sentry.Logger)

    capture_log fn ->
      {:ok, pid} = Sentry.TestGenServer.start_link(self())
      Sentry.TestGenServer.invalid_function(pid)
      assert_receive "terminating"
    end
    :error_logger.delete_report_handler(Sentry.Logger)
  end
end
