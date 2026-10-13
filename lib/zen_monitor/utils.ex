defmodule ZenMonitor.Utils do
  @spec lookup_or_start(atom(), atom(), term()) :: pid()
  def lookup_or_start(module, key, args) do
    case Registry.lookup(module, key) do
      [{_pid, value}] ->
        value

      [] ->
        # Never restart workers. A restarted Batcher monitors its dead subscriber again, stops,
        # and loops until DynamicSupervisor exits. The next lookup starts a fresh worker.
        child_spec = Supervisor.child_spec(List.to_tuple([module | args]), restart: :temporary)

        # process will register itself in registry using own pid
        value =
          case DynamicSupervisor.start_child(ZenMonitor.DynamicSupervisor, child_spec) do
            {:ok, pid} ->
              pid

            {:error, {:already_started, pid}} ->
              pid
          end

        value
    end
  end
end
