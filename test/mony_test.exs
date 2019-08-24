defmodule MonyTest do
  use ExUnit.Case
  doctest Mony

  test "greets the world" do
    assert Mony.hello() == :world
  end
end
