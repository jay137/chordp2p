defmodule CP2P.Master do
  require Logger
  use GenServer

  def start_link(opts) do
    # ####Logger.debug("Inside start_link " <> inspect(_MODULE_) <> " " <> "with options: " <> inspect(opts))
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(args) do
    table = :ets.new(:ets_hop_count, [:public, :named_table])
    #Logger.debug("#{inspect(__MODULE__)} table: #{inspect(table)}")
    {:ok, %{hop_count_table: table}}
  end

  @impl true
  def handle_call({:begin, %{numNodes: num_nodes, numReq: num_req}}, _from, state) do
    # ###Logger.debug("#{inspect(__MODULE__)} number of nodes: #{inspect(num_nodes)}, number of  Requests:#{inspect(num_req)}")

    first_node_info = nil

    spawn_nodes(1, num_nodes, first_node_info, num_req)

    node_id_list = Registry.keys(CP2P.Registry.ProcReg, self())

    Logger.debug("Before sleep")
    Process.sleep(10 * 1000)
    Logger.debug("After sleep")

    # Start messaging
    for node_id <- node_id_list do
      [{_, node_info}] = Registry.lookup(CP2P.Registry.ProcReg, node_id)

      # #Logger.debug("Before send message #{inspect node_info} alive:#{inspect Process.alive?(node_info.node_pid)}")
      send(node_info.node_pid, :send_msg)
    end

    wait_for_worker_nodes()

    {:reply, calc_avg_hops(state, num_nodes, num_req), state}
  end

  defp wait_for_worker_nodes() do
    # 3 second
    Process.sleep(3 * 1000)
    num_working_nodes = Registry.count(CP2P.Registry.ProcPresenceStamp)
    ## #Logger.debug("#{inspect(__MODULE__)} Nodes: #{inspect(num_working_nodes)}")

    if(num_working_nodes > 0) do
      wait_for_worker_nodes()
    end
  end

  defp spawn_nodes(i, num_nodes, first_node_info, num_req) do

    m = trunc(:math.log2(3 * num_nodes))
    #Logger.debug("#{inspect __MODULE__} M = #{inspect m}")

    {:ok, node_pid} =
      DynamicSupervisor.start_child(CP2P.NodeSupervisor, {CP2P.Node, [num_req, m]})

    node_info = GenServer.call(node_pid, :get)

    # ###Logger.debug("#{inspect(__MODULE__)} Starting node: #{inspect(i)}, node_info:#{inspect(node_info)}")
    Registry.register(CP2P.Registry.ProcReg, node_info.node_id, node_info)

    ###Logger.debug("#{inspect(__MODULE__)} First node_info:#{inspect(first_node_info)} for i:#{inspect i}")
    if(i == 1) do
      GenServer.call(node_info.node_pid, :create)
    else
      successor_id = GenServer.call(first_node_info.node_pid, {:find_successor, node_info.node_id})
      Logger.debug("#{inspect(__MODULE__)} successor for #{inspect node_info.node_id} is #{inspect successor_id}")
      GenServer.call(node_info.node_pid, {:join, first_node_info})
    end

    #Logger.debug("#{inspect(__MODULE__)} Spawned node  #{inspect(node_info)}")

    first_node_info =
      if i == 1 do
        node_info
      else
        first_node_info
      end

    if(i < num_nodes) do
      spawn_nodes(i + 1, num_nodes, first_node_info, num_req)
    end
  end

  defp calc_avg_hops(state, num_nodes, num_req) do
    # :ets.whereis(:ets_hop_count)
    hop_count_table = Map.get(state, :hop_count_table)
    #Logger.debug("state : #{inspect(state)} table: #{inspect(hop_count_table)}")
    [{_, total_hops}] = :ets.lookup(hop_count_table, :hop)
    avg_lookup_hops = total_hops / (num_nodes * num_req)
    avg_lookup_hops
  end

end
