defmodule CP2P.Node do

  require Logger

  use GenServer

  def start_link(opts) do
    Logger.debug("#{inspect(__MODULE__)} Inside start_link  with options: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(num_req) do
    Logger.debug("#{inspect(__MODULE__)} Inside init  num requests: #{inspect(num_req)}")
    {:ok, %{req_left: num_req}}
  end

  @impl true
  def handle_call(:pop, _from, [head | tail]) do

    {:reply, head, tail}
  end

end
