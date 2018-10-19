defmodule ChordP2P do
  use Application

  require Logger

  @moduledoc """
  Documentation for GS.
  """

  def start(type, args) do
    Logger.debug("Inside start #{inspect(__MODULE__)} with args: #{inspect(args)},  and type: #{inspect(type)}")
    CP2P.Supervisor.start_link(args)
    avg_hops = GenServer.call(CP2P.Master, {:begin, args}, :infinity)
    IO.puts("Average hops for #{inspect args[:num_nodes]} nodes passing #{inspect args[:num_req]} messages is #{inspect avg_hops}")
    Logger.debug("Exiting application #{inspect(__MODULE__)} ")
  end
end
