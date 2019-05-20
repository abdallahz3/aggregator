defmodule HuobiClient do
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
  # HuobiClient.start_link [{:btcusdt, "btc_usdt"}]
  #
  #

  def start_link(symbols) do
    WebSockex.start_link("wss://api.huobi.pro/ws", __MODULE__, %{symbols_list: symbols})
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
      subscribe(self(), "market.#{Atom.to_string(a)}.detail")
      subscribe(self(), "market.#{Atom.to_string(a)}.depth.step0")
    end)

    {:ok, new_state}
  end

  def handle_frame({:binary, msg}, state) do
    new_state =
      msg
      |> :zlib.gunzip()
      |> Jason.decode!()
      |> handle_message(state)

    {:ok, new_state}
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  def handle_message(%{"ping" => ts}, state) do
    IO.puts("Got a ping")

    m =
      %{
        "pong" => ts
      }
      |> Jason.encode!()

    send_message(self(), m)

    state
  end

  def handle_message(%{"ch" => ch} = msg, state) do
    if String.ends_with?(ch, "detail") do
      handle_message_ticker(msg, state)
    else
      handle_message_orderbook(msg, state)
    end
  end

  def handle_message_ticker(%{"tick" => tick, "ch" => ch} = msg, state) do
    pair = get_pair_as_atom(ch)

    new_pair =
      state[pair]
      |> Map.put(:high, tick["high"])
      |> Map.put(:low, tick["low"])
      |> Map.put(:timestamp, msg["ts"])
      |> Map.put(:volume, tick["vol"])
      |> Map.put(:exchange_id, "huobi")
      |> Map.put(:symbol, state.symbols_ids[pair])
      |> Map.put(:last_price, tick["close"])

    new_state = Map.put(state, pair, new_pair)


    AggregatorActor.new_message(new_state[pair_as_atom])

    new_state
  end

  def get_pair_as_atom(ch) do
    # the convention is that always the second element represents the pair
    [_, b | _] = String.split(ch, ".")
    String.to_atom(b)
  end

  def handle_message_orderbook(msg, state) do
    %{"ch" => ch, "tick" => %{"bids" => bids, "asks" => asks}} = msg

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

  def handle_message(msg, state) do
    IO.inspect(msg)
    state
  end

  def send_message(pid, msg) do
    WebSockex.cast(pid, {:send, {:text, msg}})
  end

  def handle_cast({:send, {type, msg} = frame}, state) do
    IO.puts("Sending #{type} frame with payload: #{msg}")
    {:reply, frame, state}
  end

  # Helper Functions
  defp subscribe(pid, ch) do
    send_message(pid, subscription_frame(ch))
  end

  def subscription_frame(ch) do
    subscription_message =
      %{
        sub: "#{ch}",
        id: ch
      }
      |> Jason.encode!()

    subscription_message
  end

  defp get_best_bid(bids) do
    bid = hd(bids)
    [price, _] = bid
    price
  end

  defp get_best_ask(asks) do
    ask = hd(asks)
    [price, _] = ask
    price
  end

  defp get_bid_size(bids) do
    bid = hd(bids)
    [_, size] = bid
    size
  end

  defp get_ask_size(asks) do
    ask = hd(asks)
    [_, size] = ask
    size
  end

  defp get_symbol_id_snake_cased(state) do
  end
end
