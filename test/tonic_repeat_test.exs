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

    defmodule RepeatSingleUnammedTypeBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 4 do
            uint8
        end

        test "four values" do
            assert { { { :values, [{ 1 }, { 2 }, { 3 }, { 4 }] } }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
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

    defmodule RepeatComplexBlock do
        use ExUnit.Case
        use Tonic

        repeat :values, 2 do
            repeat :four, 2 do
                group :test do
                    uint8 :a
                    uint8 :b
                end
            end
            uint8 :c
        end

        test "four values" do
            assert { { { :values, [{ { :four, [{ { :test, { :a, 1 }, { :b, 2 } } }, { { :test, { :a, 3 }, { :b, 4 } } }] }, { :c, 5 } }, { { :four, [{ { :test, { :a, 6 }, { :b, 7 } } }, { { :test, { :a, 8 }, { :b, 9 } } }] }, { :c, 10 } }] } }, <<>> } == Tonic.load(<<1,2,3,4,5,6,7,8,9,10>>, __MODULE__)
        end
    end

    defmodule RepeatBlockWrap do
        use ExUnit.Case
        use Tonic

        repeat :values, 4, fn { name, value } -> value end do
            uint8 :v
        end

        test "four values" do
            assert { { [{ { :v, 1 } }, { { :v, 2 } }, { { :v, 3 } }, { { :v, 4 } }] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end

    defmodule RepeatBlockWrapComplex do
        use ExUnit.Case
        use Tonic

        repeat :values, 4, fn { name, value } ->
            Enum.map value, fn { i } -> i end
        end do
            uint8
        end

        test "four values" do
            assert { { [1, 2, 3, 4] }, <<>> } == Tonic.load(<<1,2,3,4>>, __MODULE__)
        end
    end
end
