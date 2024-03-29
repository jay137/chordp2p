defmodule CP2P.Node do

  require Logger

  use GenServer

  ### Client APIs

  # Server APIs
  def start_link(opts) do
    ## ### #Logger.debug("#{inspect(__MODULE__)} Inside start_link with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    [num_req | t] = opts
    [m | t] = t

    # ### #Logger.debug("#{inspect(__MODULE__)} Inside init. Num requests: #{inspect(num_req)} and m: #{inspect(m)}")

    total_nodes = trunc(:math.pow(2, m))

    node_id = get_random_id_on_chord(m, :erlang.pid_to_list(self()))

    node_id = lookup_node_id(node_id, total_nodes)

    # ### #Logger.debug("Hashed value: #{inspect(hashed_hex_pid)} and node id:#{inspect(node_id)}")

    # This acts as a presence marker for this node
    Registry.register(CP2P.Registry.ProcPresenceStamp, self(), true)

    schedule_work(:stabilize, 1)
    schedule_work(:fix_fingers, 1)
    schedule_work(:check_predecessor, 1)

    {:ok,
     %CP2P.Node_info{
       node_id: node_id,
       successor: nil,
       predecessor: nil,
       node_pid: self(),
       ft: Enum.map(1..m, fn _ -> nil end),
       m: m,
       req_left: num_req
       # other_node_ids: nil
     }}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  #
  #  def handle_call(:process_msg, _from, state) do
  #    ## #Logger.debug("#{inspect __MODULE__} Received :process_msg call on node - #{inspect state.node_id} from : #{inspect _from}")
  #    # TODO: Lookup required node in finger table
  #
  #    {:reply, :ok, state}
  #  end

  ## create a new Chord ring.
  @impl true
  def handle_call(:create, _from, state) do
    successor = state
    state = %{state | successor: successor}
    {:reply, :ok, state}
  end

  #
  ## ask node n to find the successor of id
  def handle_call({:find_successor, for_node_id}, _from, state) do
    successor_for_node_id = find_successor(for_node_id, state)
    {:reply, successor_for_node_id, state}
  end

  defp find_successor(for_node_id, state) do
    #Logger.debug("#{inspect(__MODULE__)} :find_successor for node: #{inspect(for_node_id)} with state: #{inspect(state)}")
    #increment_hop_count()
    successor = state.successor

    ## # #Logger.debug("Successor in find_successor #{inspect(successor)} state: #{inspect(state)}")

    successor_for_node_id =
      if map_size(successor) > 0 and
         belongs_to_range?(state.node_id, successor.node_id + 1, for_node_id, state.m) do
        successor
      else
        closest_prec_node_info = find_closest_preceding_node_from_finger_table(for_node_id, state)

        if closest_prec_node_info.node_id == state.node_id do
          state.successor
        else
          GenServer.call(closest_prec_node_info.node_pid, {:find_successor, for_node_id})
        end
      end
  end

  ### Join a Chord ring containing node `existing_node_info`
  def handle_cast({:join, existing_node_info}, state) do
    #Logger.debug("#{inspect(__MODULE__)} Join existing_node_info: #{inspect(existing_node_info)}, state: #{inspect(state)}")

    predecessor = nil
    this_node_id = state.node_id
    successor = GenServer.call(existing_node_info.node_pid, {:find_successor, this_node_id})
    state = %{state | predecessor: predecessor}
    state = %{state | successor: successor}
    {:noreply, state}
  end

  @impl true
  def handle_info({:process_msg, id_on_chord_ring}, state) do
    # #Logger.debug("#{inspect(__MODULE__)} Received :process_msg call on node - #{inspect(state.node_id)} for chord ring id - #{inspect(id_on_chord_ring)}")

    if id_on_chord_ring != state.node_id do
      send(self(), {:pass_msg_through_successor, id_on_chord_ring})
    end

    {:noreply, state}
  end

  def handle_info({:pass_msg_through_successor, for_node_id}, state) do
    # #Logger.debug("#{inspect(__MODULE__)} :pass_msg_through_successor for node: #{inspect(for_node_id)}   with state: #{inspect(state)}")

    increment_hop_count()
    successor = state.successor

    ## # #Logger.debug("Successor in find_successor #{inspect(successor)} state: #{inspect(state)}")

    if successor != nil and map_size(successor) > 0 and
       belongs_to_range?(state.node_id, successor.node_id + 1, for_node_id, state.m) do
      send(successor.node_pid, {:process_msg, successor.node_id})
    else
      closest_prec_node_info = find_closest_preceding_node_from_finger_table(for_node_id, state)

      if closest_prec_node_info.node_id == state.node_id do
        state.successor
      else
        send(closest_prec_node_info.node_pid, {:pass_msg_through_successor, for_node_id})
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:send_msg, state) do
    # # #Logger.debug("#{inspect(__MODULE__)} Send message called for #{inspect(state.node_id)} with state: #{inspect(state)}")

    num_req = state.req_left
    # other_node_ids = state.other_node_ids
    # 1 * 1000
    send_msg_timeout = 1

    if num_req > 0 do
      rand_key_on_ring = :rand.uniform(trunc(:math.pow(2, state.m)))
      random_key_on_chord = get_random_id_on_chord(state.m, Integer.to_string(rand_key_on_ring))

      send(self(), {:process_msg, random_key_on_chord})

      # Decrement counter for this node
      new_state = %{state | req_left: num_req - 1}
      schedule_work(:send_msg, send_msg_timeout)
      {:noreply, new_state}
    else
      Registry.unregister(CP2P.Registry.ProcPresenceStamp, self())
      {:noreply, state}
    end
  end

  ## called periodically. Verifies this node's immediate
  ## successor, and tells the successor about n.
  def handle_info(:stabilize, state) do
    successor = state.successor

    state =
      if successor != nil and successor.predecessor != nil do
        x = successor.predecessor

        successor =
          if belongs_to_range?(state.node_id, successor.node_id, x.node_id, state.m) do
            x
          else
            successor
          end

        %{state | successor: successor}
      else
        state
      end

    # successor.notify(n)
    if (state.successor != nil) do
      send(state.successor.node_pid, {:notify, state})
    end


    if state.req_left != 0 do
      schedule_work(:stabilize, 2 * 1000)
    end

    {:noreply, state}
  end

  ## called periodically. refreshes finger table entries.
  ## next stores the index of the next finger to fix.
  def handle_info(:fix_fingers, state) do
    Logger.debug("Before :fix_fingers state #{inspect state}")

    successor = state.successor

    state =
      if successor != nil do
        m = state.m
        next = state.next
        finger = state.ft

        next = next + 1

        next =
          if next > m - 1 do
            0
          else
            next
          end

        Logger.debug("fix fingers : #{inspect state} find successor node id - #{inspect next }")
        next_successor =
          if(successor.node_pid == state.node_pid) do
            find_successor(successor.node_id, state)
          else
          GenServer.call(
            successor.node_pid,
            {:find_successor, state.node_id + :math.pow(2, next - 1)}
          )
          end

        finger = List.replace_at(finger, next, next_successor)

        state = %{state | ft: finger}
        %{state | next: next}
      else
        state
      end

    if state.req_left != 0 do
      schedule_work(:fix_fingers, 1 * 10)
    end

    #Logger.debug("After :fix_fingers state #{inspect state}")

    {:noreply, state}
  end

  #
  ## called periodically. checks whether predecessor has failed.
  def handle_info(:check_predecessor, state) do
    ##Logger.debug("check_predecessor Before state: #{inspect(state)}")
    predecessor = state.predecessor

    state =
      if predecessor != nil do
        pred_node_pid = predecessor.node_pid

        predecessor =
          if !Process.alive?(pred_node_pid) do
            nil
          else
            predecessor
          end

        %{state | predecessor: predecessor}
      else
        state
      end

    if state.req_left != 0 do
      schedule_work(:check_predecessor, 2 * 1000)
    end

    ##Logger.debug("check_predecessor After state: #{inspect(state)}")
    {:noreply, state}
  end

  ## n0 thinks it might be our predecessor, so it notifies this node
  def handle_info({:notify, predecessor_node_info}, state) do
    #Logger.debug("notify Before state: #{inspect(state)}")
    predecessor = state.predecessor
    this_node_id = state.node_id

    predecessor =
      if predecessor == nil or
           belongs_to_range?(
             predecessor.node_id,
             this_node_id,
             predecessor_node_info.node_id,
             state.m
           ) do
        predecessor_node_info
      else
        predecessor
      end

    state = %{state | predecessor: predecessor}
    #Logger.debug("notify After state: #{inspect(state)}")
    {:noreply, state}
  end

  defp find_closest_preceding_node_from_finger_table(for_node_id, this_node_info) do
    finger = this_node_info.ft
    this_node_id = this_node_info.node_id
    m = this_node_info.m

    finger_entry = check_finger_table(m, this_node_id, for_node_id, finger, m)

    if finger_entry do
      finger_entry
    else
      this_node_info
    end
  end

  defp check_finger_table(0, _, _, _, _) do
    nil
  end

  defp check_finger_table(i, this_node_id, for_node_id, finger, m) do
    finger_entry =
      if Enum.at(finger, i) != nil and belongs_to_range?(this_node_id, for_node_id, Enum.at(finger, i).node_id, m) do
        Enum.at(finger, i)
      else
        check_finger_table(i - 1, this_node_id, for_node_id, finger, m)
      end
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
    # # #Logger.debug("Before schedule #{inspect self()}")
    message_timer = Process.send_after(self(), job_atom_id, time_interval)
    # # #Logger.debug("After schedule #{inspect self()}")
    # # #Logger.debug("Message timer #{inspect job_atom_id} for self: #{inspect Process.read_timer(message_timer)}")
  end

  #  defp belongs_to_range?(range1, range2, num) do
  #    start_num = Kernel.min(range1, range2)
  #    end_num = Kernel.max(range1, range2)
  #
  #    if num > start_num and num < end_num do
  #      true
  #    else
  #      false
  #    end
  #  end

  defp belongs_to_range?(range1, range2, num, m) do
    # start_num = Kernel.min(range1, range2)
    # end_num = Kernel.max(range1, range2)

    Logger.debug("range1: #{inspect range1}, range2: #{inspect range2}, num: #{inspect num}, m: #{inspect m}")

    [adjustment, range1] =
      if range1 > range2 do
        [rem(range1, trunc(:math.pow(2, m))), 0]
      else
        [0, range1]
      end

    Logger.debug("adjustment : #{inspect adjustment}, range1 : #{inspect range1}, range2 : #{inspect range2}")
    num = num + adjustment
    range2 = range2 + adjustment

    if num > range1 and num < range2 do
            true
          else
            false
          end

  end

  defp get_random_id_on_chord(m, val_to_be_hashed) do
    total_nodes = trunc(:math.pow(2, m))

    {hashed_hex_pid, _} =
      :crypto.hash(:sha512, val_to_be_hashed)
      |> Base.encode16()
      |> Integer.parse(16)

    node_id =
      hashed_hex_pid
      |> rem(total_nodes)
  end

  defp increment_hop_count() do
    # # #Logger.debug("Inside increment hop count")
    hop_count_table = :ets.whereis(:ets_hop_count)
    :ets.update_counter(hop_count_table, :hop, 1, {1, 0})
  end
end
