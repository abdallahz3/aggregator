defmodule GateTest do
  use ExUnit.Case
  doctest Gate

  test "greets the world" do
    assert Gate.hello() == :world
  end
end
