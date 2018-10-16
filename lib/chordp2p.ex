defmodule ChordP2P do
  use Application

  require Logger

  @moduledoc """
  Documentation for GS.
  """

  def start(type, args) do
    # Logger.debug("Inside start " <> inspect(_MODULE_) <> " " <> "with args: " <> inspect(args) <> "and type: " <> inspect(type))
    CP2P.Supervisor.start_link(args)
    GenServer.call(CP2P.Master, {:begin, args}, :infinity)
  end
end
