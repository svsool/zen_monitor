defmodule ZenMonitor.Application do
  @moduledoc """
  OTP Application that acts as the entry point for ZenMonitor.

  This Application will start all necessary processes for a node to be a compatible ZenMonitor
  node and to communicate with other compatible ZenMonitor nodes.

  See `ZenMonitor.Supervisor` for more information.
  """
  use Application

  def start(_type, _args) do
    children = [
      ZenMonitor.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
