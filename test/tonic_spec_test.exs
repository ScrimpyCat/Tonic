defmodule TonicSpecTests do
    defmodule Recursive do
        use ExUnit.Case
        use Tonic

        uint8()
        optional do: spec()

        test "run the spec recursively" do
            assert { { 1, { 2, { 3 } } }, <<>> } == Tonic.load(<<1, 2, 3>>, __MODULE__)
        end
    end

    defmodule ExecuteSpec do
        use ExUnit.Case
        use Tonic

        uint8 :a
        group :spec do
            chunk 2 do
                spec Recursive
            end
        end
        uint8 :b

        test "run the target spec" do
            assert { { { :a, 1 }, { :spec, { 2, { 3 } } }, { :b, 4 } }, <<>> } == Tonic.load(<<1, 2, 3, 4>>, __MODULE__)
        end
    end

    defmodule OtherSpec do
        use Tonic

        uint16()
    end

    defmodule InheritingEndianness do
        use ExUnit.Case
        use Tonic

        endian :big
        spec OtherSpec

        endian :little
        spec OtherSpec

        test "run the target spec with different endianness" do
            assert { { { 1 }, { 2 } }, <<>> } == Tonic.load(<<0, 1, 2, 0>>, __MODULE__)
        end
    end

    defmodule ScopedSpec do
        use Tonic

        on get(fn [[]] -> :ok end) do
            :ok -> uint8 :b
        end

        uint8 :c

        on get(fn [[c: 3, b: 2]] -> :ok end) do
            :ok -> uint8 :d
        end
    end

    defmodule LocallyScoped do
        use ExUnit.Case
        use Tonic

        uint8 :a
        spec ScopedSpec

        on get(fn [[{ TonicSpecTests.ScopedSpec, { { :b, 2 }, { :c, 3 }, { :d, 4 } } }, { :a, 1 }]] -> :ok end) do
            :ok -> uint8 :e
        end

        test "check the target specs scope" do
            assert { { { :a, 1 }, { { :b, 2 }, { :c, 3 }, { :d, 4 } }, { :e, 5 } }, <<>> } == Tonic.load(<<1, 2, 3, 4, 5>>, __MODULE__)
        end
    end
end
