module main;

import std.container.array, std.variant, std.stdio, std.traits, std.conv,
    core.stdc.stdio, std.typecons, std.algorithm.mutation, std.bitmanip,
    std.experimental.allocator, std.experimental.allocator.mallocator;

auto mold(alias Val, Args...)(Args args) @nogc
{
    return Mallocator.instance.make!Val(args);
}

void wipe(Val)(Val* val) @nogc
{
    return Mallocator.instance.dispose(val);
}

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

/** Dataflow ready state of Atom */
enum Ready : ubyte
{
    /** Must refresh on access because stale */
    stale = 'S',

    /** Must check masters freshness on access because may be stale */
    doubt = 'D',

    /** @TODO Should throw exception on access because cycle dependency */
    // going = 'G',

    /** Should return cached value instantly on access */
    fresh = 'F',
}

/** What is Atom stores */
enum Store : ubyte
{
    /** Store normal value */
    value = 'V',

    /** Store error info */
    error = 'E',
}

/***/
struct Atom(Value)
{
    // align(1):

    /** Link to current slave with index of next master */
    private struct Cursor
    {
        Atom* slave;
        size_t index;
    }

    @disable this(this); // no postblit
    @disable this(ref Atom source); // no copy constructor

    /** Stack of current calculated atoms */
    private static Cursor cursor;

    private Array!(Atom*) masters; // 8 byte
    private Atom* slave; // 8 byte

    union  // >= 8 byte
    {
        private Value value;
        private Throwable error;
    }

    Value delegate(Mem mem) @nogc calc; // 16 byte

    Ready ready; // 1 byte
    Store store; // 1 byte
    // mixin(bitfields!(Ready, "ready", 2, Store, "store", 1, uint, "", 5,)); // 1 byte

    pragma(msg, Atom.stringof ~ ": " ~ Atom.sizeof.stringof);

    /** Recalculate atom and store result */
    private void refresh() @nogc
    {

        if (this.ready == Ready.doubt)
        {
            foreach (master; this.masters)
            {
                master.refresh;
                if (this.ready == Ready.stale)
                {
                    goto pull;
                }
            }

            this.ready = Ready.fresh;
            return;
        }

        if (this.ready == Ready.stale)
        {
        pull:

            auto cursor = Atom.cursor;
            Atom.cursor = Cursor(&this, 0);
            scope (exit)
            {
                // @todo RAII
                Atom.cursor = cursor;
            }

            try
            {
                this.put(this.calc(Mem()));
            }
            catch (Throwable err)
            {
                this.fail(err);
            }

        }

    }

    /** Tracks this atom as dependency and returns a fresh value or throws an error */
    Value get() @nogc
    {
        if (Atom.cursor.slave !is null)
        {

            scope (exit)
            {
                Atom.cursor.index++;
            }
            
            if(this.slave is null){
                this.slave = Atom.cursor.slave;
            }

            const siblings_lenght = Atom.cursor.slave.masters.length;

            if (siblings_lenght > Atom.cursor.index)
            {
                auto exists = Atom.cursor.slave.masters[Atom.cursor.index];
                if (exists !is null && exists != &this)
                {
                    Atom.cursor.slave.masters ~= exists;
                }
                Atom.cursor.slave.masters[Atom.cursor.index] = &this;
            } else {
                Atom.cursor.slave.masters ~= &this;
            }
        }

        this.refresh();

        if (this.store == Store.value)
        {
            return this.value;
        }
        else
        {
            throw this.error;
        }

        assert(0);
    }

    Value get(Value delegate(Mem mem) @nogc calc) @nogc
    {
        this.calc = calc;
        return this.get;
    }

    void put(Value next) @nogc
    {
        if ((this.store != Store.value) || (this.value != next))
        {
            if (this.slave !is null)
                this.slave.stale;
        }
        this.value = next;
        this.store = Store.value;
        this.ready = Ready.fresh;
    }

    void fail(Throwable next) @nogc
    {
        if ((this.store != Store.error) || (this.error !is next))
            if (this.slave !is null)
                scope (exit)
                    this.slave.stale;
        this.error = next;
        this.store = Store.error;
        this.ready = Ready.fresh;
    }

    void stale() @nogc
    {
        if (this.ready == Ready.stale)
            return;

        this.ready = Ready.stale;

        if (this.slave !is null)
            this.slave.doubt;

    }

    void doubt() @nogc
    {
        if (this.ready == Ready.stale)
            return;
        if (this.ready == Ready.doubt)
            return;

        this.ready = Ready.doubt;

        if (this.slave !is null)
            this.slave.doubt;

    }

}

auto mol(alias Obj)()
{

    enum Val(string member) = ReturnType!(__traits(getMember, Obj, member)).stringof;

    string res;

    static foreach (member; __traits(allMembers, Obj))
    {
        res ~= ("Atom!(" ~ Val!member ~ ") " ~ member ~ "_atom;\n");
        res ~= (
                "auto " ~ member ~ "() @nogc { return this." ~ member
                ~ "_atom.get( &this." ~ member ~ " ); }\n");
        res ~= (
                "void " ~ member ~ "(" ~ Val!member ~ " next) @nogc { this."
                ~ member ~ "_atom.put( next ); }\n");
    }

    return res;
}

struct Mem
{
}

@nogc unittest
{

    struct Card
    {
        mixin(mol!Card);

        ulong foo(Mem _) @nogc
        {
            return 1;
        }

        ulong bar(Mem _) @nogc
        {
            return foo * 2;
        }

    }

    struct Page
    {
        mixin(mol!Page);

        ulong foo(Mem _) @nogc
        {
            return 0;
        }

        Card* card(Mem _) @nogc
        {
            return mold!Card();
        }

        ulong bar(Mem _) @nogc
        {
            return card.bar + 1;
        }

    }

    Page page;

    page.bar.expect(3);
    page.card.foo = 2;
    page.bar.expect(5);

}

void main() @nogc
{
}
