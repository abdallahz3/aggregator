defmodule ZbTest do
  use ExUnit.Case
  doctest Zb

  test "greets the world" do
    assert Zb.hello() == :world
  end
end
