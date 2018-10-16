defmodule Chord_CLI do
  require Logger

  def main(args) do

    {num_nodes, _} = Integer.parse(Enum.at(args, 0))
    {num_req, _} = Integer.parse(Enum.at(args, 1))
    Logger.debug("#{inspect(__MODULE__)} #{inspect(num_nodes)}  #{inspect(num_req)}")

    # TODO: Call start here (num_nodes, num_req)
    ChordP2P.start(:normal, %{numNodes: num_nodes, numReq: num_req})
  end
end
