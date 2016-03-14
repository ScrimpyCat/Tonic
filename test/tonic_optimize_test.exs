defmodule TonicOptimizeTests do
    defmodule Convenience do
        def load_functions(module), do: Enum.filter(module.__info__(:functions), fn { name, _ } -> String.starts_with?(to_string(name), "load") end)
    end

    defmodule EnableAllOptimizations do
        use ExUnit.Case
        use Tonic, optimize: true

        test "reduce optimization enabled" do
            assert @tonic_enable_optimization[:reduce] == true
        end
    end

    defmodule DisableAllOptimizations do
        use ExUnit.Case
        use Tonic, optimize: false

        test "reduce optimization disabled" do
            assert @tonic_enable_optimization[:reduce] == false
        end
    end

    defmodule ReduceOptimization do
        import Convenience
        use ExUnit.Case
        use Tonic, optimize: [reduce: true]

        group :a do
            uint8
        end

        group :b do
            uint8
        end
        
        test "functions correctly" do
            assert { { { :a, 1 }, { :b, 2 } }, <<>> } == Tonic.load(<<1,2>>, __MODULE__)
        end

        test "reduce optimization enabled" do
            assert @tonic_enable_optimization[:reduce] == true
        end

        test "duplicates removed" do
            assert load_functions(__MODULE__) |> Enum.count == 2
        end
    end

    defmodule NoReduceOptimization do
        import Convenience
        use ExUnit.Case
        use Tonic, optimize: [reduce: false]

        group :a do
            uint8
        end

        group :b do
            uint8
        end
        
        test "functions correctly" do
            assert { { { :a, 1 }, { :b, 2 } }, <<>> } == Tonic.load(<<1,2>>, __MODULE__)
        end

        test "reduce optimization enabled" do
            assert @tonic_enable_optimization[:reduce] == false
        end

        test "duplicates removed" do
            assert load_functions(__MODULE__) |> Enum.count == 3
        end
    end
end
