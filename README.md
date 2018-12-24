Tonic
=====

An Elixir DSL for conveniently loading binary data/files.

The DSL is designed to closely represent the structure of the actual binary data
layout. So it aims to be easy to read, and easy to change.

The DSL defines functionality to represent types, endianness, groups, chunks,
repeated data, branches, optional segments. Where the majority of these functions
can be further extended to customize the behaviour and result.

The default behaviour of these operations is to remove the data that was read from the
current binary data, and append the value to the current block. Values by default are
in the form of a tagged value if a name is supplied `{ :name, value }`, otherwise are
simply `value` if no name is supplied. The default return value behaviour can be
overridden by passing in a function.

The most common types are defined in `Tonic.Types` for convenience. These are
common integer and floating point types, and strings. The behaviour of types can
further be customized when used otherwise new types can be defined using the `type/2`
function.

To use the DSL, call `use Tonic` in your module and include any additional type modules
you may require. Then you are free to write the DSL directly inside the module. Certain
options may be passed to the library on `use`, to indicate additional behaviours. The
currently supported options are:

`optimize:` which can be passed `true` to enable all optimizations, or a keyword list
enabling the specific optimizations. Enabling optimizations may make debugging issues
trickier, so best practice is to enable after it's been tested. Current specific
optimizations include:
```
:reduce #Enables the code reduction optimization, so the generated code is reduced as much as possible.
```

Example
-------
```elixir
defmodule PNG do
    use Tonic, optimize: true

    endian :big
    repeat :magic, 8, :uint8
    repeat :chunks do
        uint32 :length
        string :type, length: 4
        chunk get(:length) do
            on get(:type) do
                "IHDR" ->
                    uint32 :width
                    uint32 :height
                    uint8 :bit_depth
                    uint8 :colour_type
                    uint8 :compression_type
                    uint8 :filter_method
                    uint8 :interlace_method
                "gAMA" ->
                    uint32 :gamma, fn { name, value } -> { name, value / 100000 } end
                "cHRM" ->
                    group :white_point do
                        uint32 :x, fn { name, value } -> { name, value / 100000 } end
                        uint32 :y, fn { name, value } -> { name, value / 100000 } end
                    end
                    group :red do
                        uint32 :x, fn { name, value } -> { name, value / 100000 } end
                        uint32 :y, fn { name, value } -> { name, value / 100000 } end
                    end
                    group :green do
                        uint32 :x, fn { name, value } -> { name, value / 100000 } end
                        uint32 :y, fn { name, value } -> { name, value / 100000 } end
                    end
                    group :blue do
                        uint32 :x, fn { name, value } -> { name, value / 100000 } end
                        uint32 :y, fn { name, value } -> { name, value / 100000 } end
                    end
                "iTXt" ->
                    string :keyword, ?\0
                    string :text
                _ -> repeat :uint8
            end
        end
        uint32 :crc
    end
end

#Example load result:
#{{:magic, [137, 80, 78, 71, 13, 10, 26, 10]},
# {:chunks,
#  [{{:length, 13}, {:type, "IHDR"}, {:width, 48}, {:height, 40},
#    {:bit_depth, 8}, {:colour_type, 6}, {:compression_type, 0},
#    {:filter_method, 0}, {:interlace_method, 0}, {:crc, 3095886193}},
#   {{:length, 4}, {:type, "gAMA"}, {:gamma, 0.45455}, {:crc, 201089285}},
#   {{:length, 32}, {:type, "cHRM"}, {:white_point, {:x, 0.3127}, {:y, 0.329}},
#    {:red, {:x, 0.64}, {:y, 0.33}}, {:green, {:x, 0.3}, {:y, 0.6}},
#    {:blue, {:x, 0.15}, {:y, 0.06}}, {:crc, 2629456188}},
#   {{:length, 345}, {:type, "iTXt"}, {:keyword, "XML:com.adobe.xmp"},
#    {:text,
#     <<0, 0, 0, 0, 60, 120, 58, 120, 109, 112, 109, 101, 116, 97, 32, 120, 109, 108, 110, 115, 58, 120, 61, 34, 97, 100, 111, 98, 101, 58, 110, 115, 58, 109, 101, 116, 97, 47, 34, ...>>},
#    {:crc, 1287792473}},
#   {{:length, 1638}, {:type, "IDAT"},
#    [88, 9, 237, 216, 73, 143, 85, 69, 24, 198, 241, 11, 125, 26, 68, 148, 25,
#     109, 4, 154, 102, 114, 192, 149, 70, 137, 137, 209, 152, 152, 24, 19, 190,
#     131, 75, 22, 234, 55, 224, 59, ...], {:crc, 2269121590}},
#   {{:length, 0}, {:type, "IEND"}, [], {:crc, 2923585666}}]}}
```


To-Do
-----

 * Automatically use loader on extension and magic number match
 * Pass loading off to another module
 * Convenient types
 * New function: Seek. Ability to seek certain points in the data
 * Change repeat step callback to pass in current length
 * Add a repeat/5 where you can pass in the option whether the list should be reversed or not


Installation
------------
```elixir
defp deps do
    [{ :tonic, "~> 0.2.0" }]
end
```
