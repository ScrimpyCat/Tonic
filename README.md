Tonic
=====

An Elixir DSL for conveniently loading binary data/files.

The intended goal for this library is to try and create a DSL that describes the structure of the data in a way that is logical (almost 1:1 to the spec of the data), easy to read, and easy to change.


To-Do
-----

 * Automatically use loader on extension and magic number match
 * Pass loading off to another module
 * Convenient types
 * New function: Seek. Ability to seek certain points in the data
 * Change repeat step callback to pass in current length
 * Add a repeat/5 where you can pass in the option whether the list should be reversed or not
