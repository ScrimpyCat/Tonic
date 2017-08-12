defmodule TonicEndiannessTest do
    defmodule CustomTypes do
        use Tonic
        type :little_uint16, :uint16, :little
    end

    defmodule EndiannessTest do
        use ExUnit.Case
        use Tonic
        import CustomTypes

        endian :little
        uint16 :a
        endian :big
        uint16 :b
        uint16 :c, :little
        uint16 :d, :big
        little_uint16 :e
        little_uint16 :f, :big

        setup do
            {
                :ok, data: <<
                    1 :: integer-size(16)-unsigned-little,
                    1 :: integer-size(16)-unsigned-big,
                    1 :: integer-size(16)-unsigned-little,
                    1 :: integer-size(16)-unsigned-big,
                    1 :: integer-size(16)-unsigned-little,
                    1 :: integer-size(16)-unsigned-little
                >>
            }
        end

        test "load all values from data with correct endianness", %{ data: data } do
            assert { {
                { :a, 1 },
                { :b, 1 },
                { :c, 1 },
                { :d, 1 },
                { :e, 1 },
                { :f, 1 }
            }, <<>> } == Tonic.load(data, __MODULE__)
        end
    end
end
