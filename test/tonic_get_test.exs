defmodule TonicGetTest do
    defmodule GetValueWithNameTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        repeat :numbers, get(:length), :uint8

        test "load a number of values based on the value of a previously loaded value found through name lookup" do
            assert { { { :length, 4 }, { :numbers, [0,1,2,3] } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithNameWrappedTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        repeat :numbers, get(:length, fn value -> value - 1 end), :uint8

        test "load a number of values based on the value of a previously loaded value found through name lookup wrapping the result" do
            assert { { { :length, 4 }, { :numbers, [0,1,2] } }, <<3>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithFunctionTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        repeat :numbers, get(fn [[length: value]] -> value end), :uint8

        test "load a number of values based on the value of a previously loaded value found through function lookup" do
            assert { { { :length, 4 }, { :numbers, [0,1,2,3] } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithNameWithinSameScopeTest do
        use ExUnit.Case
        use Tonic

        group do
            uint8 :length
            repeat :numbers, get(:length), :uint8
        end

        test "get loaded value using name lookup in same scope" do
            assert { { { { :length, 4 }, { :numbers, [0,1,2,3] } } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithNameInParentScopeTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        group do
            repeat :numbers, get(:length), :uint8
        end

        test "get loaded value using name lookup in parent scope" do
            assert { { { :length, 4 }, { { :numbers, [0,1,2,3] } } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithFunctionInSeparateScopeTest do
        #currently not possible with named gets, as it doesn't convert to var_entry style for different branched scope paths.
        use ExUnit.Case
        use Tonic

        group do: uint8 :length
        group do
            repeat :numbers, get(fn [[], [{ _, { { :length, value } } }]] -> value end), :uint8
        end

        test "get loaded value using function lookup in separate scope" do
            assert { { { { :length, 4 } }, { { :numbers, [0,1,2,3] } } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithNameWithTwoNamedCollisionsInSameScopeTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        uint8 :length
        repeat :numbers, get(:length), :uint8

        test "get loaded value using name lookup, where two of same name exist in same scope" do
            assert { { { :length, 4 }, { :length, 0 }, { :numbers, [] } }, <<1,2,3>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithNameWithTwoNamedCollisionsInSeparateScopesTest do
        use ExUnit.Case
        use Tonic

        uint8 :length
        group do
            uint8 :length
            repeat :numbers, get(:length), :uint8
        end

        test "get loaded value using name lookup, where two of same name exist in separate scopes" do
            assert { { { :length, 4 }, { { :length, 0 }, { :numbers, [] } } }, <<1,2,3>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end

    defmodule GetValueWithStrippedNameTest do
        use ExUnit.Case
        use Tonic

        uint8 :length, fn { _, value } -> value end
        repeat :numbers, get(:length), :uint8

        test "get loaded value using name lookup, where name has been stripped from the loaded value entry" do
            assert { { 4, { :numbers, [0,1,2,3] } }, <<>> } == Tonic.load(<<4,0,1,2,3>>, __MODULE__)
        end
    end
end
