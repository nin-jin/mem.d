module mem.expect;

version (unittest)
{
    void expect(Val)(Val left, Val right) @nogc
    {
        if (left == right)
            return;
        // throw mold!Error("Unexpected");
        throw cast(Throwable) null; // Enforce stop debugger
    }
}
