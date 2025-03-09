defmodule ChildNode do
  @moduledoc """
  ChildNode provides facilities for starting another erlang node on the current machine.

  This module enhances and abstracts the erlang `peer` module. After calling `peer.start` to
  make sure the child node is running, it ensures that Elixir is started, after which it will run
  any function passed in as the `:on_start` param. This function must be compiled and loaded on
  both nodes.

  After that, control is handed back to the caller who can use the `:rpc` module to invoke
  functions remotely.

  The child nodes process is linked to the caller's process, so if the caller dies, so will the
  child node.

  If additional logging is required, set `enable_sasl` option to `true`.
  """

  @type param :: {:enable_sasl, boolean} | {:on_start, (-> any)}
  @type params :: [param]

  defmodule Runner do
    @moduledoc """
    When the new node starts up, we often want to set up a supervision tree by calling
    a function with `:rpc.call`. However, when the call ends, all the linked processes
    in the rpc call will die. This runner encapsulates them and doesn't link to its caller,
    so that any processes started by `Runner` will continue to live after the `:rpc` call.
    """
    use GenServer

    def start(mod, fun, args) do
      GenServer.start(__MODULE__, [mod, fun, args])
    end

    def start(init_fn) when is_function(init_fn) do
      GenServer.start(__MODULE__, [init_fn])
    end

    def init([mod, fun, args]) do
      rv = apply(mod, fun, args)
      {:ok, rv}
    end

    def init([init_fn]) do
      {:ok, init_fn}
    end

    def get(runner_pid) do
      GenServer.call(runner_pid, :get)
    end

    def do_init(runner_pid, args) do
      GenServer.call(runner_pid, {:do_init, args})
    end

    def handle_call({:do_init, args}, _from, init_fn) do
      {:reply, init_fn.(args), init_fn}
    end

    def handle_call(:get, _from, v) do
      {:reply, v, v}
    end
  end

  @spec start_link(Application.t(), atom, params) :: {:ok, pid} | {:error, any}
  def start_link(app_to_start, node_name, params \\ [], timeout \\ 5_000) do
    unless Node.alive?() do
      {:ok, _} = Node.start(:"local@0.0.0.0")
    end

    default_node_start_args = [
      ~c"-setcookie #{Node.get_cookie() |> Atom.to_charlist()}",
      ~c"-connect_all",
      ~c"false"
    ]

    node_start_args =
      if params[:enable_sasl] do
        default_node_start_args ++ [~c"-logger", ~c"handle_sasl_reports true"]
      else
        default_node_start_args
      end

    node_name = to_node_name(node_name)

    {:ok, node_pid, node_name} =
      :peer.start_link(%{
        host: ~c"0.0.0.0",
        name: node_name,
        connection: :standard_io,
        args: node_start_args
      })

    :rpc.call(node_name, :code, :add_paths, [:code.get_path()])

    {:ok, _} = :rpc.call(node_name, :application, :ensure_all_started, [:elixir])

    on_start = params[:on_start]
    rpc_args = [node_name, app_to_start, on_start, self()]

    case :rpc.call(node_name, __MODULE__, :on_start, rpc_args, timeout) do
      {:ok, start_fn_results} ->
        {:ok, node_name, node_pid, start_fn_results}

      {:badrpc, :timeout} ->
        {:error, :timeout}
    end
  end

  def on_start(node_name, app_to_start, start_callback, _caller) do
    case app_to_start do
      apps when is_list(apps) ->
        for app <- apps do
          {:ok, _} = Application.ensure_all_started(app)
        end

      app when is_atom(app) ->
        {:ok, _started_apps} = Application.ensure_all_started(app)
    end

    start_fn_results =
      case start_callback do
        callback when is_function(callback) ->
          {:ok, runner_pid} = Runner.start(callback)
          Runner.do_init(runner_pid, node_name)

        {m, f, a} ->
          {:ok, runner_pid} = Runner.start(m, f, a)
          Runner.get(runner_pid)

        nil ->
          nil
      end

    {:ok, start_fn_results}
  end

  @doc "Runs the MFA in a process on the remote node"
  @spec run(node, module(), atom(), [any]) :: any
  def run(node, m, f, a) do
    {:ok, runner_pid} = :rpc.call(node, Runner, :start, [m, f, a])
    :rpc.call(node, Runner, :get, [runner_pid])
  end

  defp to_node_name(node_name) when is_atom(node_name) do
    node_name
    |> Atom.to_string()
    |> String.split(".")
    |> sanitize_node_name
  end

  defp sanitize_node_name([node_name]) do
    String.to_atom(node_name)
  end

  defp sanitize_node_name(node_name) when is_list(node_name) do
    node_name
    |> List.last()
    |> Macro.underscore()
    |> String.downcase()
    |> String.to_atom()
  end
end
