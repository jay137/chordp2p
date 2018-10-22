defmodule CP2P.Node do

  require Logger

  use GenServer

  ### Client APIs

  # Server APIs
  def start_link(opts) do
    ## ### ##Logger.debug("#{inspect(__MODULE__)} Inside start_link with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    [num_req | t] = opts
    [m | t] = t

    # ### ##Logger.debug("#{inspect(__MODULE__)} Inside init. Num requests: #{inspect(num_req)} and m: #{inspect(m)}")

    total_nodes = trunc(:math.pow(2, m))

    node_id = get_random_id_on_chord(m, :erlang.pid_to_list(self()))

    node_id = lookup_node_id(node_id, total_nodes)

    # ### ##Logger.debug("Hashed value: #{inspect(hashed_hex_pid)} and node id:#{inspect(node_id)}")

    # This acts as a presence marker for this node
    Registry.register(CP2P.Registry.ProcPresenceStamp, self(), true)

    schedule_work(:stabilize, 1)
    schedule_work(:fix_fingers, 1)
    schedule_work(:check_predecessor, 1)

    {:ok,
     %CP2P.Node_info{
       node_id: node_id,
       node_pid: self(),
       ft: Enum.map(1..m, fn _ -> nil end),
       m: m,
       req_left: num_req
     }}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  ## create a new Chord ring.
  @impl true
  def handle_call(:create, _from, state) do
    successor_id = state.node_id
    state = %{state | successor_id: successor_id}
    {:reply, :ok, state}
  end

  #
  ## ask node n to find the successor of id
  def handle_call({:find_successor, for_node_id}, _from, state) do
    successor_id_for_node_id = find_successor(for_node_id, state)
    {:reply, successor_id_for_node_id, state}
  end

  defp find_successor(for_node_id, state) do
    ##Logger.debug("#{inspect(__MODULE__)} :find_successor for node: #{inspect(for_node_id)} with state: #{inspect(state)}")
    successor_id = state.successor_id

    ## # ##Logger.debug("Successor in find_successor #{inspect(successor)} state: #{inspect(state)}")

    successor_id_for_node_id =
      if (successor_id != nil) and
         belongs_to_range?(state.node_id, successor_id + 1, for_node_id) do
        successor_id
      else
        closest_prec_node_id = find_closest_preceding_node_from_finger_table(for_node_id, state)

        if closest_prec_node_id == state.node_id do
          #Logger.debug("#{inspect __MODULE__} **Successor in find_successor for #{inspect(for_node_id)} is #{inspect state.successor.node_id} ")
          state.successor_id
        else
          closest_prec_node_state = get_latest_node_state(closest_prec_node_id, state)
          successor_id = GenServer.call(closest_prec_node_state.node_pid, {:find_successor, for_node_id})
          #Logger.debug("#{inspect __MODULE__} #*Successor in find_successor for #{inspect(for_node_id)} is #{inspect successor.node_id} ")
          successor_id
        end
      end
  end

  ### Join a Chord ring containing node `existing_node_info`
  def handle_cast({:join, existing_node_info}, state) do
    Logger.debug(
      "#{inspect(__MODULE__)} Join cast to existing_node: #{inspect(existing_node_info.node_id)} from : #{
        inspect(state.node_id)
      }"
    )

    predecessor_id = nil
    this_node_id = state.node_id
    successor_id = GenServer.call(existing_node_info.node_pid, {:find_successor, this_node_id})
    state = %{state | predecessor_id: predecessor_id}
    state = %{state | successor_id: successor_id}
    {:noreply, state}
  end

  def handle_call({:join, existing_node_info}, _from, state) do
    Logger.debug(
      "#{inspect(__MODULE__)} Join call to existing_node: #{inspect(existing_node_info.node_id)} from : #{
        inspect(state.node_id)
      }"
    )

    predecessor_id = nil
    this_node_id = state.node_id
    successor_id = GenServer.call(existing_node_info.node_pid, {:find_successor, this_node_id})
    state = %{state | predecessor_id: predecessor_id}
    state = %{state | successor_id: successor_id}
    {:reply, state, state}
  end

  @impl true
  def handle_info({:process_msg, id_on_chord_ring}, state) do
    # ##Logger.debug("#{inspect(__MODULE__)} Received :process_msg call on node - #{inspect(state.node_id)} for chord ring id - #{inspect(id_on_chord_ring)}")

    if id_on_chord_ring != state.node_id do
      send(self(), {:pass_msg_through_successor, id_on_chord_ring})
    end

    {:noreply, state}
  end

  def handle_info({:pass_msg_through_successor, for_node_id}, state) do
    # ##Logger.debug("#{inspect(__MODULE__)} :pass_msg_through_successor for node: #{inspect(for_node_id)}   with state: #{inspect(state)}")

    increment_hop_count()
    successor_id = state.successor_id

    ## # ##Logger.debug("Successor in find_successor #{inspect(successor)} state: #{inspect(state)}")

    if successor_id != nil and #if successor_id != nil and map_size(successor) > 0 and
       belongs_to_range?(state.node_id, successor_id + 1, for_node_id) do
      success_state = get_latest_node_state(successor_id, state)
      send(success_state.node_pid, {:process_msg, successor_id})
    else
      closest_prec_node_id = find_closest_preceding_node_from_finger_table(for_node_id, state)

      if closest_prec_node_id == state.node_id do
        state.successor_id
      else
        closest_prec_node_state = get_latest_node_state(closest_prec_node_id, state)
        send(closest_prec_node_state.node_pid, {:pass_msg_through_successor, for_node_id})
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:send_msg, state) do
    # # ##Logger.debug("#{inspect(__MODULE__)} Send message called for #{inspect(state.node_id)} with state: #{inspect(state)}")

    num_req = state.req_left
    send_msg_timeout = 100

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
      #Logger.debug("#{inspect __MODULE__} Print state #{inspect state}")
      {:noreply, state}
    end
  end

  ## called periodically. Verifies this node's immediate
  ## successor, and tells the successor about n.
  #TODO: Add stabilize for initial configuration
  def handle_info(:stabilize, state) do
    Logger.debug(
      "#{inspect(__MODULE__)} Running stabilize on #{inspect state.node_id} with successor - #{
        inspect state.successor_id
      } and pred - #{inspect state.predecessor_id}"
    )
    successor_id = state.successor_id

    successor_state =
      if successor_id != nil do
        success_state = get_latest_node_state(successor_id,  state)
      else
        nil
      end

    state =
      if successor_id != nil and successor_state != nil and successor_state.predecessor_id != nil do
        pred_id = successor_state.predecessor_id

        state =
          if belongs_to_range?(state.node_id, successor_id, pred_id) do
            Logger.debug(
              "#{inspect(__MODULE__)} Changing successor of #{inspect state.node_id} from #{
                inspect state.successor.node_id
              } to #{inspect(pred_id)}"
            )
            %{state | successor_id: pred_id}
          else
            state
          end
      else
        state
      end

    # successor.notify(n)
    if (successor_id != nil and state.node_id != successor_id) do
      success_state = get_latest_node_state(successor_id, state)
      send(success_state.node_pid, {:notify, state})
    end

    if state.req_left != 0 do
      schedule_work(:stabilize, 1 * 500)
    end

    {:noreply, state}
  end

  ## `predecessor_node_info` thinks it might be our predecessor, so it notifies this node
  def handle_info({:notify, predecessor_node_info}, state) do
    Logger.debug(
      "#{inspect __MODULE__} Received notify request from pred : #{
        inspect(predecessor_node_info.node_id)
      } to set it as pred for node : #{inspect(state.node_id)} "
    )
    predecessor_id = state.predecessor_id
    this_node_id = state.node_id

    predecessor =
      if predecessor_id == nil or
         belongs_to_range?(
           predecessor_id,
           this_node_id,
           predecessor_node_info.node_id
         )do
        Logger.debug(
          "#{inspect __MODULE__} Pred changed for node - #{inspect state.node_id} after notify: #{inspect(state)}"
        )
        predecessor_node_info.node_id
      else
        predecessor_id
      end

    state = %{state | predecessor_id: predecessor_id}

    {:noreply, state}
  end

  ## called periodically. refreshes finger table entries.
  ## next stores the index of the next finger to fix.
  def handle_info(:fix_fingers, state) do
    ##Logger.debug("Before :fix_fingers state #{inspect state}")

    successor_id = state.successor_id

    state =
      if successor_id != nil do
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

        successor_state = get_latest_node_state(successor_id, state)
        #Logger.debug("fix fingers : #{inspect state} find successor node id - #{inspect next }")
        next_successor_id =
          if(successor_state.node_pid == state.node_pid) do
            find_successor(successor_id, state)
          else
          GenServer.call(
            successor_state.node_pid,
            {:find_successor, state.node_id + :math.pow(2, next - 1)}
          )
          end

        finger = List.replace_at(finger, next, next_successor_id)

        state = %{state | ft: finger}
        %{state | next: next}
      else
        state
      end

    if state.req_left != 0 do
      schedule_work(:fix_fingers, 1 * 100)
    end

    ##Logger.debug("After :fix_fingers state #{inspect state}")

    {:noreply, state}
  end

  #
  ## called periodically. checks whether predecessor has failed.
  def handle_info(:check_predecessor, state) do
    ###Logger.debug("check_predecessor Before state: #{inspect(state)}")
    predecessor_id = state.predecessor_id

    state =
      if predecessor_id != nil do
        pred_state = get_latest_node_state(predecessor_id, state)
        pred_node_pid = pred_state.node_pid

        predecessor_id =
          if !Process.alive?(pred_node_pid) do
            nil
          else
            predecessor_id
          end

        %{state | predecessor_id: predecessor_id}
      else
        state
      end

    if state.req_left != 0 do
      schedule_work(:check_predecessor, 1 * 100)
    end

    ###Logger.debug("check_predecessor After state: #{inspect(state)}")
    {:noreply, state}
  end

  defp find_closest_preceding_node_from_finger_table(for_node_id, this_node_info) do
    finger = this_node_info.ft
    this_node_id = this_node_info.node_id
    m = this_node_info.m

    finger_entry = check_finger_table(m, this_node_id, for_node_id, finger)

    if finger_entry do
      finger_entry
    else
      this_node_info.node_id
    end
  end

  defp check_finger_table(0, _, _, _) do
    nil
  end

  defp check_finger_table(i, this_node_id, for_node_id, finger) do
    finger_entry =
      if Enum.at(finger, i) != nil and belongs_to_range?(this_node_id, for_node_id, Enum.at(finger, i)) do
        Enum.at(finger, i)
      else
        check_finger_table(i - 1, this_node_id, for_node_id, finger)
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
    # # ##Logger.debug("Before schedule #{inspect self()}")
    message_timer = Process.send_after(self(), job_atom_id, time_interval)
    # # ##Logger.debug("After schedule #{inspect self()}")
    # # ##Logger.debug("Message timer #{inspect job_atom_id} for self: #{inspect Process.read_timer(message_timer)}")
  end

  #range1, num, range2 should be in clockwise
  defp belongs_to_range?(range1, range2, num) do
    # start_num = Kernel.min(range1, range2)
    # end_num = Kernel.max(range1, range2)

    does_it_belong =
      cond do
        range1 < range2 ->
          if num > range1 and num < range2 do
            true
          else
            false
          end

        range2 < range1 ->
          if num > range1 and num < range2 do
            false
          else
            true
          end

        true ->
          false
      end

    does_it_belong
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
    # # ##Logger.debug("Inside increment hop count")
    hop_count_table = :ets.whereis(:ets_hop_count)
    :ets.update_counter(hop_count_table, :hop, 1, {1, 0})
  end

  defp get_latest_node_state(node_id, state) do
    node_state =
      if(node_id == state.node_id) do
        state
      else
        Logger.debug("#{inspect __MODULE__} node_id : #{inspect node_id} reg: #{inspect Registry.lookup(CP2P.Registry.ProcReg, node_id)}")
        [{_, node_info}] = Registry.lookup(CP2P.Registry.ProcReg, node_id)
        Logger.debug("#{inspect __MODULE__} node_info : #{inspect self()}")
        node_state = GenServer.call(node_info.node_pid, :get)
      end

  end

end
