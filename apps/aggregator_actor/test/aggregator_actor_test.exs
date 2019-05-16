defmodule AggregatorActorTest do
  use ExUnit.Case
  doctest AggregatorActor

  test "greets the world" do
    assert AggregatorActor.hello() == :world
  end
end
