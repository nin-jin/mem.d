module mem.atom;

import std.container.array, std.variant, std.bitmanip, mem.ready, mem.store, mem.mem;

/** Reactive primitive that calculates, cache and revalidate result. */
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
        Value value;
        Throwable error;
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
