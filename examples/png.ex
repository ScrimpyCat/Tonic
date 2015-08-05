#Example PNG loader (parses a few different chunks)
defmodule PNG do
    use Tonic

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
