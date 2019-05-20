defmodule PoloniexClient do
  use WebSockex

  # state looks like this
  # {
  #    btcusdt: {
  #        ...
  #    },
  #    ethbtc: {
  #        ...
  #    },
  #    symbols_ids: {
  #       ... which maps form pair like this `btcusdt` to `btc_usdt` as this is a requirement from the
  #               the technical document
  #    }
  # }
  #
  #
  # user id     key                         secret
  # up121053284	if9ginGbEuq5wGpLF4cKMlAFG0	csdt9r7TpoFUaqGApZJdwGKWz2s

  #   {
  #     "e": "auth",
  #     "auth": {
  #       "key": "if9ginGbEuq5wGpLF4cKMlAFG0.",
  #       "signature": "'13b8b109b06b4d867410d0aff7169065b92316e21c2f35cf5b0240b2777aa0e4'",
  #       "timestamp": 1558258488
  #     }
  # }

  def start_link(symbols) do
    WebSockex.start_link("wss://api2.poloniex.com", __MODULE__, %{symbols_list: symbols})
  end

  def handle_connect(_conn, state) do
    IO.puts("Connected")

    # send_message(self(), subscription_to_ticker_frame_jsonified(""))
    send_message(self(), subscription_to_orderbook_frame_jsonified(""))


    # symbols_ids =
    #   Enum.reduce(state.symbols_list, %{}, fn {a, b}, acc -> Map.put_new(acc, a, b) end)

    # new_state = %{}
    # new_state = put_in(new_state, [:symbols_ids], symbols_ids)

    # s =
    #   Enum.reduce(state.symbols_list, %{}, fn {a, _}, acc ->
    #     acc = put_in(acc, [a], %{})
    #     acc = put_in(acc, [a, :orderbook], %{ask: 0, bid: 0, ask_size: 0, bid_size: 0})
    #     acc
    #   end)

    # new_state = Map.merge(new_state, s)

    # IO.inspect new_state

    # Enum.each(state.symbols_list, fn {a, _} ->
    #   send_message(self(), subscription_to_orderbook_frame_jsonified(a))
    #   send_message(self(), subscription_to_ticker_frame_jsonified(a))
    # end)

    # {:ok, new_state}
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    new_state =
      msg
      |> Jason.decode!()
      |> IO.inspect()

    # |> handle_received_message(state)

    {:ok, new_state}
  end

  def handle_frame(frame, state) do
    IO.inspect(frame)
    {:ok, state}
  end

  def handle_received_message(%{"e" => "ping"}, state) do
    IO.puts("Got a ping")

    m =
      %{
        "e" => "pong"
      }
      |> Jason.encode!()

    send_message(self(), m)

    state
  end

  def handle_received_message(
        %{"data" => %{"ok" => "ok"}, "e" => "auth", "ok" => "ok"},
        state
      ) do
    symbols_ids =
      Enum.reduce(state.symbols_list, %{}, fn {a, b}, acc -> Map.put_new(acc, a, b) end)

    new_state = %{}
    new_state = put_in(new_state, [:symbols_ids], symbols_ids)

    s =
      Enum.reduce(state.symbols_list, %{}, fn {a, _}, acc ->
        acc = put_in(acc, [a], %{})
        acc = put_in(acc, [a, :orderbook], %{ask: 0, bid: 0, ask_size: 0, bid_size: 0})
        acc
      end)

    new_state = Map.merge(new_state, s)

    IO.inspect(new_state)

    Enum.each(state.symbols_list, fn {a, _} ->
      nil
      # send_message(self(), subscription_to_orderbook_frame_jsonified(a))
      # send_message(self(), subscription_to_ticker_frame_jsonified(a))
    end)

    send_message(self(), subscription_to_ticker_frame_jsonified("toz"))

    {:ok, new_state}
  end

  # def handle_received_message(%{"method" => "ticker", "params" => params}, state) do
  #   # AggregatorActor.new_message(%{
  #   #   ask: ask,
  #   #   ask_size: ask_size,
  #   #   bid: bid,
  #   #   bid_size: bid_size,
  #   #   exchange: "hitbtc",
  #   #   high: params["high"],
  #   #   last_price: params["last"],
  #   #   low: params["low"],
  #   #   symbol: params["symbol"],
  #   #   timestamp: params["timestamp"],
  #   #   volume: params["volume"]
  #   # })

  #   # state

  #   pair_as_atom = get_pair_as_atom(params["symbol"])

  #   new_pair =
  #     state[pair_as_atom]
  #     |> Map.put(:high, params["high"])
  #     |> Map.put(:low, params["low"])
  #     |> Map.put(:timestamp, params["timestamp"])
  #     |> Map.put(:volume, params["volume"])
  #     |> Map.put(:exchange_id, "hitbtc")
  #     # |> Map.put(:symbol, state.symbols_ids[pair])
  #     |> Map.put(:last_price, params["last"])

  #   new_state = Map.put(state, pair_as_atom, new_pair)

  #   IO.inspect(state)

  #   new_state
  # end

  # def handle_received_message(%{"method" => "snapshotOrderbook"}, state) do
  #   state
  # end

  # def handle_received_message(
  #       %{
  #         "method" => "updateOrderbook",
  #         "params" => %{
  #           "ask" => asks,
  #           "bid" => bids,
  #           "symbol" => symbol,
  #           "timestamp" => timestamp
  #         }
  #       },
  #       state
  #     ) do
  #   pair_as_atom = get_pair_as_atom(symbol)

  #   new_pair =
  #     state[pair_as_atom]
  #     |> put_in([:orderbook, :bid], get_best_bid(bids))
  #     |> put_in([:orderbook, :ask], get_best_ask(asks))
  #     |> put_in([:orderbook, :bid_size], get_bid_size(bids))
  #     |> put_in([:orderbook, :ask_size], get_ask_size(asks))

  #   new_state = Map.put(state, pair_as_atom, new_pair)

  #   new_state
  # end

  def handle_received_message(msg, state) do
    IO.puts("toz")
    IO.inspect(msg)
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
    subscription_message = %{command: "subscribe", channel: 1002} |> Jason.encode!()

    subscription_message
  end

  def subscription_to_orderbook_frame_jsonified(symbol) do
    subscription_message =
      %{"command": "subscribe", "channel": symbol}
      |> Jason.encode!()

    subscription_message
  end

  defp get_best_bid(bids) do
    if bids == nil || length(bids) == 0 do
      0
    else
      bid = hd(bids)
      bid["price"]
    end
  end

  defp get_best_ask(asks) do
    if asks == nil || length(asks) == 0 do
      0
    else
      ask = hd(asks)
      ask["price"]
    end
  end

  defp get_bid_size(bids) do
    if bids == nil || length(bids) == 0 do
      0
    else
      bid = hd(bids)
      bid["size"]
    end
  end

  defp get_ask_size(asks) do
    if asks == nil || length(asks) == 0 do
      0
    else
      ask = hd(asks)
      ask["size"]
    end
  end

  def get_pair_as_atom(ch) do
    String.to_atom(ch)
  end
end
