defmodule HitBTCClient do
  use WebSockex

  def start_link(symbols) do
    WebSockex.start_link("wss://api.hitbtc.com/api/2/ws", __MODULE__, %{symbols_list: symbols})
  end

  def handle_connect(_conn, state) do
    IO.puts("Connected")

    symbols_ids =
      Enum.reduce(state.symbols_list, %{}, fn {a, b}, acc -> Map.put_new(acc, a, b) end)

    new_state = %{}
    new_state = put_in(new_state, [:symbols_ids], symbols_ids)

    s =
      Enum.reduce(state.symbols_list, %{}, fn {a, _}, acc ->
        acc = put_in(acc, [a], %{})
        acc = put_in(acc, [a, :orderbook], %{})
        acc
      end)

    new_state = Map.merge(new_state, s)

    # new_state = put_in new_state, [:btcusdt], %{}
    # new_state = put_in new_state, [:btcusdt, :orderbook], %{}

    Enum.each(state.symbols_list, fn {a, _} ->
      send_message(self(), subscription_to_orderbook_frame_jsonified(a))
      send_message(self(), subscription_to_ticker_frame_jsonified(a))
    end)

    {:ok, new_state}
  end

  def handle_frame({:text, msg}, state) do
    new_state =
      msg
      |> Jason.decode!()
      # |> IO.inspect()
      |> handle_received_message(state)

    {:ok, new_state}
  end

  def handle_frame(frame, state) do
    # IO.inspect(frame)
    {:ok, state}
  end

  def handle_received_message(%{"method" => "ticker", "params" => params}, state) do
    symbol = params["symbol"]
    symbol = state["symbols"][symbol]

    ask = symbol["ask"] || 0
    ask_size = symbol["ask_size"] || 0

    bid = symbol["bid"] || 0
    bid_size = symbol["bid_size"] || 0

    AggregatorActor.new_message(%{
      ask: ask,
      ask_size: ask_size,
      bid: bid,
      bid_size: bid_size,
      exchange: "hitbtc",
      high: params["high"],
      last_price: params["last"],
      low: params["low"],
      symbol: params["symbol"],
      timestamp: params["timestamp"],
      volume: params["volume"]
    })

    IO.puts("toz")

    state
  end

  def handle_received_message(%{"method" => "snapshotOrderbook"}, state) do
    state
  end

  def handle_received_message(
        %{
          "method" => "updateOrderbook",
          "params" => %{"ask" => ask, "bid" => bid, "symbol" => symbol, "timestamp" => timestamp}
        },
        state
      ) do
    new_state =
      if length(ask) > 0 do
        ask = hd(ask)

        state
        |> put_in(["symbols", symbol, "ask"], ask["price"])
        |> put_in(["symbols", symbol, "ask_size"], ask["size"])
      else
        state
      end

    new_state2 =
      if length(bid) > 0 do
        bid = hd(bid)

        new_state
        |> put_in(["symbols", symbol, "bid"], bid["price"])
        |> put_in(["symbols", symbol, "bid_size"], bid["size"])
      else
        new_state
      end

    new_state2
  end

  def handle_received_message(msg, state) do
    # IO.inspect(msg)
    state
  end

  def handle_cast({:send, {:text, msg} = frame}, state) do
    IO.puts("Sending frame with payload: #{msg}")
    {:reply, frame, state}
  end

  # Client API
  def send_message(process_name, msg) do
    WebSockex.cast(process_name, {:send, {:text, msg}})
  end

  # Helpers
  def subscription_to_ticker_frame_jsonified(symbol) do
    subscription_message =
      %{
        method: "subscribeTicker",
        params: %{
          symbol: symbol
        },
        id: 123
      }
      |> Jason.encode!()

    subscription_message
  end

  def subscription_to_orderbook_frame_jsonified(symbol) do
    subscription_message =
      %{
        method: "subscribeOrderbook",
        params: %{
          symbol: symbol
        },
        id: 123
      }
      |> Jason.encode!()

    subscription_message
  end

  def get_pair_as_atom(ch) do
    # the convention is that always the second element represents the pair
    [_, b | _] = String.split(ch, ".")
    String.to_atom(b)
  end
end
