defmodule TonicRepeatTests do
    defmodule EmptyRepeat do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
        end
        
        test "empty repeat" do
            assert { { { :values, [{}, {}, {}, {}] } }, <<1,2,3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatZeroTimes do
        use ExUnit.Case
        use Tonic

        repeat :values, 0 do
        end
        
        test "empty repeat" do
            assert { { { :values, [] } }, <<1,2,3,4>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatSingleTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
            uint8 :v
        end

        test "four values" do
            assert { { { :values, [{ { :v, 1 } }, { { :v, 2 } }, { { :v, 3 } }, { { :v, 4 } }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 2 do
            uint8 :a
            uint8 :b
        end

        test "four values" do
            assert { { { :values, [{ { :a, 1 }, { :b, 2 } }, { { :a, 3 }, { :b, 4 } }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end
end
