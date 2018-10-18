defmodule CP2P.Node do
  require Logger

  use GenServer

  ### Client APIs

  ## create a new Chord ring.
  def create() do
    predecessor = nil
    successor = self
  end

  #

  ### Join a Chord ring containing node n0.
  def join(n0) do
    predecessor = nil
    successor = n0.find_successor(self)
  end

  #

  ## called periodically. verifies this node's immediate
  ## successor, and tells the successor about n.
  def handle_info(:stabilize, state) do
    successor = state[:successor]
    x = successor[:predecessor]

    if belongs_to_range?(state[:node_id], successor[:node_id], x[:node_id]) do
      successor = x
    end

    # successor.notify(n)
    GenServer.cast(successor[:node_pid], {:notify, state})

    schedule_work(:stabilize, 2 * 1000)

    state = %{state | successor: successor}
  end

  ## n0 thinks it might be our predecessor.
  #  def notify(n0) do
  #    if (predecessor is nil or n0 belongs_to (predecessor, n)) do
  #      predecessor = n0;
  #    end
  #  end
  #

  ## called periodically. refreshes finger table entries.
  ## next stores the index of the next finger to fix.
  def handle_info(:fix_fingers, state) do
    # TODO: Add next to state

    m = state[:m]
    next = state[:next]
    finger = state[:ft]

    next = next + 1

    if next > m - 1 do
      next = 0
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

    state = {state | predecessor: predecessor}
  end

  # Server APIs
  def start_link(opts) do
    Logger.debug("#{inspect(__MODULE__)} Inside start_link with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(num_req) do
    # TODO: Pass num_nodes from the master
    Logger.debug("#{inspect(__MODULE__)} Inside init num requests: #{inspect(num_req)}")
    schedule_work(:send_msg, 1 * 1000)

    m = 8

    {hashed_hex_pid, _} =
      :crypto.hash(:sha512, :erlang.pid_to_list(self)) |> Base.encode16() |> Integer.parse(16)

    node_id = hashed_hex_pid |> rem(trunc(:math.pow(2, m)))

    Logger.debug("Hashed value: " <> inspect(hashed_hex_pid))

    {:ok,
     %CP2P.Node_info{
       node_id: node_id,
       successor: %{},
       predecessor: %{},
       node_pid: self(),
       ft: [],
       req_left: num_req
     }}
  end

  @impl true
  def handle_call(:process_msg, _from, state) do
    # TODO: Lookup required node in finger table
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:send_msg, state) do
    num_req = Map.get(state, :req_left)

    if num_req > 0 do
      # TODO: Choose random node
      random_node_id = 1

      GenServer.call(random_node_id, {:process_msg})

      # Decrement counter for this node
      new_state = %{state | req_left: num_req - 1}
      schedule_work(:send_msg, 1 * 1000)
      {:noreply, new_state}
    end
  end

  defp schedule_work(job_atom_id, time_interval) do
    # In 1 sec
    Process.send_after(self(), job_atom_id, time_interval)
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
