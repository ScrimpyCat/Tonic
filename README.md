Tonic
=====

An Elixir DSL for conveniently loading binary data/files.


Work In Progress
----------------

It is currently a work in progress, and as it stands isn't particularly useful at the moment.


To-Do
-----

 * Automatically use loader on extension and magic number match
 * Pass loading off to another module
 * Convenient types
 * New function: Seek. Ability to seek certain points in the data
 * New function: Block/Chunk/Binary. Be able to specify a new chunk of binary data. E.g. so operations within that block are relative to that new chunk. An unspecified length repeat will only repeat till the end of that chunk and not the entire binary data
 * Change optionals? Possibly change them so they check for match errors after the optional sequence. So if there's an error it will then remove the optional sequence and try again. e.g. if you have a sequence of 1 byte, 2 optional bytes, 1 byte; with the current usage if the data contained 3 bytes it would include the optional and would report a match error (for the 4th byte), with this adjustment the optional would not be used and there would be 1 byte (the 3rd) still left unprocessed in the binary data.
 * Change repeat step callback to pass in current length
 * Add a repeat/5 where you can pass in the option whether the list should be reversed or not
