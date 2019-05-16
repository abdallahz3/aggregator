defmodule KrakenTest do
  use ExUnit.Case
  doctest Kraken

  test "greets the world" do
    assert Kraken.hello() == :world
  end
end
