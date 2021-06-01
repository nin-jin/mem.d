module mem.atom;

import std.container.array, std.variant, std.bitmanip, mem.mem;

/** Reactive primitive that calculates, cache and revalidate result. */
struct Atom(Value)
{
    // align(1):

    /** Link to peer with index of back link in complement array */
    private struct Link
    {
        Atom* atom;
        size_t index;
        
        Link back() @nogc
        {
            return this.atom.peers[this.index];
        }
    }

    @disable this(this); // no postblit
    @disable this(ref Atom source); // no copy constructor

    /** Current calculating atoms */
    private static Link current;

    private Array!Link peers; // 8 byte

    union  // >= 8 byte
    {
        Value value;
        Throwable error;
    }

    mixin(bitfields!(bool, "fresh", 1, bool, "done", 1, size_t, "slaves_from", 62)); // 4 bytes

    pragma(msg, Atom.stringof ~ ": " ~ Atom.sizeof.stringof);
    pragma(msg, Link.stringof ~ ": " ~ Link.sizeof.stringof);

    /** Moves peer from one position to another. Doesn't clear data at old position! */
    private void move_link(size_t from_pos, size_t to_pos) @nogc
    {
        if (from_pos == to_pos)
            return;

        auto link = this.peers[from_pos];

        if (to_pos == this.peers.length)
            this.peers ~= link;
        else
            this.peers[to_pos] = link;

        link.back.index = to_pos;
    }

    private void escape_slave(size_t pos) @nogc
    {
        if (pos >= this.peers.length)
            return;

        this.move_link(pos, this.peers.length);
    }

    private void escape_master(size_t pos) @nogc
    {
        if (pos >= this.peers.length)
            return;

        this.escape_slave(this.slaves_from);
        this.move_link(pos, this.slaves_from);
        this.slaves_from = this.slaves_from + 1;
    }

    private void fill_slave(size_t pos) @nogc
    {
        if (pos == this.peers.length)
            return;
        this.move_link(this.peers.length - 1, pos);
        this.peers.length = this.peers.length - 1;
    }

    private void fill_master(size_t pos) @nogc
    {
        this.slaves_from = this.slaves_from - 1;
        this.move_link(this.slaves_from, pos);
        this.fill_slave(this.slaves_from);
    }

    /** Tracks this atom as dependency and returns a fresh value or throws an error */
    Value get(Value delegate(Mem) @nogc task) @nogc
    {
        // Recalculate when required
        if (!this.fresh)
        {

            auto current = Atom.current;
            Atom.current = Link(&this, 0);
            scope (exit)
                Atom.current = current;

            try
            {
                this.put(task(Mem()));
            }
            catch (Throwable err)
            {
                this.fail(err);
            }

        }

        // Link with currently calculated atom
        if (Atom.current.atom !is null)
        {

            scope (exit)
                Atom.current.index++;

            if (Atom.current.index < Atom.current.atom.slaves_from)
            {
                if (Atom.current.back.atom != &this)
                {
                    Atom.current.atom.escape_master(Atom.current.index);
                    Atom.current.atom.peers[Atom.current.index] = Link(&this, this.peers.length);
                    this.peers ~= Atom.current;
                }
            }
            else
            {
                if (Atom.current.atom.peers.length != Atom.current.atom.slaves_from)
                    Atom.current.atom.escape_slave(Atom.current.index);

                if (Atom.current.index == Atom.current.atom.peers.length)
                    Atom.current.atom.peers ~= Link(&this, this.peers.length);
                else
                    Atom.current.atom.peers[Atom.current.index] = Link(&this, this.peers.length);

                this.peers ~= Atom.current;

            }

        }

        // Return actual cached value
        if (this.done)
            return this.value;
        else
            throw this.error;

        assert(0);
    }

    void put(Value next) @nogc
    {
        this.stale();
        this.value = next;
        this.done = true;
        this.fresh = true;
    }

    void fail(Throwable next) @nogc
    {
        this.stale();
        this.error = next;
        this.done = false;
        this.fresh = true;
    }

    void stale_slaves() @nogc
    {
    }

    void stale() @nogc
    {
        if (!this.fresh)
            return;

        this.fresh = false;

        foreach (slave; this.peers[this.slaves_from .. $])
            slave.atom.stale();

    }

}
