defmodule ZbClient do
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
  # ZbClient.start_link [{:ltcbtc, "ltc_btc"}, {:btcusdt, "btc_usdt"}]
  #
  #

  def start_link(symbols) do
    WebSockex.start_link("wss://api.zb.cn/websocket", __MODULE__, %{symbols_list: symbols})
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
        acc = put_in(acc, [a, :orderbook], %{ask: 0, bid: 0, ask_size: 0, bid_size: 0})
        acc
      end)

    new_state = Map.merge(new_state, s)

    Enum.each(state.symbols_list, fn {a, _} ->
      send_message(self(), subscription_to_orderbook_frame_jsonified(a))
      send_message(self(), subscription_to_ticker_frame_jsonified(a))
    end)

    {:ok, new_state}
  end

  def handle_frame({:text, msg}, state) do
    {:ok, msg_decoded} = msg |> Jason.decode()

    new_state =
      if String.ends_with?(msg_decoded["channel"], "_ticker") do
        handle_message_ticker(msg_decoded, state)
      else
        handle_message_orderbook(msg_decoded, state)
      end

    {:ok, new_state}
  end

  def handle_frame(frame, state) do
    IO.inspect(frame)
    {:ok, state}
  end

  def handle_message_ticker(%{"ticker" => ticker, "channel" => ch} = msg, state) do
    pair_as_atom = get_pair_as_atom(ch)

    new_pair =
      state[pair_as_atom]
      |> Map.put(:high, ticker["high"])
      |> Map.put(:low, ticker["low"])
      |> Map.put(:timestamp, String.to_integer(msg["date"]))
      |> Map.put(:volume, ticker["vol"])
      |> Map.put(:exchange_id, "zb")
      |> Map.put(:symbol, state.symbols_ids[pair_as_atom])
      |> Map.put(:last_price, ticker["last"])

    new_state = Map.put(state, pair_as_atom, new_pair)

    AggregatorActor.new_message(new_state[pair_as_atom])

    new_state
  end

  def get_pair_as_atom(ch) do
    t =
      if String.ends_with?(ch, "_ticker") do
        String.slice(ch, 0..-(String.length("_ticker") + 1))
      else
        String.slice(ch, 0..-(String.length("_depth") + 1))
      end

    String.to_atom(t)
  end

  def handle_message_orderbook(msg, state) do
    %{"channel" => ch, "bids" => bids, "asks" => asks} = msg

    pair = get_pair_as_atom(ch)

    new_pair =
      state[pair]
      |> put_in([:orderbook, :bid], get_best_bid(bids))
      |> put_in([:orderbook, :ask], get_best_ask(asks))
      |> put_in([:orderbook, :bid_size], get_bid_size(bids))
      |> put_in([:orderbook, :ask_size], get_ask_size(asks))

    new_state = Map.put(state, pair, new_pair)

    new_state
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
        event: "addChannel",
        channel: "#{symbol}_ticker"
      }
      |> Jason.encode!()

    subscription_message
  end

  def subscription_to_orderbook_frame_jsonified(symbol) do
    subscription_message =
      %{
        event: "addChannel",
        channel: "#{symbol}_depth"
      }
      |> Jason.encode!()

    subscription_message
  end

  defp get_best_bid(bids) do
    if bids == nil || length(bids) == 0 do
      0
    else
      [p, _] = hd(bids)
      p
    end
  end

  defp get_best_ask(asks) do
    if asks == nil || length(asks) == 0 do
      0
    else
      [a, _] = hd(asks)
      a
    end
  end

  defp get_bid_size(bids) do
    if bids == nil || length(bids) == 0 do
      0
    else
      [_, a] = hd(bids)
      a
    end
  end

  defp get_ask_size(asks) do
    if asks == nil || length(asks) == 0 do
      0
    else
      [_, a] = hd(asks)
      a
    end
  end
end
