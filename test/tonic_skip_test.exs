defmodule TonicSkipTests do
    defmodule SkipSingle do
        use ExUnit.Case
        use Tonic

        uint8
        skip :float32
        uint8

        test "skip a single type" do
            assert { { 1, 3 }, <<>> } == Tonic.load(<<1, 2.5 :: float-size(32)-native, 3>>, __MODULE__)
        end
    end

    defmodule SkipBlock do
        use ExUnit.Case
        use Tonic

        uint8
        skip do
            uint8
            float32
        end
        uint8

        test "skip a collection of types" do
            assert { { 1, 3 }, <<>> } == Tonic.load(<<1, 2, 2.5 :: float-size(32)-native, 3>>, __MODULE__)
        end
    end
end
