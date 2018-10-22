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
    # Logger.debug("#{inspect(__MODULE__)} table: #{inspect(table)}")
    {:ok, %{hop_count_table: table}}
  end

  @impl true
  def handle_call({:begin, %{numNodes: num_nodes, numReq: num_req}}, _from, state) do
    # ###Logger.debug("#{inspect(__MODULE__)} number of nodes: #{inspect(num_nodes)}, number of  Requests:#{inspect(num_req)}")

    first_node_info = nil

    spawn_nodes(1, num_nodes, first_node_info, num_req)

    node_id_list = Registry.keys(CP2P.Registry.ProcReg, self())

    node_info_list =
      Enum.map(
        node_id_list,
        fn node_id ->
          [{_, node_info}] = Registry.lookup(CP2P.Registry.ProcReg, node_id)
          node_info
        end
      )

    # #Logger.debug("#{inspect(__MODULE__)} node info list: #{inspect(node_info_list)}")
    # node_id_to_pid_map = Enum.group_by(node_info_list, & &1.node_id, & &1.node_pid)
    node_id_to_pid_map =
      Enum.group_by(node_info_list, &Map.get(&1, :node_id), &Map.get(&1, :node_pid))

    # Logger.debug("Master pid : #{inspect(self())} Node id to pid map : #{inspect(node_id_to_pid_map)}")

    # Set other node pid list for each node
    #    for node_id <- node_id_list do
    #      [{_, node_info}] = Registry.lookup(CP2P.Registry.ProcReg, node_id)
    #
    #      other_node_id_to_pid_map = Map.delete(node_id_to_pid_map, node_id)
    #      other_node_id_list = List.flatten(Map.keys(other_node_id_to_pid_map))
    #      #Logger.debug("Other node id list: #{inspect(other_node_id_list)} for node id: #{inspect(node_id)}")
    #
    #      # Set other node pid list
    #      :ok = GenServer.call(node_info.node_pid, {:update_node_ids_in_state, other_node_id_list})
    #    end

    # Start messaging
    Logger.debug("Before Sleep")
    Process.sleep(10 * 1000)
    Logger.debug("After Sleep")

    for node_id <- node_id_list do
      [{_, node_info}] = Registry.lookup(CP2P.Registry.ProcReg, node_id)

      Logger.debug(
        "Before send message #{inspect(node_info)} alive:#{
          inspect(Process.alive?(node_info.node_pid))
        }"
      )

      send(node_info.node_pid, :send_msg)
      # GenServer.cast(node_info.node_pid, :send_msg)
    end

    wait_for_worker_nodes()

    # TODO: Return average number of hops for all nodes

    # :ets.whereis(:ets_hop_count)
    hop_count_table = Map.get(state, :hop_count_table)
    # Logger.debug("state : #{inspect(state)} table: #{inspect(hop_count_table)}")
    [{_, total_hops}] = :ets.lookup(hop_count_table, :hop)
    # Logger.debug("total_hops: #{inspect(total_hops)}")
    avg_lookup_hops = total_hops / num_nodes
    {:reply, avg_lookup_hops, state}
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
    # TODO: Calculate m based on num nodes
    m = 10

    {:ok, node_pid} =
      DynamicSupervisor.start_child(CP2P.NodeSupervisor, {CP2P.Node, [num_req, m]})

    node_info = GenServer.call(node_pid, :get)

    # ###Logger.debug("#{inspect(__MODULE__)} Starting node: #{inspect(i)}, node_info:#{inspect(node_info)}")
    Registry.register(CP2P.Registry.ProcReg, node_info.node_id, node_info)

    ### Logger.debug("#{inspect(__MODULE__)} First node_info:#{inspect(first_node_info)} for i:#{inspect i}")
    if(i == 1) do
      GenServer.call(node_info.node_pid, :create)
    else
      GenServer.cast(node_info.node_pid, {:join, first_node_info})
    end

    ## #Logger.debug("***")

    Logger.debug("#{inspect(__MODULE__)} Spawned node  #{inspect(node_info)}")

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
end
