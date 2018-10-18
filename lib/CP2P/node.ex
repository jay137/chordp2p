defmodule CP2P.Node do

  require Logger

  use GenServer

  ###Client APIs

  ##create a new Chord ring.
  def create() do
    predecessor = nil
    successor = self
  end
  #

  ###Join a Chord ring containing node n0.
  def join(n0) do
    predecessor = nil;
    successor = n0.find_successor(self)
  end
  #

  ##called periodically. verifies n’s immediate
  ##successor, and tells the successor about n.
  def handle_info(:stabilize, state) do
    #x = successor.predecessor
    #if (belongs_to_range?(self, successor, x)) do
      #successor = x
    #end
    #successor.notify(n)
  end
  #

  ## n0 thinks it might be our predecessor.
  #  def notify(n0) do
  #    if (predecessor is nil or n0 belongs_to (predecessor, n)) do
  #      predecessor = n0;
  #    end
  #  end
  #

  ## called periodically. refreshes finger table entries.
  ## next stores the index of the next finger to fix.
  # def fix_fingers() do
  #  next = next + 1;
  #  if (next > m) do
  #    next = 1;
  #  end
  #  finger[next] = find successor(n + :math.pow(2,next-1))
  # end

  #
  ## called periodically. checks whether predecessor has failed.
  # def check_predecessor() do
  #   if (predecessor has failed)
  #     predecessor = nil;
  # end



  # Server APIs
  def start_link(opts) do
    Logger.debug("#{inspect(__MODULE__)} Inside start_link with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(num_req) do
    Logger.debug("#{inspect(__MODULE__)} Inside init num requests: #{inspect(num_req)}")
    schedule_work(:send_msg, 1 * 1000)
    {:ok, %{req_left: num_req}}
  end

  @impl true
  def handle_call(:process_msg, _from, state) do
    #TODO: Lookup required node in finger table
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:send_msg, state) do
    num_req = Map.get(state, :req_left)

    if num_req > 0 do
      #TODO: Choose random node
      random_node_id = 1

      GenServer.call(random_node_id, {:process_msg})

      #Decrement counter for this node
      new_state = %{state | req_left: num_req - 1}
      schedule_work(:send_msg, 1 * 1000)
      {:noreply, new_state}
    end
  end

  defp schedule_work(job_atom_id, time_interval) do
    Process.send_after(self(), job_atom_id, time_interval) # In 1 sec
  end

  defp belongs_to_range?(range1, range2, num) do
    true
  end

end
