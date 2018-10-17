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

    for i <- 1..num_nodes do

      {:ok, node_pid} = DynamicSupervisor.start_child(CP2P.NodeSupervisor, {CP2P.Node,  num_req})
      #Logger.debug("#{inspect(__MODULE__)} Starting node: #{inspect(i)}, pid:#{inspect(node_pid)}")
      Registry.register(CP2P.Registry.ProcReg, node_pid, i) #TODO: Create ring node id by hashing function

    end

    {:reply, :ok, state}
  end

  # @impl true
  # def handle_cast({:push, item}, state) do
  #   {:noreply, [item | state]}
  # end
end
