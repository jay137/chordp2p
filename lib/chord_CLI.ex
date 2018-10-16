defmodule Chord_CLI do
  require Logger

  def main(args) do
    # {_, noflag_opts, _} = OptionParser.parse(args)
    Logger.debug(inspect(args) <> inspect(is_list(args)))

    {num_nodes, _} = Integer.parse(Enum.at(args, 0))
    {num_req, _} = Integer.parse(Enum.at(args, 1))
    Logger.debug(inspect(num_nodes) <> inspect(num_req))

    # TODO: Call start here (num_nodes, num_req)
    ChordP2P.start(:normal, [num_nodes, num_req])
  end
end
