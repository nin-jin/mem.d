module mem.ready;

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
