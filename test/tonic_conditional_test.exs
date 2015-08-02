defmodule TonicConditionalTests do
    defmodule SimpleOn do
        use ExUnit.Case
        use Tonic

        uint8 :type
        on get(:type) do
            1 -> uint32
            2 -> float32
        end

        test "simple on statement" do
            assert { { { :type, 2 }, 2.5 }, <<>> } == Tonic.load(<<2, 2.5 :: float-size(32)-native>>, __MODULE__)
        end
    end

    defmodule ScopeOn do
        use ExUnit.Case
        use Tonic

        endian :little
        uint32 :type
        on get(:type) do
            1 -> endian :little
            2 -> endian :big
        end
        float32

        test "correct scoping for on statement" do
            assert { { { :type, 2 }, 2.5 }, <<>> } == Tonic.load(<<2 :: integer-size(32)-little, 2.5 :: float-size(32)-big>>, __MODULE__)
        end
    end

    defmodule MultilineOn do
        use ExUnit.Case
        use Tonic

        uint8 :type, fn { _, v } -> v end
        on get(:type) do
            1 -> 
                uint32
                uint32
                group do
                    float32
                end
            2 -> float32
        end

        test "multiline statement" do
            assert { { 1, 15, 123, { 2.5 } }, <<>> } == Tonic.load(<<
                1, 
                    15 :: integer-size(32)-native,
                    123 :: integer-size(32)-native,
                    2.5 :: float-size(32)-native
            >>, __MODULE__)
        end
    end

    defmodule OnGuards do
        use ExUnit.Case
        use Tonic

        uint8 :type, fn
            { _, 1 } -> 1
            { _, 2 } -> :float
        end
        on get(:type) do
            a when is_integer(a) -> uint32
            b when is_atom(b) -> float32
        end

        test "on statement with guards" do
            assert { { :float, 2.5 }, <<>> } == Tonic.load(<<2, 2.5 :: float-size(32)-native>>, __MODULE__)
        end
    end

    defmodule NestedOn do
        use ExUnit.Case
        use Tonic

        uint8 :type, fn { _, v } -> v end
        uint8 :type2, fn { _, v } -> v end
        on get(:type) do
            1 ->
                on get(:type2) do
                    2 -> uint8 :three
                end
            2 -> float32
        end

        test "nested on statement" do
            assert { { 1, 2, { :three, 3 } }, <<4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end
end
