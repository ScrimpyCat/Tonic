defmodule TonicOptionalTests do
    defmodule OptionalSuccess do
        use ExUnit.Case
        use Tonic

        uint8
        optional do
            uint8
            float32
        end
        uint8

        test "optional statement that succeeds" do
            assert { { 1, 2, 2.5, 3 }, <<>> } == Tonic.load(<<1, 2, 2.5 :: float-size(32)-native, 3>>, __MODULE__)
        end
    end

    defmodule OptionalFailure do
        use ExUnit.Case
        use Tonic

        uint8
        optional do
            uint8
            float32
        end
        uint8

        test "optional statement that fails" do
            assert { { 1, 2 }, <<3>> } == Tonic.load(<<1, 2, 3>>, __MODULE__)
        end
    end

    defmodule OptionalUnnamedSuccess do
        use ExUnit.Case
        use Tonic

        uint8
        optional :float32
        uint8

        test "optional unnamed statement that succeeds" do
            assert { { 1, 2.5, 3 }, <<>> } == Tonic.load(<<1, 2.5 :: float-size(32)-native, 3>>, __MODULE__)
        end
    end

    defmodule OptionalUnnamedFailure do
        use ExUnit.Case
        use Tonic

        uint8
        optional :float32
        uint8

        test "optional unnamed statement that succeeds" do
            assert { { 1, 3 }, <<>> } == Tonic.load(<<1, 3>>, __MODULE__)
        end
    end
end
