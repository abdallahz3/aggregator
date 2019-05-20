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
    msg
    |> convert_from_map_to_aggregator_structure()
    |> IO.inspect()

    {:noreply, state}
  end

  defp convert_from_map_to_aggregator_structure(m) do
    %AggregatorStructure{
      ask: m.orderbook[:ask],
      ask_size: m.orderbook[:ask_size],
      bid: m.orderbook[:bid],
      bid_size: m.orderbook[:bid_size],
      exchange: m[:exchange_id],
      high: m[:high],
      last_price: m[:last_price],
      low: m[:low],
      symbol: m[:symbol],
      timestamp: DateTime.from_unix!(m[:timestamp], :millisecond),
      volume: m[:volume]
    }
  end
end
