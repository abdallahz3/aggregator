# Aggregator

**TODO: Add description**


To run the application

iex -S mix
AggregatorActor.start_link
KrakenClient.start_link [{:"ETH/USD", "ETH_USD"}]
### similar exchanges like huobi for
HuobiClient.start_link [{:btcusdt, "btc_usdt"}]


---
the convention is start_link takes an array of tuples, the first element of the tuple
is an atom, which corresponds to the string used to subscribe to the tickers
and the second element is the symble snaked-cased

