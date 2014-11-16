defmodule TonicStringTests do
    defmodule StringTillEnd do
        use ExUnit.Case
        use Tonic

        string :name
        
        test "string with no options" do
            assert { { { :name, "12345678" } }, <<>> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule StringLength do
        use ExUnit.Case
        use Tonic

        string :name, length: 4
        
        test "string with length" do
            assert { { { :name, "1234" } }, <<"5678">> } == Tonic.load(<<"12345678">>, __MODULE__)
        end
    end

    defmodule StringNullTerminator do
        use ExUnit.Case
        use Tonic

        string :name, 0

        test "string with null terminator" do
            assert { { { :name, "1234" } }, <<"5678">> } == Tonic.load(<<"1234", 0, "5678">>, __MODULE__)
        end
    end

    defmodule StringLengthWithNullTerminator do
        use ExUnit.Case
        use Tonic

        string :name, length: 5, terminator: ?\n
        string :name, length: 5, terminator: ?\n
        
        test "string with length" do
            assert { { { :name, "1234" }, { :name, "56789" } }, <<"\n">> } == Tonic.load(<<"1234\n56789\n">>, __MODULE__)
        end
    end
end
