defmodule CP2P.Node do
  require Logger

  use GenServer

  ### Client APIs

  # Server APIs
  def start_link(opts) do
    ## Logger.debug("#{inspect(__MODULE__)} Inside start_link with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    [num_req | t] = opts
    [m | t] = t

    # Logger.debug("#{inspect(__MODULE__)} Inside init. Num requests: #{inspect(num_req)} and m: #{inspect(m)}")

    total_nodes = trunc(:math.pow(2, m))

    {hashed_hex_pid, _} =
      :crypto.hash(:sha512, :erlang.pid_to_list(self)) |> Base.encode16() |> Integer.parse(16)

    node_id =
      hashed_hex_pid
      |> rem(total_nodes)

    node_id = lookup_node_id(node_id, total_nodes)

    # Logger.debug("Hashed value: #{inspect(hashed_hex_pid)} and node id:#{inspect(node_id)}")

    # * 1000)
    # schedule_work(:send_msg, 1)

    {:ok,
     %CP2P.Node_info{
       node_id: node_id,
       successor: %{},
       predecessor: %{},
       node_pid: self(),
       ft: [],
       m: m,
       req_left: num_req,
       other_node_pids: nil
     }}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:process_msg, _from, state) do
    # Logger.debug("#{inspect __MODULE__} Received :process_msg call on node - #{inspect state.node_id}")
    # TODO: Lookup required node in finger table

    {:reply, :ok, state}
  end

  ## create a new Chord ring.
  #  def create() do
  #    predecessor = nil
  #    successor = self()
  #  end

  #

  ## ask node n to find the successor of id
  def handle_call({:find_successor, for_node_id}, _from, state) do
    successor = state[:successor]

    successor_for_node_id =
      if belongs_to_range?(state[:node_id], successor[:node_id] + 1, for_node_id) do
        successor
      else
        # TODO: Change to local function call
        closest_prec_node_info = find_closest_preceding_node_from_finger_table(for_node_id, state)
        GenServer.call(closest_prec_node_info[:node_pid], {:find_successor, for_node_id})
      end

    {:reply, successor_for_node_id, state}
  end

  @impl true
  def handle_call({:update_node_pids_in_state, other_node_pids}, _from, state) do
    state = %{state | other_node_pids: other_node_pids}
    {:reply, state, state}
  end

  #  ## search the local table for the highest predecessor of id
  #  def handle_call({:closest_preceding_node, for_node_id}, _from, state) do
  #    closest_preceding_node_info = find_closest_preceding_node_from_finger_table for_node_id, state
  #    {:reply, closest_preceding_node_info, state}
  #  end

  ### Join a Chord ring containing node `existing_node_info`
  @impl true
  def handle_cast({:join, existing_node_info}, state) do
    predecessor = nil
    this_node_id = state[:node_id]
    successor = GenServer.call(existing_node_info[:node_pid], {:find_successor, this_node_id})
    state = %{state | predecessor: predecessor}
    state = %{state | successor: successor}
  end

  @impl true
  def handle_info(:send_msg, state) do
    Logger.debug(
      "#{inspect(__MODULE__)} Send message called for #{inspect(state.node_id)} with state: #{
        inspect(state)
      }"
    )

    num_req = Map.get(state, :req_left)
    other_node_pids = state.other_node_pids
    # 1 * 1000
    send_msg_timeout = 1

    if num_req > 0 do
      call_to_random_node_pid = Enum.random(other_node_pids)
      GenServer.call(call_to_random_node_pid, {:process_msg})

      # Decrement counter for this node
      new_state = %{state | req_left: num_req - 1}
      schedule_work(:send_msg, send_msg_timeout)
      {:noreply, new_state}
    end
  end

  ## called periodically. Verifies this node's immediate
  ## successor, and tells the successor about n.
  def handle_info(:stabilize, state) do
    successor = state[:successor]
    x = successor[:predecessor]

    successor =
      if belongs_to_range?(state[:node_id], successor[:node_id], x[:node_id]) do
        x
      end

    # successor.notify(n)
    GenServer.cast(successor[:node_pid], {:notify, state})

    schedule_work(:stabilize, 2 * 1000)

    state = %{state | successor: successor}
  end

  ## called periodically. refreshes finger table entries.
  ## next stores the index of the next finger to fix.
  def handle_info(:fix_fingers, state) do
    # TODO: Add next to state

    m = state[:m]
    next = state[:next]
    finger = state[:ft]

    next = next + 1

    next =
      if next > m - 1 do
        0
      end

    # find(successor(n + :math.pow(2, next - 1)))
    successor = state[:successor]

    # finger[next] = find(successor(n + :math.pow(2, next - 1)))
    next_successor =
      GenServer.call(
        successor[:node_pid],
        {:find_successor, state[:node_id] + :math.pow(2, next - 1)}
      )

    schedule_work(:fix_fingers, 2 * 1000)

    List.replace_at(finger, next, next_successor)

    state = %{state | ft: finger}
    state = %{state | next: next}
  end

  #
  ## called periodically. checks whether predecessor has failed.
  def handle_info(:check_predecessor, state) do
    predecessor = state[:predecessor]
    pred_node_pid = predecessor[:node_pid]

    predecessor =
      if !Process.alive?(pred_node_pid) do
        nil
      else
        predecessor
      end

    schedule_work(:check_predecessor, 2 * 1000)

    state = %{state | predecessor: predecessor}
  end

  ## n0 thinks it might be our predecessor, so it notifies this node
  def handle_info({:notify, predecessor_node_info}, state) do
    predecessor = state[:predecessor]
    this_node_id = state[:node_id]

    predecessor =
      if predecessor == nil or
           belongs_to_range?(
             predecessor_node_info[:node_id],
             this_node_id,
             predecessor[:node_id]
           ) do
        predecessor_node_info
      else
        predecessor
      end

    state = %{state | predecessor: predecessor}
  end

  defp find_closest_preceding_node_from_finger_table(for_node_id, this_node_info) do
    finger = this_node_info[:ft]
    this_node_id = this_node_info[:node_id]
    m = this_node_info[:m]

    for i <- m..1 do
      if belongs_to_range?(this_node_id, for_node_id, finger[i]) do
        finger[i]
      end
    end

    this_node_info
  end

  defp lookup_node_id(this_node_id, total_nodes) do
    node_id_lookup = Registry.lookup(CP2P.Registry.ProcReg, this_node_id)

    if node_id_lookup != [] do
      this_node_id = Enum.random(1..(total_nodes - 1))
      lookup_node_id(this_node_id, total_nodes)
    else
      this_node_id
    end
  end

  defp schedule_work(job_atom_id, time_interval) do
    message_timer = Process.send_after(self(), job_atom_id, time_interval)

    Logger.debug(
      "Message timer #{inspect(job_atom_id)} for self: #{
        inspect(Process.read_timer(message_timer))
      }"
    )
  end

  defp belongs_to_range?(range1, range2, num) do
    start_num = Kernel.min(range1, range2)
    end_num = Kernel.max(range1, range2)

    if num > start_num and num < end_num do
      true
    else
      false
    end
  end
end
