module mem.mol;

import std.traits;

auto mol(alias Obj)()
{

    enum Val(string member) = ReturnType!(__traits(getMember, Obj, member)).stringof;

    string res;

    static foreach (member; __traits(allMembers, Obj))
    {
        res ~= ("Atom!(" ~ Val!member ~ ") " ~ member ~ "_atom;\n");
        
        res ~= ("auto " ~ member ~ "() @nogc {\n");
        res ~= ("   this." ~ member ~ "_atom.calc = &this." ~ member ~ ";\n");
        res ~= ("   return this." ~ member ~ "_atom.get();\n");
        res ~= ("}\n");
        
        res ~= (
                "void " ~ member ~ "(" ~ Val!member ~ " next) @nogc { this."
                ~ member ~ "_atom.put( next ); }\n");
    }

    return res;
}
