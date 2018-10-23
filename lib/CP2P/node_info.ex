defmodule CP2P.Node_info do
  @moduledoc false

  '''
    node_state should be provided by implementing algorithm
  '''

  defstruct node_id: -1,
            successor: nil,
            predecessor: nil,
            node_pid: nil,
            ft: [],
            req_left: 0,
            m: -1,
            next: -1
end
