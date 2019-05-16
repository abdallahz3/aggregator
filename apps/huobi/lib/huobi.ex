defmodule HuobiClient do
  use WebSockex

  @url "wss://api.huobi.pro/ws"
  # @url "ws://demos.kaazing.com/echo"

  def start_link(symbols) do
    # kline = "market.#{pair}.detail"
    # depth = "#{pair}.depth.step0"

    symbols2 =
      Enum.map(symbols, fn symbol ->
        %{kline: "market.#{symbol}.detail", depth: "market.#{symbol}.depth.step0"}
      end)

    try_connect(symbols2, 1000)
  end

  def try_connect(symbols, backoff_time) do
    case WebSockex.start_link(
           @url,
           __MODULE__,
           %{
             symbols: symbols
           }
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        IO.puts("Error starting.")
        IO.inspect(reason)
        # {:error, reason}
        # {:shutdown, reason}
        # :ignore
        :timer.sleep(backoff_time)
        try_connect(symbols, backoff_time * 2)
    end
  end

  def init(state) do
    IO.puts("state")
    IO.inspect(state)
    # Enum.each 
    # subscribe(pair, depth, "depth")
  end

  # Handlers of received messages
  def handle_message(%{"ping" => ts}, state) do
    # IO.puts("Got a ping")

    m =
      %{
        "pong" => ts
      }
      |> Jason.encode!()

    send_message(state.process_name, m)

    state
  end

  def handle_message(msg, state) do
    kline = state.kline
    depth = state.depth

    new_state =
      case msg["ch"] do
        ^kline -> handle_message_kline(msg, state)
        ^depth -> handle_message_depth(msg, state)
        _ -> state
      end

    new_state
  end

  # def handle_message_kline(%{"ch" => @kline, "tick" => tick} = msg, state) do
  def handle_message_kline(%{"tick" => tick} = msg, state) do
    new_state =
      state
      |> Map.put(:high, tick["high"])
      |> Map.put(:low, tick["low"])
      |> Map.put(:timestamp, msg["ts"])
      |> Map.put(:volume, tick["vol"])
      |> Map.put(:exchange_id, "huobi")
      |> Map.put(:symbol, state.pair_as_string)
      |> Map.put(:last_price, tick["close"])

    # check if at least we received a depth once
    if Map.has_key?(new_state.latest_depth, :bid) do
      # IO.inspect new_state 
      Huobi.Aggregator.new_message(new_state)
    end

    new_state
  end

  # def handle_message_depth(%{"ch" => @depth, "tick" => %{"bids" => bids, "asks" => asks}} = msg, state) do
  def handle_message_depth(%{"tick" => %{"bids" => bids, "asks" => asks}}, state) do
    new_state =
      state
      |> put_in([:latest_depth, :bid], get_best_bid(bids))
      |> put_in([:latest_depth, :ask], get_best_ask(asks))
      |> put_in([:latest_depth, :bid_size], get_bid_size(bids))
      |> put_in([:latest_depth, :ask_size], get_ask_size(asks))

    new_state
  end

  # Client API
  def send_message(process_name, msg) do
    WebSockex.cast(process_name, {:send, {:text, msg}})
  end

  # Server API
  def handle_cast({:send, frame}, state) do
    {:reply, frame, state}
  end

  # Callbacks
  def handle_connect(_conn, state) do
    IO.puts("Connected #{state.process_name}")
    {:ok, state}
  end

  def handle_disconnect(_conn, state) do
    IO.puts("Disconnected #{state.process_name}")
    {:ok, state}
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

  # Helper Functions
  defp subscribe(pid, ch, id) do
    send_message(pid, subscription_frame(ch, id))
  end

  def subscription_frame(ch, id) do
    subscription_message =
      %{
        sub: "#{ch}",
        # id: "#{ch}"
        id: id
      }
      |> Jason.encode!()

    # {:text, subscription_message}
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
end
