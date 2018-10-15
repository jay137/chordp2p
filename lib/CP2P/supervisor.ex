defmodule CP2P.Supervisor do
  use Supervisor

  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, [])
  end

  def init(args) do
    Logger.debug("Inside init " <> inspect(__MODULE__) <> " " <> "with args: " <> inspect(args))

    children = [
      {Registry, keys: :unique, name: CP2P.Registry.ProcReg},
      # {CP2P.Beacon, name: CP2P.Beacon},
      {CP2P.Master, name: CP2P.Master, args: args},
      {DynamicSupervisor, name: CP2P.NodeSupervisor, strategy: :one_for_one}
      # {CP2P.Node_failure_instrumentor, name: CP2P.Node_failure_instrumentor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
