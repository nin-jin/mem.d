module mem.main;

public import mem.gc, mem.mol, mem.mem, mem.atom, mem.expect;

/** Caching */
@nogc unittest
{

    struct Random
    {
        mixin(mol!Random);
        
        ulong number(Mem _) @nogc
        {
            return this.number_atom.value + 1;
        }

    }

    Random random;

    random.number.expect(1);
    random.number.expect(1);

}

/** Revalidate closes slaves */
@nogc unittest
{

    struct Multiplier
    {
        mixin(mol!Multiplier);
        
        ulong source(Mem _) @nogc
        {
            return 2;
        }

        ulong result(Mem _) @nogc
        {
            return this.source * 5;
        }

    }

    Multiplier multiplier;
    multiplier.result.expect(10);

    multiplier.source = 3;
    multiplier.result.expect(15);

}

/** Complex example */
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
