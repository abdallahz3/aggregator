defmodule KrakenClient do
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
  #    },
  #    channels_map: {
  #    integer to atom
  #    }
  # }
  #
  #
  #
  #

  def start_link(symbols) do
    WebSockex.start_link("wss://ws.kraken.com", __MODULE__, %{symbols_list: symbols})
  end

  def handle_connect(_conn, state) do
    IO.puts("Connected")

    # symbols is array of tuples the first is the pair, the second is the pair in snake case
    # symbols_ids is a map from pairs to pairs is snake case
    symbols_ids =
      Enum.reduce(state.symbols_list, %{}, fn {a, b}, acc -> Map.put_new(acc, a, b) end)

    new_state = %{}
    new_state = put_in(new_state, [:symbols_ids], symbols_ids)

    # what this will do is add pairs to a map and then we merge this map with state so it matches the
    # state structure, see above
    s =
      Enum.reduce(state.symbols_list, %{}, fn {a, _}, acc ->
        acc = put_in(acc, [a], %{})
        acc = put_in(acc, [a, :orderbook], %{ask: 0, bid: 0, ask_size: 0, bid_size: 0})
        acc
      end)

    new_state = Map.merge(new_state, s)

    # channels_map serves as mapping from numbers to atoms
    # the reason for that is kraken for ticker returns [ch_num, tick], ch_num is first sent when you
    # subscribe successfully to a channels, so we need to keep track of what symbol matches whan ch_num
    # channels_map serves for that purpose
    new_state = put_in(new_state, [:channels_map], %{})

    l =
      Enum.map(state.symbols_list, fn {a, _} ->
        a
      end)

    subscribe(self(), l)

    {:ok, new_state}
  end

  def handle_frame({_type, msg}, state) do
    new_state =
      msg
      |> Jason.decode!()
      |> handle_received_message(state)

    {:ok, new_state}
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  def handle_received_message(%{"event" => "heartbeat"}, state) do
    IO.inspect(%{"event" => "heartbeat"})
    state
  end

  def handle_received_message(
        %{
          "channelID" => channel_id,
          "event" => "subscriptionStatus",
          "pair" => pair,
          "status" => "subscribed",
          "subscription" => %{"name" => "ticker"}
        } = msg,
        state
      ) do
    new_state = put_in(state, [:channels_map, channel_id], String.to_atom(pair))
    new_state
  end

  def handle_received_message(
        %{
          "channelID" => channel_id,
          "event" => "subscriptionStatus",
          "pair" => pair,
          "status" => "subscribed",
          "subscription" => %{"name" => "book"}
        } = msg,
        state
      ) do
    new_state = put_in(state, [:channels_map, channel_id], String.to_atom(pair))
    new_state
  end

  def handle_received_message([channel_id, tick] = msg, state) do
    pair_as_atom = state.channels_map[channel_id]
    state = update_ticker(state, pair_as_atom, tick)

    AggregatorActor.new_message(state[pair_as_atom])

    state
  end

  def handle_received_message([channel_id, %{"a" => asks}, %{"b" => bids}] = msg, state) do
    pair = state[state.channels_map[channel_id]]

    new_pair =
      pair
      |> put_in([:orderbook, :bid], get_best_bid(bids))
      |> put_in([:orderbook, :ask], get_best_ask(asks))
      |> put_in([:orderbook, :bid_size], get_bid_size(bids))
      |> put_in([:orderbook, :ask_size], get_ask_size(asks))

    new_state = Map.put(state, state.channels_map[channel_id], new_pair)

    new_state
  end

  def handle_received_message(msg, state) do
    IO.puts("message not handled")
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

  # Helper Functions
  defp subscribe(pid, sm) do
    send_message(pid, subscription_to_tickers_frame_jsonified(sm))
    # send_message(pid, subscription_to_orderbook_frame_jsonified(sm))
  end

  # symbols list is a list of strings, not a list of tuples
  def subscription_to_tickers_frame_jsonified(symbols_list) do
    subscription_message =
      %{
        event: "subscribe",
        pair: symbols_list,
        # pair: ["BTC/USD"],
        subscription: %{
          name: "ticker"
        }
      }
      |> Jason.encode!()

    subscription_message
  end

  def subscription_to_orderbook_frame_jsonified(symbols_list) do
    subscription_message =
      %{
        event: "subscribe",
        pair: symbols_list,
        # pair: ["BTC/USD"],
        subscription: %{
          name: "book"
        }
      }
      |> Jason.encode!()

    subscription_message
  end

  defp get_best_bid(bids) do
    bid = hd(bids)
    [price, _, _] = bid
    price
  end

  defp get_best_ask(asks) do
    ask = hd(asks)
    [price, _, _] = ask
    price
  end

  defp get_bid_size(bids) do
    bid = hd(bids)
    [_, size, _] = bid
    size
  end

  defp get_ask_size(asks) do
    ask = hd(asks)
    [_, size, _] = ask
    size
  end

  def update_ticker(state, pair_as_atom, tick) do
    pair = state[pair_as_atom]

    pair =
      if Map.has_key?(tick, "a") do
        [p, _, s] = tick["a"]
        put_in(pair, [:orderbook, :ask], p) |> put_in([:orderbook, :ask_size], s)
      end

    pair =
      if Map.has_key?(tick, "b") do
        [p, _, s] = tick["b"]
        put_in(pair, [:orderbook, :bid], p) |> put_in([:orderbook, :bid_size], s)
      end

    pair =
      if Map.has_key?(tick, "h") do
        [h, _] = tick["h"]
        put_in(pair, [:h], h)
      end

    pair =
      if Map.has_key?(tick, "l") do
        [l, _] = tick["l"]
        put_in(pair, [:l], l)
      end

    pair =
      if Map.has_key?(tick, "v") do
        [v, _] = tick["v"]
        put_in(pair, [:v], v)
      end

    new_state = Map.put(state, pair_as_atom, pair)

    new_state
  end
end
