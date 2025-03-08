defmodule ZenMonitor.Utils do
  @spec lookup_or_start(atom(), atom(), term()) :: pid()
  def lookup_or_start(module, key, args) do
    case Registry.lookup(module, key) do
      [{_pid, value}] ->
        value

      [] ->
        # process will register itself in registry using own pid
        value = case DynamicSupervisor.start_child(
            ZenMonitor.DynamicSupervisor,
            List.to_tuple([module | args])
          ) do
          {:ok, pid} ->
            pid

          {:error, {:already_started, pid}} ->
            pid
        end

        value
    end
  end
end
