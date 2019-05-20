defmodule CexTest do
  use ExUnit.Case
  doctest Cex

  test "greets the world" do
    assert Cex.hello() == :world
  end
end
