defmodule CP2P.Node_info do
  @moduledoc false

  '''
    node_state should be provided by implementing algorithm
  '''

  defstruct node_id: -1, successor: %{}, predecessor: %{}, node_pid: nil

end