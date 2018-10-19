defmodule CP2P.Master do
  require Logger
  use GenServer

  def start_link(opts) do
    # Logger.debug("Inside start_link " <> inspect(_MODULE_) <> " " <> "with options: " <> inspect(opts))
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(args) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:begin, %{numNodes: num_nodes , numReq: num_req}}, _from, state) do
    Logger.debug("#{inspect(__MODULE__)} number of nodes: #{inspect(num_nodes)}, number of  Requests:#{inspect(num_req)}")

    first_node_info = nil

    spawn_nodes(1, num_nodes, first_node_info, num_req)

    {:reply, :ok, state}
  end

  defp spawn_nodes(i, num_nodes, first_node_info, num_req) do

    #TODO: Calculate m based on num nodes
    m = 8
    {:ok, node_pid} = DynamicSupervisor.start_child(CP2P.NodeSupervisor, {CP2P.Node, [num_req, m]})
    node_info = GenServer.call(node_pid, :get)
    Logger.debug("#{inspect(__MODULE__)} Starting node: #{inspect(i)}, node_info:#{inspect(node_info)}")
    Registry.register(CP2P.Registry.ProcReg, node_info.node_id, node_info)

    Logger.debug("#{inspect(__MODULE__)} First node_info:#{inspect(first_node_info)} for i:#{inspect i}")
    if(i > 1)do
      GenServer.cast(node_info.node_pid, {:join, first_node_info.node_pid})
    end

    if(i <= num_nodes) do
      if(i == 1)do
        spawn_nodes(i + 1, num_nodes, node_info, num_req)
      else
        spawn_nodes(i + 1, num_nodes, first_node_info, num_req)
      end
    end
  end

  # @impl true
  # def handle_cast({:push, item}, state) do
  #   {:noreply, [item | state]}
  # end
end
