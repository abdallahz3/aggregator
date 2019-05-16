defmodule AggregatorActor do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: AggregatorActor)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def new_message(msg) do
    GenServer.cast(AggregatorActor, {:new_message, msg})
  end

  def handle_cast({:new_message, msg}, state) do
    IO.puts("toz")

    msg
    |> convert_from_map_to_aggregator_structure()
    |> IO.inspect()

    {:noreply, state}
  end

  defp convert_from_map_to_aggregator_structure(m) do
    %AggregatorStructure{
      ask: m.ask,
      ask_size: m.ask_size,
      bid: m.bid,
      bid_size: m.bid_size,
      exchange: m.exchange,
      high: m.high,
      last_price: m.last_price,
      low: m.low,
      symbol: m.symbol,
      timestamp: DateTime.from_unix!(m.timestamp, :millisecond),
      volume: m.volume
    }
  end
end
