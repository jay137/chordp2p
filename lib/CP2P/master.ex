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
  def handle_call({:begin, args}, _from, state) do
    Logger.debug(inspect(args))
    # Logger.debug("Numnodes:" <> inspect(head) <> "  " <> "NumReq:" <> inspect(tail))
    {:reply, :ok, state}
  end

  # @impl true
  # def handle_cast({:push, item}, state) do
  #   {:noreply, [item | state]}
  # end
end
