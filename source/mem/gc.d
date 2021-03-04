module mem.gc;

import std.experimental.allocator, std.experimental.allocator.mallocator;

auto mold(alias Val, Args...)(Args args) @nogc
{
    return Mallocator.instance.make!Val(args);
}

void wipe(Val)(Val* val) @nogc
{
    return Mallocator.instance.dispose(val);
}
